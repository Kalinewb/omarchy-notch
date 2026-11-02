#!/bin/bash

# The quiet settings panel (plan-settings.md), as numbers.
#
#   ./dev/settings.sh
#
# Runs the real Bar.qml in a throwaway notch whose host keeps the shell config
# in memory (dev/harness/settings-shell.qml), and reads what the panel and the
# notch report over IPC (`settingsReport`, `snapshot`). Nothing live is touched.
# No stopwatch checks: every wait is `settle`, a poll of the report until it
# says what the check is about.
#
#   1   the shape: rows are a label and one of six controls, in sections one deep;
#       the retired components, wraps and captions are gone from the source
#   2   the ratchet: 8 visible rows by default (9 when plan-glow.md P4 shows Notification
#       light), 19 behind Advanced, 32 in all, a
#       file that only shrinks; the default view fits without scrolling
#   3   the tips: one per row id, short, one sentence, none that repeats its label
#   4   Advanced is closed on open, opens on press, and is closed again on reopen
#   5   the foot line: its delays (parsed from NotchTip.qml), when a tip pends,
#       shows, swaps and goes, that it never moves the panel, and fits all 28
#   6   the state on the right, and the merged rows' one write each
#   7   the keys the panel has no row for still work, still change, and survive
#       a write -- true of the panel as it was before the rows moved
#   8   every key the notch reads is decided: on a row, or listed as rowless
#   9   the keyboard: the row cursor on all six controls, Escape's order, the
#       recorder suspending it, the cursor row always inside the view
#   10  the badges and the header: counts only above 0, only on header buttons, the
#       buttons overlapping neither the title nor each other
#   11  the settings panel's height is the one thing the contract may change

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-settings.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/settings-shell.qml" "$root/shell.qml"

ipc() { quickshell ipc -p "$root" call "${TARGET:-notch}" "$@" 2>/dev/null; }
XENV=()   # more environment for the next start, set by the check that wants it
start() {
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 "${XENV[@]}" NOTCH_HARNESS_CONFIG="$1" quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  sleep 0.5
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }
report() { ipc settingsReport; }
# settle <jq filter on settingsReport>: wait up to 3 s for it to be true.
settle() {
  for _ in $(seq 1 60); do [[ $(report | jq -r "$1" 2>/dev/null) == true ]] && return 0; sleep 0.05; done
  return 1
}

echo "${BOLD}The quiet settings panel${RESET}  ${DIM}plugin: $REPO${RESET}"

# ---------------------------------------------------------------------------
# 3  Tips
# ---------------------------------------------------------------------------
echo; echo "${BOLD}3  Tips${RESET}"
ROWS="atRest autoHide glow openWith opensTo notifications notifyLight menu volume width onHover hidden openRow panels corners notifyTime lightColours peeks glowSize greenAbove lowBelow keybinds stayOpen windowsToTop updateCheck share importer reset"
tips=$(python3 - "$REPO/settings-tips.js" "$ROWS" <<'PY'
import json, re, sys
src = open(sys.argv[1]).read()
rows = sys.argv[2].split()
labels = {
  "atRest": "At rest", "autoHide": "Auto-hide", "glow": "Charging glow", "openWith": "Open with", "opensTo": "Opens to",
  "notifications": "Notifications", "notifyLight": "Notification light", "menu": "Menu", "volume": "Volume and brightness",
  "width": "Width", "onHover": "On hover", "hidden": "Hidden widgets", "openRow": "Also in the widget row", "panels": "Panels",
  "corners": "Corners", "notifyTime": "Notification time", "lightColours": "Light colours", "peeks": "Peeks",
  "glowSize": "Glow size", "greenAbove": "Green from", "lowBelow": "Low battery at", "keybinds": "Keybinds",
  "stayOpen": "Keep open", "windowsToTop": "Windows to the top", "updateCheck": "Check for updates",
  "share": "Share settings", "importer": "Use someone's settings", "reset": "Reset to defaults"}
block = re.search(r"var t = \{(.*?)\n\}", src, re.S).group(1)
tips = dict(re.findall(r'^\s+(\w+):\s+"(.*)",?\s*$', block, re.M))
noRow = re.findall(r'"(\w+)"', re.search(r"var noRow = \[(.*?)\]", src, re.S).group(1))
bad = []
for i, tip in tips.items():
    label = labels.get(i, "").lower()
    low = tip.lower()
    if len(tip) > 60: bad.append(f"{i}: {len(tip)} characters")
    if "." in tip or "\n" in tip: bad.append(f"{i}: a full stop")
    if not tip[:1].isupper(): bad.append(f"{i}: does not start a sentence")
    if label and (low.startswith(label) or label in low): bad.append(f"{i}: repeats its label")
print(json.dumps({"ids": sorted(tips), "want": sorted(rows), "bad": bad, "unique": len(set(tips.values())) == len(tips),
                  "longest": max(len(v) for v in tips.values()), "labelled": sorted(labels) == sorted(rows),
                  "noRow": len(noRow), "noRowUnique": len(set(noRow)) == len(noRow)}))
PY
)
check "one tip per row id: 28, none missing, none extra" "28 true" "$(jq -r '"\(.ids | length) \(.ids == .want)"' <<<"$tips")"
check "every tip is at most 60 characters, one sentence, no full stop, never its label" "" "$(jq -r '.bad | join("; ")' <<<"$tips")"
check "every tip is different" "true" "$(jq -r .unique <<<"$tips")"
check "the label table here covers exactly the 28 row ids" "true" "$(jq -r .labelled <<<"$tips")"
check "the 17 rowless keys are listed once each" "17 true" "$(jq -r '"\(.noRow) \(.noRowUnique)"' <<<"$tips")"

start '{"batteryPeek":false}'
ipc settings >/dev/null; settle '.panelHostable >= 0' || true
rep=$(report)
check "the report carries the panel: rows, tip, cursor and the sizes the checks read" "true" \
  "$(jq -r '.panel | . as $p | (.rows | type == "array") and (["pending","shown","text","source","id"] | all(. as $k | $p.tip | has($k)))
    and (["sections","advanced","cursor","contentHeight","viewHeight","footHeight","header","badges","lastWrite"] | all(. as $k | $p | has($k)))' <<<"$rep")"
n=$(jq -r '.panel.rows | length' <<<"$rep")
if (( n == 0 )); then
  check "the panel reports its rows" "28" "0"
else
  check "each row's tip is its id's tip, and only an attention row has a helper" "" "$(python3 - "$REPO/settings-tips.js" "$rep" <<'PY'
import json, re, sys
tips = dict(re.findall(r'^\s+(\w+):\s+"(.*)",?\s*$', open(sys.argv[1]).read(), re.M))
rows = json.loads(sys.argv[2])["panel"]["rows"]
bad = [f'{r["id"]}: tip' for r in rows if r.get("tip") != tips.get(r["id"])]
bad += [f'{r["id"]}: helper' for r in rows if r.get("helper") and not r.get("attention")]
bad += [f"{t}: orphaned" for t in tips if t not in [r["id"] for r in rows]]
print("; ".join(bad))
PY
)"
fi
check "a press the panel does not take answers no-such-button, not an error" "no-such-button" "$(ipc settingsPress nonsense)"
stop

# ---------------------------------------------------------------------------
# 1, 2, 4  Shape, ratchet and Advanced, on the default panel
# ---------------------------------------------------------------------------
echo; echo "${BOLD}1  Shape${RESET}"
BASE="$REPO/dev/baselines/settings.json"
SRC="$REPO/NotchSettings.qml"
open_panel() { ipc settings >/dev/null; settle '.panel.rows | length > 0'; }
start '{"batteryPeek":false}'
open_panel || true; sleep 0.3
rep=$(report)
check "28 rows in four sections: 3, 2, 4 and 19" "Look,Open,In the notch,Advanced 28 3 2 4 19" \
  "$(jq -r '.panel | "\(.sections | join(",")) \(.rows | length) \([.rows[] | select(.section == "Look")] | length) \([.rows[] | select(.section == "Open")] | length) \([.rows[] | select(.section == "In the notch")] | length) \([.rows[] | select(.section == "Advanced")] | length)"' <<<"$rep")"
check "every row is a label and one control of the six kinds, directly in its section" "" \
  "$(jq -r '[.panel.rows[] | select((.label == "") or ((.control | IN("switch","pick","pickMany","stepper","keyRecord","button")) | not) or .depth != 1 or .controls > 1) | .id] | join(" ")' <<<"$rep")"
check "a row has a state on the right, except the buttons" "" \
  "$(jq -r '[.panel.rows[] | select(.control != "button" and .state == "") | .id] | join(" ")' <<<"$rep")"
check "the retired components are gone from the source" "0" "$(grep -cwE 'ChipFlow|StackedRow|ItemChips|PluginPicker|PanelSlider|Choice|ViewRow|revealSection' "$SRC" || true)"
check "…and so are wrapped text, captions and a reduced-motion key" "0 0 0" \
  "$(grep -c wrapMode "$SRC" || true) $(grep -c 'Style.font.caption' "$SRC" || true) $(grep -c reducedMotion "$SRC" || true)"

echo; echo "${BOLD}2  Ratchet and fit${RESET}"
vmax=$(jq -r .visibleMax "$BASE")
visible=$(jq -r '[.panel.rows[] | select(.section != "Advanced" and .visible)] | length' <<<"$rep")
check "visible by default is 8 (Notification light is hidden until the glow work), and at most the baseline's $vmax" "8 true" "$visible $( (( visible <= vmax )) && echo true || echo false )"
check "Advanced has at most $(jq -r .advancedMax "$BASE") rows, the panel at most $(jq -r .totalMax "$BASE")" "true" \
  "$(jq -r --argjson b "$(cat "$BASE")" '([.panel.rows[] | select(.section == "Advanced")] | length) <= $b.advancedMax and (.panel.rows | length) <= $b.totalMax' <<<"$rep")"
check "with Advanced closed the list fits: contentHeight is at most viewHeight" "true" "$(jq -r '.panel.contentHeight <= .panel.viewHeight and .panel.viewHeight > 0' <<<"$rep")"

echo; echo "${BOLD}4  Advanced${RESET}"
adv_visible='[.panel.rows[] | select(.section == "Advanced" and .visible)] | length'
check "Advanced is closed when the panel opens, and none of its rows shows" "false 0" "$(jq -r "\"\(.panel.advanced.open) \($adv_visible)\"" <<<"$rep")"
ipc settingsPress advanced >/dev/null; settle ".panel.advanced.open == true and ($adv_visible) > 0" || true
check "the press opens it: all its rows show but the four with no target here (Panels, Share, Use, Light colours)" "true 15" "$(report | jq -r "\"\(.panel.advanced.open) \($adv_visible)\"")"
check "…and the long list scrolls rather than stretching the panel" "true" "$(report | jq -r '.panel.contentHeight > .panel.viewHeight')"
ipc settings >/dev/null; sleep 0.8; open_panel || true
settle '.panel.advanced.open == false' || true
check "closed and reopened, it is closed again" "false" "$(report | jq -r .panel.advanced.open)"
stop

# ---------------------------------------------------------------------------
# 6  State on the right, and one write per merged row
# ---------------------------------------------------------------------------
echo; echo "${BOLD}6  State${RESET}"
states() { # states <row ids>: "id=state; ..." in panel order
  report | jq -r --arg ids "$*" '($ids | split(" ")) as $want | [.panel.rows[] | select(.id as $i | $want | index($i)) | "\(.id)=\(.state)"] | join("; ")'
}
start '{"batteryPeek":false,"compact":["clock","media"],"notifications":true,"suppressNativeToast":true,"batteryGlow":false,"bottomRadius":8,"filletRadius":12,"notificationStay":true}'
open_panel || true
check "media and time at rest, Notch only, the glow off, corners 8 / 12, notifications until I act" \
  "atRest=Time, Media; glow=Off; notifications=Notch only; corners=8 / 12 px; notifyTime=Until I act" "$(states atRest glow notifications corners notifyTime)"
stop
start '{"batteryPeek":false,"notifications":false,"glowStyle":"bottom","bottomRadius":8,"filletRadius":8,"notificationSeconds":45}'
open_panel || true
check "notifications off, the bottom glow, corners 8 / 8, an odd 45 seconds" \
  "glow=Bottom; notifications=Off; corners=8 px; notifyTime=45 s" "$(states glow notifications corners notifyTime)"
stop
start '{"batteryPeek":false}'
open_panel || true
check "the defaults: nothing at rest, Notch + toast, the outline" "atRest=Nothing; glow=Outline; notifications=Notch + toast" "$(states atRest glow notifications)"
write() { # write <press> <lastWrite> <file>: one write holding its keys, the rest untouched
  local before; before=$(TARGET=settingstest ipc writes)
  ipc settingsPress "$1" >/dev/null
  settle ".panel.lastWrite == $2" || true
  check "$1: one write of $2, and the file holds $3" "$((before + 1)) $2 $3" "$(TARGET=settingstest ipc writes) $(report | jq -c .panel.lastWrite) $(TARGET=settingstest ipc config | jq -cS .)"
}
write set:notifications:only '{"notifications":true,"suppressNativeToast":true}' '{"batteryPeek":false,"notifications":true,"suppressNativeToast":true}'
write set:glow:bottom '{"batteryGlow":true,"glowStyle":"bottom"}' '{"batteryGlow":true,"batteryPeek":false,"glowStyle":"bottom","notifications":true,"suppressNativeToast":true}'
write set:corners:12 '{"bottomRadius":12,"filletRadius":12}' '{"batteryGlow":true,"batteryPeek":false,"bottomRadius":12,"filletRadius":12,"glowStyle":"bottom","notifications":true,"suppressNativeToast":true}'
write set:notifyTime:30 '{"notificationStay":false,"notificationSeconds":30}' '{"batteryGlow":true,"batteryPeek":false,"bottomRadius":12,"filletRadius":12,"glowStyle":"bottom","notificationSeconds":30,"notificationStay":false,"notifications":true,"suppressNativeToast":true}'
stop

# ---------------------------------------------------------------------------
# 8  Every key is decided
# ---------------------------------------------------------------------------
echo; echo "${BOLD}8  Every key decided${RESET}"
start '{"batteryPeek":false}'
open_panel || true
decided=$(python3 - "$REPO" "$(report)" <<'PY'
import json, re, sys
repo, rep = sys.argv[1], json.loads(sys.argv[2])
bar = open(repo + "/Bar.qml").read()
read = set(re.findall(r'notch(?:Setting|Number|Items|Triggers)\("(\w+)"', bar)) | {"notificationLight", "notificationLightColours"}
rowKeys = [k for r in rep["panel"]["rows"] for k in r["keys"]]
tips = open(repo + "/settings-tips.js").read()
noRow = re.findall(r'"(\w+)"', re.search(r"var noRow = \[(.*?)\]", tips, re.S).group(1))
every = rowKeys + noRow
print(json.dumps({"read": len(read), "rowKeys": len(rowKeys), "noRow": len(noRow), "overlap": sorted(set(rowKeys) & set(noRow)),
                  "dupes": sorted({k for k in every if every.count(k) > 1}), "missing": sorted(read - set(every)), "extra": sorted(set(every) - read),
                  "wizard": sorted(r["id"] for r in rep["panel"]["rows"] if r["id"] in "atRest openWith opensTo autoHide menu volume notifications glow".split() and r["section"] != "Advanced")}))
PY
)
check "the keys of the rows (36) and the rowless ones (17) are the 53 the notch reads" "53 36 17" "$(jq -r '"\(.read) \(.rowKeys) \(.noRow)"' <<<"$decided")"
check "…none is in both lists, none twice, none unaccounted for, none invented" "" "$(jq -r '[.overlap, .dupes, .missing, .extra] | add | join(" ")' <<<"$decided")"
check "the wizard's eight questions are all main rows" "atRest autoHide glow menu notifications openWith opensTo volume" "$(jq -r '.wizard | join(" ")' <<<"$decided")"
stop

# ---------------------------------------------------------------------------
# 7  The rowless keys work and change
# ---------------------------------------------------------------------------
echo; echo "${BOLD}7  Dropped keys work and change${RESET}"
# The six dropped keys and the legacy trio: expandOn (-> openWith), hoverAction
# (-> hoverItems) and hoverPlugin.
DROPPED='{"batteryPeek":false,"compactHeight":40,"settingsWith":["rightClick"],"menuWith":["middleClick"],"menuKey":"super+alt+m","stateKey":"super+alt+s","criticalBattery":5,"expandOn":"click","hoverAction":"clock","hoverPlugin":"acme.alpha"}'
start "$DROPPED"
ipc settings >/dev/null; settle '.panelHostable >= 0' || true
resolved() { # the six, the legacy trio, windowsToTop
  jq -c --argjson r "$(report | jq -c .resolved)" \
    '{compactHeight: $r.compactHeight, settingsWith: .resolved.settingsWith, menuWith: $r.menuWith, menuKey: $r.menuKey, stateKey: $r.stateKey,
      criticalBattery: $r.criticalBattery, openWith: .resolved.openWith, hoverItems: .resolved.hoverItems, windowsToTop: .resolved.windowsToTop}' <<<"$(TARGET=notch ipc snapshot)"
}
check "the six dropped keys and the legacy trio resolve to what they say" \
  '{"compactHeight":40,"settingsWith":["rightClick"],"menuWith":["middleClick"],"menuKey":"SUPER + ALT + M","stateKey":"SUPER + ALT + S","criticalBattery":5,"openWith":["click"],"hoverItems":["clock","date"],"windowsToTop":false}' \
  "$(resolved)"
TARGET=notch ipc set autoHide true >/dev/null
settle '.panel.lastWrite.autoHide == true' || true
check "a write the panel's writer makes keeps every one of them" '["autoHide","batteryPeek","compactHeight","criticalBattery","expandOn","hoverAction","hoverPlugin","menuKey","menuWith","settingsWith","stateKey"]' \
  "$(TARGET=settingstest ipc config | jq -c 'keys')"
check "…and they still resolve the same (windowsToTop now follows autoHide)" '{"compactHeight":40,"settingsWith":["rightClick"],"menuWith":["middleClick"],"menuKey":"SUPER + ALT + M","stateKey":"SUPER + ALT + S","criticalBattery":5,"openWith":["click"],"hoverItems":["clock","date"],"windowsToTop":true}' \
  "$(resolved)"
TARGET=notch ipc set compactHeight 36 >/dev/null
settle '.resolved.compactHeight == 36' || true
check "notch set compactHeight 36 changes the resolved value" "36" "$(report | jq -r .resolved.compactHeight)"
TARGET=notch ipc set criticalBattery 12 >/dev/null
settle '.resolved.criticalBattery == 12' || true
check "…and criticalBattery 12" "12" "$(report | jq -r .resolved.criticalBattery)"
TARGET=notch ipc set windowsToTop false >/dev/null
settle '.panel.lastWrite.windowsToTop == false' || true
check "windowsToTop, which keeps a row, is written and shows in the snapshot" "false" "$(TARGET=notch ipc snapshot | jq -r .resolved.windowsToTop)"
# setNotchSettings: two keys, one write, the rest untouched.
before=$(TARGET=settingstest ipc writes)
TARGET=settingstest ipc many '{"notifications":true,"suppressNativeToast":true}' >/dev/null
settle '.panel.lastWrite.suppressNativeToast == true' || true
check "setNotchSettings writes its keys in one write" "$((before + 1))" "$(TARGET=settingstest ipc writes)"
check "…as one lastWrite object with exactly those keys" '{"notifications":true,"suppressNativeToast":true}' "$(report | jq -c .panel.lastWrite)"
check "…leaving the others as they were" "36 12 false" "$(TARGET=settingstest ipc config | jq -r '"\(.compactHeight) \(.criticalBattery) \(.windowsToTop)"')"
stop

# ---------------------------------------------------------------------------
# 5  The foot line
# ---------------------------------------------------------------------------
echo; echo "${BOLD}5  Tip state${RESET}"
TIP="$REPO/NotchTip.qml"
delay() { sed -nE "s/^ *readonly property int $1: ([0-9]+).*/\1/p" "$TIP"; }
check "the delays in NotchTip.qml: hover 400, focus 250, hide 120, fade 90 ms" "400 250 120 90" "$(delay hoverMs) $(delay focusMs) $(delay hideMs) $(delay fadeMs)"
check "…the fade is opacity only: no Behavior on x, y, width or height, no wrapped text" "0 1 1 0" \
  "$(grep -cE 'Behavior on (x|y|width|height)' "$TIP" || true) $(grep -c 'Behavior on opacity { NumberAnimation { duration: tip.fadeMs' "$TIP" || true) $(grep -c 'Behavior' "$TIP" || true) $(grep -c wrapMode "$TIP" || true)"
check "…and the foot is one reserved line of space(24), in the panel" "1" "$(grep -c 'readonly property real footHeight: Style.space(24)' "$SRC" || true)"
start '{"batteryPeek":false}'
open_panel || true; sleep 0.3
tip() { report | jq -r "$1"; }
tipof() { python3 - "$REPO/settings-tips.js" "$1" <<'PY'
import re, sys
print(dict(re.findall(r'^\s+(\w+):\s+"(.*)",?\s*$', open(sys.argv[1]).read(), re.M))[sys.argv[2]])
PY
}
without=$(report)
for _ in 1 2 3; do ipc settingsPress key:down >/dev/null; done
check "key:down three times: the third row is pending from the keyboard" "true glow focus" "$(tip '.panel.tip | "\(.pending) \(.id) \(.source)"')"
settle '.panel.tip.shown == true' || true
check "…then shown with that row's text" "true focus $(tipof glow)" "$(tip '.panel.tip | "\(.shown) \(.source) \(.text)"')"
ipc settingsPress key:down >/dev/null
check "…and the next row swaps it at once" "true openWith $(tipof openWith)" "$(tip '.panel.tip | "\(.shown) \(.id) \(.text)"')"
ipc settingsPress key:escape >/dev/null
ipc settingsPress hover:atRest >/dev/null
check "hover:atRest: pending at once, not yet shown" "true false hover" "$(tip '.panel.tip | "\(.pending) \(.shown) \(.source)"')"
settle '.panel.tip.shown == true' || true
check "…then shown with the row's text, from the pointer" "false true hover atRest $(tipof atRest)" "$(tip '.panel.tip | "\(.pending) \(.shown) \(.source) \(.id) \(.text)"')"
ipc settingsPress hover:width >/dev/null
check "hover:width swaps the text at once, still shown" "true width $(tipof width)" "$(tip '.panel.tip | "\(.shown) \(.id) \(.text)"')"
check "the foot is as tall with a tip as without, the list did not move, and the foot sits below it" "true true true" \
  "$(jq -rn --argjson a "$without" --argjson b "$(report)" '"\($a.panel.footHeight == $b.panel.footHeight and $a.panel.footHeight > 0) \($a.panel.viewHeight == $b.panel.viewHeight and $a.panel.contentHeight == $b.panel.contentHeight) \($b.panel.footTop >= $b.panel.viewBottom)"')"
check "the tip is drawn in the notch's secondary text colour" "$(ipc geometry | jq -r .colours.secondary)" "$(tip .panel.tip.color)"
ipc settingsPress unhover >/dev/null
settle '.panel.tip.shown == false' || true
check "unhover: gone, nothing pending" "false false" "$(tip '.panel.tip | "\(.pending) \(.shown)"')"
cut=""
for id in $ROWS; do
  ipc settingsPress hover:$id >/dev/null
  settle ".panel.tip.shown == true and .panel.tip.id == \"$id\"" || true
  sleep 0.1
  [[ $(tip .panel.tip.truncated) == false ]] || cut+="$id "
done
check "all 28 tips fit on the line, none is cut off" "" "$cut"
stop

# ---------------------------------------------------------------------------
# 9  The keyboard
# ---------------------------------------------------------------------------
echo; echo "${BOLD}9  Keyboard${RESET}"
start '{"batteryPeek":false}'
open_panel || true; sleep 0.3
miss=""
# Press a key; the cursor must come to rest on <row>, inside the view.
move() {
  ipc settingsPress "key:$1" >/dev/null
  settle ".panel.cursor == \"$2\" and .panel.cursorTop >= -0.5 and .panel.cursorBottom <= .panel.viewHeight + 0.5" || miss+="$1:$2(got $(tip .panel.cursor)) "
}
MAIN="atRest autoHide glow openWith opensTo notifications menu volume"
for id in $MAIN advanced; do move down $id; done
check "Down walks the eight main rows and reaches the Advanced line, each inside the view" "" "$miss"
ipc settingsPress key:space >/dev/null
settle '.panel.advanced.open == true' || true
check "Space on the Advanced line opens it" "true" "$(tip .panel.advanced.open)"
miss=""
ADV="width onHover hidden openRow corners notifyTime peeks glowSize greenAbove lowBelow keybinds stayOpen windowsToTop updateCheck reset"
for id in $ADV; do move down $id; done
check "…and Down goes on through its 15 rows to the last, scrolling to keep each in the view" "" "$miss"
check "…the list did scroll" "true" "$(tip '.panel.contentHeight > .panel.viewHeight')"
miss=""
for id in updateCheck windowsToTop stayOpen keybinds lowBelow greenAbove glowSize peeks notifyTime corners openRow hidden onHover width advanced volume; do move up $id; done
check "Up walks back to the Advanced line and the main rows" "" "$miss"
act() { # act <key> <lastWrite> <what>
  ipc settingsPress "key:$1" >/dev/null
  settle ".panel.lastWrite == $2" || true
  check "$3" "$2" "$(report | jq -c .panel.lastWrite)"
}
ipc settingsPress hover:autoHide >/dev/null
check "the pointer moves the cursor to its row" "autoHide" "$(tip .panel.cursor)"
act space '{"autoHide":true}' "Space flips a Switch"
act return '{"autoHide":false}' "…and Enter flips it back"
ipc settingsPress hover:atRest >/dev/null
ipc settingsPress key:space >/dev/null
settle '.panel.rows[] | select(.id == "atRest") | .open == true' || true
check "Space opens a PickMany, the cursor on its first option" "true 0" "$(tip '"\(.panel.rows[] | select(.id == "atRest") | .open) \(.panel.cursorSub)"')"
ipc settingsPress key:right >/dev/null
check "Right walks to the next option" "1" "$(tip .panel.cursorSub)"
act space '{"compact":["date"]}' "Space chooses it, and the PickMany stays open"
ipc settingsPress key:left >/dev/null
act return '{"compact":["clock","date"]}' "Left and Enter choose the one before"
ipc settingsPress key:escape >/dev/null
settle '.panel.rows[] | select(.id == "atRest") | .open == false' || true
check "Escape closes the open Pick" "false true" "$(tip '"\(.panel.rows[] | select(.id == "atRest") | .open) \(.panel.open)"')"
ipc settingsPress hover:glow >/dev/null
ipc settingsPress key:space >/dev/null
ipc settingsPress key:right >/dev/null; ipc settingsPress key:right >/dev/null
act space '{"batteryGlow":true,"glowStyle":"bottom"}' "a Pick takes the option Right walked to"
settle '.panel.rows[] | select(.id == "glow") | .open == false' || true
check "…and folds shut" "false" "$(tip '.panel.rows[] | select(.id == "glow") | .open')"
ipc settingsPress hover:width >/dev/null
act right '{"compactWidth":190}' "Right steps a Stepper up"
act left '{"compactWidth":180}' "…and Left steps it down"
ipc settingsPress hover:keybinds >/dev/null
ipc settingsPress key:space >/dev/null
ipc settingsPress key:space >/dev/null
settle '.panel.recorder == true' || true
check "Space on the Keybinds row opens it, and Space again starts a recorder" "true" "$(tip .panel.recorder)"
ipc settingsPress key:down >/dev/null; ipc settingsPress key:right >/dev/null; ipc settingsPress key:space >/dev/null
check "while it listens, Down, Right and Space do nothing: the cursor and the recorder stay" "keybinds 0 true" "$(tip '"\(.panel.cursor) \(.panel.cursorSub) \(.panel.recorder)"')"
ipc settingsPress key:escape >/dev/null
settle '.panel.recorder == false' || true
check "Escape stops only the recording: the panel and the row are as they were" "false true keybinds" "$(tip '"\(.panel.recorder) \(.panel.open) \(.panel.cursor)"')"
ipc settingsPress key:escape >/dev/null
ipc settingsPress hover:reset >/dev/null
ipc settingsPress key:space >/dev/null
sleep 0.3
cfg=$(TARGET=settingstest ipc config)
check "Space presses a Button: Reset ran, and the settings are gone" "true" "$([[ $cfg != *autoHide* && $cfg != *glowStyle* ]] && echo true || echo false)"
ipc settingsPress hover:atRest >/dev/null
ipc settingsPress key:space >/dev/null
ipc settingsPress hover:glow >/dev/null
settle '.panel.tip.shown == true' || true
ipc settingsPress key:escape >/dev/null
check "Escape first closes the tip: the Pick and the panel stay" "false true true" "$(tip '"\(.panel.tip.shown) \(.panel.rows[] | select(.id == "atRest") | .open) \(.panel.open)"')"
ipc settingsPress key:escape >/dev/null
settle '.panel.rows[] | select(.id == "atRest") | .open == false' || true
check "…then the open Pick, the panel still open" "false true" "$(tip '"\(.panel.rows[] | select(.id == "atRest") | .open) \(.panel.open)"')"
ipc settingsPress key:escape >/dev/null
settle '.panel.open == false' || true
check "…then the panel" "false" "$(tip .panel.open)"
stop

# ---------------------------------------------------------------------------
# 10  Badges and the header
# ---------------------------------------------------------------------------
echo; echo "${BOLD}10  Badges and header${RESET}"
# Header buttons must overlap neither the title nor each other, and stay inside
# the panel's padding (368 px at 100 % scale).
header_fits='.panel as $p | $p.header | sort_by(.x) | . as $h
  | ([range(1; length) | select($h[.].x < $h[. - 1].x + $h[. - 1].width - 0.5)] | length == 0)
    and (($h | last | .x + .width) <= $p.width - 16 + 0.5) and all($h[]; .width > 0)'
header_names='[.panel.header[].name] | join(",")'
badge_text='[.panel.badges[] | "\(.name)=\(.count)"] | join(",")'
button_text() { echo "[.panel.header[] | select(.name == \"$1\") | .text] | first"; }
no_row_badge='[.panel.rows[] | select(((.label + " " + .state) | test(" · [0-9]+$")) or (.helper | test("[0-9]+ (new|issue|update)"))) | .id] + [.panel.sections[] | select(test("[0-9]"))] | join(" ")'

start '{"batteryPeek":false}'
open_panel || true
rep=$(report)
check "nothing to report: no badge, and the header is the title and the close button" "0 title,close" "$(jq -r "\"\(.panel.badges | length) \(${header_names})\"" <<<"$rep")"
check "…no row or section carries a count" "" "$(jq -r "$no_row_badge" <<<"$rep")"
check "…Guided setup stays hidden until Bar.openWizard exists, and its press does nothing" "$(grep -q 'function openWizard' "$REPO/Bar.qml" && echo ok || echo no-such-button)" "$(ipc settingsPress header:guide)"
check "…the header fits: nothing overlaps, all inside the padding" "true" "$(jq -r "$header_fits" <<<"$rep")"
stop

# A notch whose Setup runs against a sandbox (the hooks of dev/setup.sh) that
# has exactly two things to put right: a Hyprland config error and an old backup.
sbx="$root/setup-sandbox"
mkdir -p "$sbx/bin" "$sbx/notch" "$sbx/home/.config/hypr" "$sbx/home/.config/omarchy/plugins" "$sbx/home/.local/state/omarchy/toggles"
printf '#!/bin/bash\ncase "$1" in configerrors) echo '"'"'["line 3: unexpected symbol"]'"'"' ;; *) echo "[]" ;; esac\n' >"$sbx/bin/hyprctl"
printf '#!/bin/bash\nexit 0\n' >"$sbx/bin/quiet"
chmod +x "$sbx/bin/hyprctl" "$sbx/bin/quiet"
: >"$sbx/home/.config/hypr/hyprland.lua.bak.1700000000"
SETUP_ENV=(NOTCH_FORCE_SETUP=1 NOTCH_SETUP_SANDBOX="$sbx" NOTCH_SETUP_STATUS="$sbx/run/setup.json" NOTCH_SETUP_NOTCH_DIR="$sbx/notch"
  NOTCH_SETUP_HYPRCTL="$sbx/bin/hyprctl" NOTCH_SETUP_OMARCHY_SHELL="$sbx/bin/quiet" NOTCH_SETUP_OMARCHY="$sbx/bin/quiet"
  NOTCH_SETUP_OMARCHY_VERSION="$sbx/bin/quiet" NOTCH_SETUP_TOGGLE_BAR="$sbx/bin/quiet" NOTCH_SETUP_QS="$sbx/bin/quiet"
  NOTCH_SETUP_KILL="$sbx/bin/quiet" NOTCH_SETUP_LUA="$sbx/bin/quiet" NOTCH_SETUP_SESSION_LOCKED="$sbx/bin/quiet"
  NOTCH_SETUP_RESTART_SHELL="$sbx/bin/quiet")
XENV=("${SETUP_ENV[@]}")
start '{"batteryPeek":false}'
ipc setup check "" >/dev/null
ipc settings >/dev/null
settle '.panel.badges | length > 0' || true
rep=$(report)
check "two issues in the sandbox: one badge, Setup · 2" "setup=2 title,setup,close Setup · 2" \
  "$(jq -r "[($badge_text), ($header_names), ($(button_text setup))] | join(\" \")" <<<"$rep")"
check "…the header still fits" "true" "$(jq -r "$header_fits" <<<"$rep")"
check "…and still no row or section carries a count" "" "$(jq -r "$no_row_badge" <<<"$rep")"
stop

# The notch's own update: a git checkout one commit behind its origin. The
# plugin half of the count reads 0 here, as it does until Plugins has been visited.
export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
upd="$root/update-sandbox"
git init -q --bare "$upd/origin.git"
git clone -q "$upd/origin.git" "$upd/plugin" 2>/dev/null
git clone -q "$upd/origin.git" "$upd/work" 2>/dev/null
echo '{"version":"1.0.0"}' >"$upd/work/manifest.json"
git -C "$upd/work" add manifest.json; git -C "$upd/work" commit -qm one; git -C "$upd/work" push -q origin HEAD 2>/dev/null
git -C "$upd/plugin" pull -q origin HEAD 2>/dev/null
echo '{"version":"1.0.1"}' >"$upd/work/manifest.json"
git -C "$upd/work" commit -qam two; git -C "$upd/work" push -q origin HEAD 2>/dev/null
UPDATE_ENV=(NOTCH_FORCE_UPDATES=1 NOTCH_UPDATE_DIR="$upd/plugin" NOTCH_UPDATE_STATE_DIR="$upd/state" NOTCH_UPDATE_RESTART=none NOTCH_UPDATE_FIRST_CHECK_MS=200)
XENV=("${UPDATE_ENV[@]}")
start '{"batteryPeek":false}'
ipc settings >/dev/null
settle '.panel.badges | length > 0' || true
rep=$(report)
check "an update available: Updates · 1, a header button" "updates=1 title,updates,close Updates · 1" \
  "$(jq -r "[($badge_text), ($header_names), ($(button_text updates))] | join(\" \")" <<<"$rep")"
check "…the header fits, and no row or section carries it" "true " "$(jq -r "\"\(${header_fits}) \(${no_row_badge})\"" <<<"$rep")"
res=$(ipc settingsPress header:updates); sleep 0.9
check "…pressing it opens Plugins" "ok true" "$res $(ipc geometry | jq -r '.plugins.open')"
stop
# Both at once: the widest header, three buttons and the title in 368 px.
XENV=("${SETUP_ENV[@]}" "${UPDATE_ENV[@]}")
start '{"batteryPeek":false}'
ipc setup check "" >/dev/null
ipc settings >/dev/null
settle '(.panel.badges | length) == 2' || true
rep=$(report)
check "both at once: Updates · 1 then Setup · 2" "updates=1,setup=2 title,updates,setup,close" "$(jq -r "[($badge_text), ($header_names)] | join(\" \")" <<<"$rep")"
check "…with both badges the header still fits: the title is overlapped by nothing" "true" "$(jq -r "$header_fits" <<<"$rep")"
stop
XENV=()

# ---------------------------------------------------------------------------
# 11  Contract
# ---------------------------------------------------------------------------
echo; echo "${BOLD}11  Contract${RESET}"
# The panel changes height when its rows move; nothing else the contract
# records may change (phase 2 re-records the baseline once, per plan-settings.md 6).
cout=$("$REPO/dev/contract.sh" 2>&1); crc=$?
paths=$(sed -nE 's/^ +([^ ]+): baseline .*/\1/p' <<<"$cout" | sed 's/\x1b\[[0-9;]*m//g')
other=$(grep -vc '/settingsPanel/height$' <<<"$paths" || true)
[[ -z $paths ]] && other=0
check "the contract differs from its baseline in no path but */settingsPanel/height" "0" "$other"
if [[ -z $paths ]]; then check "…and with the baseline as recorded, contract.sh passes" "0" "$crc"; fi
check "the recorded baseline changes in no line but a height" "0" "$(git -C "$REPO" diff -U0 -- dev/baselines/synthetic.json | grep '^[+-] ' | grep -vc '"height"' || true)"

# ---------------------------------------------------------------------------
# The ratchet's baseline (check 2 reads it)
# ---------------------------------------------------------------------------
echo; echo "${BOLD}Ratchet${RESET}"
check "the baseline holds the caps: 9 visible, 19 Advanced, 32 in all" "9 19 32" "$(jq -r '"\(.visibleMax) \(.advancedMax) \(.totalMax)"' "$BASE")"
lines=$(wc -l <"$REPO/NotchSettings.qml"); cap=$(jq -r .fileLines "$BASE")
check "NotchSettings.qml has not grown past the recorded $cap lines" "true" "$( (( lines <= cap )) && echo true || echo false )"
if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi

echo
if (( failures )); then echo "${RED}${failures} of ${checks} checks failed${RESET}"; exit 1; fi
echo "${GREEN}all ${checks} checks pass${RESET}"
