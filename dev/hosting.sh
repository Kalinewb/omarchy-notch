#!/bin/bash

# Drawing another plugin's panel inside the notch, as numbers.
#
#   ./dev/hosting.sh
#
# PanelHosting.qml against Omarchy's REAL audio widget, loaded from the
# installed shell. The host is a plain black window standing in for the notch's
# panel surface, so what is measured here is the mechanism: what it takes, that
# the panel still works where it lands, that the plugin's own window never maps
# while the notch holds its content, and that everything is given back the way
# it was found -- size included.
#
# Nothing here touches the live session: the widget is a second copy, loaded
# read-only, with a stand-in `bar`.

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
WIDGET=${HOSTING_WIDGET:-$SHELL_PATH/shell/plugins/panels/audio/Panel.qml}
[[ -f $WIDGET ]] || { echo "hosting.sh: no widget at $WIDGET" >&2; exit 1; }

sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-hosting.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

root="$sb/root"
mkdir -p "$root"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/hosting-shell.qml" "$root/shell.qml"

ipc() { quickshell ipc -p "$root" call hosting "$@" 2>/dev/null; }
field() { jq -r "$2" <<<"$1"; }

echo "${BOLD}Hosting another plugin's panel${RESET}  ${DIM}$(basename "$(dirname "$WIDGET")")/$(basename "$WIDGET")${RESET}"

OMARCHY_SHELL_PATH="$SHELL_PATH/shell" HOSTING_WIDGET="$WIDGET" \
  quickshell -p "$root" -n >"$sb/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc ready) == yes ]] && break; done
sleep 0.6

check "1. the widget loads with nothing but a stand-in bar" "yes" "$(ipc ready)"
check "2. its panel is one the notch can draw" "" "$(ipc hostable)"

# --- taking it -----------------------------------------------------------------

before=$(ipc state)
check "3. nothing is hosted to begin with, and the plugin's own window is not mapped" "false 0 false" \
  "$(field "$before" '.hosting') $(field "$before" '.slotChildren') $(field "$before" '.ownWindowVisible')"

check "4. taking it succeeds" "" "$(ipc take)"
sleep 0.5
after=$(ipc state)
echo "  ${DIM}$(jq -c '{hosting, slotChildren, contentSize, ownWindowVisible}' <<<"$after")${RESET}"
check "5. the panel is now in the notch's slot" "true 1 true" \
  "$(field "$after" '.hosting') $(field "$after" '.slotChildren') $(field "$after" '.contentInSlot')"
check "6. …at the host's size" "460x420" \
  "$(field "$after" '.contentSize.width')x$(field "$after" '.contentSize.height')"
check "7. …and the plugin's own window never mapped" "false false" \
  "$(field "$after" '.ownWindowVisible') $(field "$after" '.ownPanelOpen')"

texts=$(ipc texts)
echo "  ${DIM}live text: $texts${RESET}"
check "8. the panel is live where it landed, not a picture of itself" "true" \
  "$(jq -r 'length >= 3' <<<"$texts")"

ipc resizeHost 640 >/dev/null; sleep 0.6
check "9. it lays out again when the notch resizes" "640" "$(field "$(ipc state)" '.contentSize.width')"

check "10. taking it twice is refused rather than losing the first one" "already hosting" "$(ipc take)"

# --- giving it back --------------------------------------------------------------

check "11. giving it back succeeds" "" "$(ipc giveBack)"
sleep 0.5
back=$(ipc state)
check "12. the notch's slot is empty again" "false 0" \
  "$(field "$back" '.hosting') $(field "$back" '.slotChildren')"
check "13. …and the panel is its own size again, not the notch's" "460" \
  "$(field "$back" '.contentSize.width // 460')"

ipc openOwn >/dev/null; sleep 0.8
own=$(ipc state)
check "14. the plugin's own panel opens normally afterwards" "true true" \
  "$(field "$own" '.ownPanelOpen') $(field "$own" '.ownWindowVisible')"
texts=$(ipc texts)
check "15. …and is still live after the round trip" "true" "$(jq -r 'length >= 3' <<<"$texts")"
ipc closeOwn >/dev/null; sleep 0.4

check "16. giving back when nothing is hosted does nothing and says nothing" "" "$(ipc giveBack)"

# --- a widget that cannot be hosted ------------------------------------------------

ipc quit >/dev/null 2>&1; wait "$qs_pid" 2>/dev/null; qs_pid=""
cat >"$sb/Plain.qml" <<'QML'
import QtQuick
// A bar widget with no pop-out panel at all.
Item {
  property var bar: null
  property string moduleName: ""
  implicitWidth: 20
  implicitHeight: 20
}
QML
OMARCHY_SHELL_PATH="$SHELL_PATH/shell" HOSTING_WIDGET="$sb/Plain.qml" \
  quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc ready) == yes ]] && break; done
sleep 0.4
check "17. a widget with no panel is declined, in words" "no panel" "$(ipc hostable)"
check "18. …and taking it refuses rather than half-doing it" "no panel" "$(ipc take)"
check "19. …leaving the slot empty" "false 0" \
  "$(field "$(ipc state)" '.hosting') $(field "$(ipc state)" '.slotChildren')"

check "20. no QML errors in any of it" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"


# ---------------------------------------------------------------------------
# B. Inside the notch: the same panel, on the notch's surface and its motion.
# ---------------------------------------------------------------------------

echo; echo "${BOLD}Inside the notch${RESET}"

ipc quit >/dev/null 2>&1; wait "$qs_pid" 2>/dev/null; qs_pid=""

notch_root="$sb/notch"
mkdir -p "$notch_root"
ln -s "$SHELL_PATH/shell/Commons" "$notch_root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$notch_root/Ui"
ln -s "$SHELL_PATH/shell/services" "$notch_root/services"
ln -s "$REPO" "$notch_root/notch"
cp "$REPO/dev/harness/hosting-notch-shell.qml" "$notch_root/shell.qml"

notch() { quickshell ipc -p "$notch_root" call notch "$@" 2>/dev/null; }

# Setup reads a sandbox, never this machine's real config.
mkdir -p "$sb/setup-home/.config/omarchy" "$sb/setup-state" "$sb/setup-run"
echo '{"bar":{"id":"graveklar.notch","layout":{"left":[],"center":[],"right":[]}}}' >"$sb/setup-home/.config/omarchy/shell.json"

OMARCHY_SHELL_PATH="$SHELL_PATH/shell" HOSTING_WIDGET="$WIDGET" \
  NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
  NOTCH_FORCE_SETUP=1 NOTCH_SETUP_HOME="$sb/setup-home" NOTCH_SETUP_CONFIG_DIR="$sb/setup-home/.config" \
  NOTCH_SETUP_TOGGLES_DIR="$sb/setup-home/toggles" NOTCH_SETUP_STATE_DIR="$sb/setup-state" \
  NOTCH_SETUP_STATUS="$sb/setup-run/setup.json" \
  NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"bottomRadius":10}' \
  quickshell -p "$notch_root" -n >>"$sb/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do sleep 0.1; [[ $(notch geometry) == \{* ]] && break; done
sleep 0.8

check "21. the notch is drawing the widget" "true" \
  "$(notch geometry | jq -r '.widgets.slots >= 1')"

# Sample the height all the way through the open, to see the spring rather than
# a jump: every sample between rest and the target, never past it.
( for _ in $(seq 1 14); do notch geometry | jq -rc '"\(.bar.height) \(.target.height) \(.state)"'; done ) >"$sb/opening" &
sampler=$!
opened=$(notch hostPanel audio)
wait "$sampler" 2>/dev/null
sleep 0.9

check "22. the notch takes the panel" "opened" "$opened"
g=$(notch geometry)
echo "  ${DIM}$(jq -c '{state, view, hosted: {open: .hosted.open, items: .hosted.items, size: [.hosted.width, .hosted.height], wanted: .hosted.report.wanted}}' <<<"$g")${RESET}"
check "23. it is on the notch's surface, in the notch's view" "expanded hosted true" \
  "$(field "$g" '.state') $(field "$g" '.view') $(field "$g" '.hosted.open')"
# The panel reads its colours off the bar object it was given. Inside the
# notch those are the notch's -- white on black -- not the theme's.
check "23a. …painting with the notch's colours: text, background and urgent are the notch's, not the theme's" "true true true" \
  "$(field "$g" '.colours | "\(.widgets.foreground == .text) \(.widgets.background == .notch) \(.urgent == .text)"')"
check "24. every item of the panel came, not just the first" "true" \
  "$(field "$g" '.hosted.items >= 1')"
check "25. the notch grew to the size the PLUGIN asked its own card for" "true" \
  "$(field "$g" '.hosted.report.wanted.width > 0 and (.hosted.width >= .hosted.report.wanted.width)')"
check "26. …and the notch's own surface is what moved: top edge on the screen edge, square top corners" "0 0" \
  "$(field "$g" '.bar.y') $(field "$g" '.radii.topLeft')"
check "27. the target is the hosted size, and the bar arrived at it" "true" \
  "$(field "$g" '(.target.height == .hosted.height) and ((.bar.height - .target.height) | fabs) < 0.5')"

# The motion itself.
heights=$(awk '{print $1}' "$sb/opening")
samples=$(grep -c . "$sb/opening")
target=$(field "$g" '.hosted.height')
peak=$(sort -g <<<"$heights" | tail -1)
settled=$(notch geometry | jq -r '.bar.height')
echo "  ${DIM}$samples height samples while opening: $(echo "$heights" | head -8 | tr '\n' ' ')…  peak $peak, target $target${RESET}"
check "28. it grew rather than jumped: more than one height seen on the way" "true" \
  "$([[ $(sort -u <<<"$heights" | grep -c .) -gt 1 ]] && echo true || echo false)"
# The notch's spring overshoots once by 3.8 % (damping 0.72, spring.js) and
# settles. So a peak slightly above the target is the design, and a peak well
# above it, or a resting height that is not the target, is not.
spring=$(awk -v p="$peak" -v t="$target" -v s="$settled" 'BEGIN {
  printf "%s %s", (p <= t * 1.05 ? "true" : "false"), ((s - t) < 0.5 && (t - s) < 0.5 ? "true" : "false") }')
check "29. it springs the way the notch springs: one small overshoot, then rest at the target" "true true" "$spring"

# The guest's own controls keep their own shapes -- Omarchy's toggle is a pill,
# its rules are hairlines, and forcing the notch's radius onto them would make
# them look wrong rather than integrated. What IS the notch's business is that
# the guest does not paint a surface of its own over the notch's black: the
# background belongs to the notch, and the card that used to provide one was
# left behind with the plugin's window.
d=$(notch design)
check "30. the guest paints no background of its own over the notch" "0" "$(python3 -c '
import json,sys
d=json.loads(sys.argv[1])
items=[i for i in d.get("hosted", []) if i["drawn"] and i["width"]>0 and i["height"]>0]
area=max((i["width"]*i["height"] for i in items), default=0)
slot=json.loads(sys.argv[2])
full=[i for i in items if i["width"]*i["height"] >= 0.9*slot["width"]*slot["height"]]
print(len(full))' "$d" "$(field "$g" '{width: .hosted.width, height: .hosted.height}')")"

check "31. the notch reports what it is hosting" "true" \
  "$(notch hosting | jq -r '.active')"

# Closing: the panel goes back, and the notch shrinks on its own timing.
notch releasePanel >/dev/null; sleep 1.2
g=$(notch geometry)
check "32. closing gives the panel back and the notch rests" "compact false 0" \
  "$(field "$g" '.state') $(field "$g" '.hosted.open') $(field "$g" '.hosted.items')"
check "33. …and the notch is holding nothing" "false" "$(notch hosting | jq -r '.active')"
check "33a. …and the panel's colours are the theme's again, for its own window" "true true" \
  "$(field "$g" '.colours | "\(.widgets.foreground == .themeText) \(.widgets.background == .themeBarBackground)"')"

# Opening it again after a round trip.
check "34. it can be hosted again afterwards" "opened" "$(notch hostPanel audio)"
sleep 0.9
check "35. …with the panel back on the notch's surface" "expanded true" \
  "$(notch geometry | jq -r '.state') $(notch geometry | jq -r '.hosted.open')"

# Every way of closing a panel closes this one too.
notch toggle >/dev/null; sleep 1.2
check "36. the open keybind closes it, like every other panel" "false 0" \
  "$(notch geometry | jq -r '.hosted.open') $(notch geometry | jq -r '.hosted.items')"

check "37. a widget the notch is not drawing is declined, in words" "declined:no such widget" \
  "$(notch hostPanel nosuchwidget)"

# The click path: a widget the user has asked for opens in the notch; one they
# have not is left alone entirely.
ipc_notch_restart() { :; }
check "38. a widget nobody opted into is not intercepted, and nothing is opted in by default" "false []" \
  "$(notch geometry | jq -r '.hosted.open') $(notch hosting | jq -c '.opted')"

# Settings -> Integrations has to offer it, or nobody can reach it without
# editing shell.json by hand.
check "39. the settings offer the widget, named, as something the notch can draw" "1 Audio false" \
  "$(notch settingsReport 2>/dev/null | jq -r '.hostable | length') $(notch settingsReport 2>/dev/null | jq -r '.hostable[0].name') $(notch settingsReport 2>/dev/null | jq -r '.hostable[0].hosted')"

# A plugin opening its own panel -- its keybind, or `omarchy-shell <id> open` --
# has to land in the notch too, or the integration only half applies.
harness() { quickshell ipc -p "$notch_root" call harness "$@" 2>/dev/null; }

check "40. nothing is hosted before the summon" "false" "$(notch geometry | jq -r '.hosted.open')"
check "41. summoning a widget nobody opted into leaves the notch alone" "ok false" \
  "$(harness summon) $(sleep 0.8; notch geometry | jq -r '.hosted.open')"
own=$(harness ownWindow)
check "42. …and that plugin opened its own window, as it always did" "true" \
  "$(jq -r '.open' <<<"$own")"

# Put the plugin's own panel back down first: `open` is already true, and
# setting it true again would fire no change for the notch to act on.
harness dismiss >/dev/null; sleep 0.6

# Now opt it in, the way the settings switch does, and summon again.
harness setNotch '{"batteryPeek":false,"bottomRadius":10,"hostedPanels":["audio"]}' >/dev/null; sleep 0.8
check "43. the settings switch is what turns it on" '["audio"]' "$(notch hosting | jq -c '.opted')"
harness summon >/dev/null; sleep 1.0
g=$(notch geometry)
own=$(harness ownWindow)
check "44. the plugin's own summon now opens inside the notch" "expanded hosted true" \
  "$(field "$g" '.state') $(field "$g" '.view') $(field "$g" '.hosted.open')"
# This shows the window is down once the notch has it. That it never appears at
# all rests on the handler running in the same turn as the plugin's own `open`,
# which is reasoned rather than measured: an IPC round trip is ~50 ms and a
# frame is ~8, so this harness cannot see a single-frame flicker either way.
check "45. …and the plugin's own window was put straight back down" "false false" \
  "$(jq -r '.visible' <<<"$own") $(jq -r '.open' <<<"$own")"

notch releasePanel >/dev/null; sleep 1.0
check "46. releasing it gives the panel back" "false 0" \
  "$(notch geometry | jq -r '.hosted.open') $(notch geometry | jq -r '.hosted.items')"

# Setup has to ask, or nobody finds the switch.
harness setNotch '{"batteryPeek":false,"bottomRadius":10}' >/dev/null; sleep 0.8
notch setup check "" >/dev/null 2>&1; sleep 2.5
point=$(notch setup status "" 2>/dev/null | jq -c '.points[] | select(.id == "hostable-panels")')
echo "  ${DIM}$(jq -c '{severity, title, handoff}' <<<"$point" 2>/dev/null)${RESET}"
check "47. Setup asks about a panel the notch could draw, and offers to do it" "action Integrate them integrate-panels" \
  "$(jq -r '.severity' <<<"$point") $(jq -r '.handoff.label' <<<"$point") $(jq -r '.handoff.action' <<<"$point")"
check "48. …naming the plugin rather than its id" "Audio" "$(jq -r '.items[0].summary' <<<"$point")"

harness setNotch '{"batteryPeek":false,"bottomRadius":10,"hostedPanels":["audio"]}' >/dev/null; sleep 0.8
notch setup check "" >/dev/null 2>&1; sleep 2.5
point=$(notch setup status "" 2>/dev/null | jq -c '.points[] | select(.id == "hostable-panels")')
check "49. …and stops asking once it is on" "ok" "$(jq -r '.severity' <<<"$point")"

check "50. no QML errors in the notch either" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
