#!/bin/bash

# Quiet -- a plugin asking the notch to step out of the way for a moment, and the
# notch coming back as it was -- as numbers.
#
#   ./dev/quiet.sh
#
# A. activities.js `defer` as a pure function, under node: time is supplied.
# B. The verb over IPC on a throwaway notch (`notch quiet on|off|status <owner>`):
#    every answer word, what hides and what does not (the space the notch reserves),
#    and that it comes back to the same page, the same way back, the same view.
# C. With plugins (dev/fixtures): a panel open when it starts comes back, a panel
#    or a claim asked for meanwhile is declined with the reason, a line already on
#    the notch gets its time back, and a plugin switched off lets its hold go.
# D. The fail-safes, on a notch with shortened clocks (NOTCH_QUIET_* only count in
#    a test notch): the lease lapses by itself, renewing keeps it, the cap cuts a
#    requester that never stops and refuses it for a while.
#
# E. Notifications: a toast on the notch keeps its place and its time, and one that arrives
#    meanwhile is claimed when the notch is back.
#
# Nothing here touches the live session or the real plugins folder.

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

work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-quiet.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

# --- A. defer --------------------------------------------------------------------------

echo "${BOLD}activities.js defer${RESET}  ${DIM}node, no display${RESET}"
cat >"$work/run.js" <<EOF
const vm = require("vm"), fs = require("fs")
const source = fs.readFileSync("$REPO/activities.js", "utf8").replace(/^\.pragma library/m, "")
const context = { console, Math, JSON, Date, Array, Object, String, Number }
vm.createContext(context)
vm.runInContext(source, context)
const A = context
function claim(s, key, priority, ttl, now) {
  return A.claim(s, { owner: "o", key: key, priority: priority, title: "t", detail: "", glyph: "", progress: -1,
                      view: "", screens: [], ttlMs: ttl, panelRoute: "", at: 0 }, now).state
}
// Two transients on screen (4 s and 5 s from 1000) and a third waiting behind them.
let s = A.create()
s = claim(s, "a", "transient", 4000, 1000)
s = claim(s, "b", "transient", 5000, 1000)
s = claim(s, "c", "transient", 2000, 1000)
const d = A.defer(s, 3000)
console.log("a=" + d.visible[0].expiresAt + " b=" + d.visible[1].expiresAt + " c=" + d.queued[0].claimedAt)
console.log("same=" + (A.defer(s, 0) === s) + " neg=" + (A.defer(s, -5) === s))
console.log("input=" + s.visible[0].expiresAt + "/" + s.queued[0].claimedAt)
const keys = (t) => A.tick(d, t).visible.map((e) => e.key).join("")
// Until the moved deadline both are there; a goes at 8000 and the waiting c takes its place.
console.log("early=" + keys(7999) + " moved=" + keys(8000))
// A queued transient waits at most ten seconds, counted from the end of the pause: at 14000 the
// wait is exactly ten seconds and it is shown, a millisecond later it is dropped.
const late = (t) => A.tick(A.defer(s, 3000), t).visible.map((e) => e.key).join("")
console.log("waits=" + late(14000) + " dropped=[" + late(14001) + "]")
// Without the pause the same wait would already be over at 11001.
console.log("undeferred=[" + A.tick(s, 11001).visible.map((e) => e.key).join("") + "]")
// A line with no time on it has none afterwards either.
let p = claim(A.create(), "p", "persistent", 0, 1000)
console.log("none=" + A.defer(p, 3000).visible[0].expiresAt)
EOF
out=$(node "$work/run.js" 2>&1 | tr -d '\r')
check "a shown line's time is moved by the pause, and so is a queued one's wait" \
  "a=8000 b=9000 c=4000" "$(sed -n 1p <<<"$out")"
check "no pause (0 or less) hands back the same state" "same=true neg=true" "$(sed -n 2p <<<"$out")"
check "it makes a new state and leaves its argument alone" "input=5000/1000" "$(sed -n 3p <<<"$out")"
check "…a line runs to its moved deadline and no further" "early=ab moved=bc" "$(sed -n 4p <<<"$out")"
check "…the wait of a queued transient is counted from the end of the pause" "waits=c dropped=[]" "$(sed -n 5p <<<"$out")"
check "…which, undeferred, would already have dropped it" "undeferred=[]" "$(sed -n 6p <<<"$out")"
check "…and a line with no time on it stays that way" "none=0" "$(sed -n 7p <<<"$out")"

# --- the notch, with plugins ------------------------------------------------------------

plugins="$work/plugins"; mkdir -p "$plugins" "$work/state" "$work/markers" "$work/bin"
cp -r "$REPO/dev/fixtures/back/plugins/acme.pages" "$plugins/acme.pages"
cp -r "$REPO/dev/fixtures/platform/plugins/acme.demo" "$plugins/acme.demo"
root="$work/root"; mkdir -p "$root"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/platform-shell.qml" "$root/shell.qml"
printf 'import QtQuick\nimport qs.Commons\nimport qs.Ui\nItem { }\n' >"$root/Probe.qml"
printf '#!/bin/bash\necho "$*" >> "%s/omarchy-shell.log"\necho "Target not found." >&2\nexit 1\n' "$work" >"$work/bin/omarchy-shell"
chmod +x "$work/bin/omarchy-shell"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
harness() { quickshell ipc -p "$root" call harness "$@" 2>/dev/null; }
settle() { sleep 0.9; }
st() { ipc geometry | jq -r .state; }
zone() { ipc geometry | jq -r .window.exclusiveZone; }
rep() { ipc backReport | jq -r '"\(.offered) \(.depth) \(.panel)"'; }
qrep() { ipc quiet status x | jq -r "$1"; }
now_ms() { date +%s%3N; }
# Back to the resting notch, whatever is open.
rest() { for _ in 1 2 3 4; do [[ $(st) == compact ]] && return; ipc back >/dev/null; ipc collapse >/dev/null; settle; done; }

start() { # start [extra env...]
  env PATH="$work/bin:$PATH" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_FORCE_PLATFORM=1 NOTCH_PLUGINS_DIR="$plugins" NOTCH_PLATFORM_ENABLED="*" \
    NOTCH_PLATFORM_STATE_DIR="$work/state" NOTCH_FIXTURE_MARKER_DIR="$work/markers" \
    NOTCH_PLATFORM_WIDGETS='{}' NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' "$@" \
    quickshell -p "$root" -n >>"$work/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc integrations | jq -r '.scannedAt > 0') == true ]] && break; done
  sleep 0.5
}
stop() { harness quit >/dev/null 2>&1; sleep 0.6; kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

# --- B. the verb ------------------------------------------------------------------------

echo; echo "${BOLD}The verb, on a notch with nothing open${RESET}  ${DIM}omarchy-shell notch quiet <on|off|status> <owner>${RESET}"
start
check "the notch says it has the verb (the feature word)" "true" \
  "$(ipc integrations | jq -r '.features | index("quiet") != null')"
check "at rest: not quiet, showing the resting notch" "false compact" "$(qrep .quiet) $(st)"
rest_zone=$(zone)

check "on answers quiet" "quiet" "$(ipc quiet on probe:one)"
settle
check "…the notch is hidden" "hidden" "$(st)"
check "…and the space it reserves is untouched, so no window moves" "$rest_zone" "$(zone)"
check "…the report names the hold, with time left on it" "true probe:one true" \
  "$(qrep '"\(.quiet) \(.holds[0].owner) \(.holds[0].leftMs > 20000)"')"
sleep 2.2
check "…the platform beat says so, for a plugin that reads the file (SurfaceLink)" "true" \
  "$(jq -r '.quiet' "$work/state/platform.json" 2>/dev/null)"
check "on again for the same owner answers renewed" "renewed" "$(ipc quiet on probe:one)"
check "off answers restored: that was the last hold" "restored" "$(ipc quiet off probe:one)"
settle
check "…the resting notch is back, in the same space" "compact $rest_zone" "$(st) $(zone)"
check "off for an owner that holds nothing answers idle" "idle" "$(ipc quiet off probe:one)"

check "an owner with a space or a slash in it is refused" "declined:bad-owner declined:bad-owner" \
  "$(ipc quiet on 'a/b') $(ipc quiet on 'a:b:c')"
check "a word that is not on, off or status is refused" "declined:bad-state" "$(ipc quiet maybe probe)"
check "…and nothing was held by any of that" "false" "$(qrep .quiet)"

echo; echo "${BOLD}Several owners${RESET}"
ipc quiet on probe:a >/dev/null; ipc quiet on probe:b >/dev/null
check "two holds: quiet" "true 2" "$(qrep .quiet) $(qrep '.holds | length')"
check "the first to let go answers released: the notch stays away" "released true" "$(ipc quiet off probe:a) $(qrep .quiet)"
check "the last answers restored" "restored false" "$(ipc quiet off probe:b) $(qrep .quiet)"
for i in 1 2 3 4 5 6 7 8; do ipc quiet on "probe:o$i" >/dev/null; done
check "a ninth owner is refused rather than collected" "declined:too-many 8" \
  "$(ipc quiet on probe:o9) $(qrep '.holds | length')"
for i in 1 2 3 4 5 6 7 8; do ipc quiet off "probe:o$i" >/dev/null; done
settle

# --- B. what comes back -----------------------------------------------------------------

echo; echo "${BOLD}It comes back as it was${RESET}"
# The notch closes a panel when the session's focus moves (HyprlandFocusGrab), and a suite runs in a
# session someone is using, so a scenario that opens a panel is run again, up to three times, before
# a mismatch is believed. One line per scenario: every observation in it has to be right.
scenario() { # scenario <description> <expected> <function>
  local got
  for _ in 1 2 3; do rest; got=$("$3"); [[ $got == "$2" ]] && break; done
  check "$1" "$2" "$got"
}
gs() { ipc geometry | jq -r '"\(.settingsOpen)/\(.state)"'; }

sc_settings() {
  ipc view settings >/dev/null; settle; local opened; opened=$(gs)
  ipc quiet on probe >/dev/null; settle; local away; away="$(gs) $(rep)"
  ipc quiet off probe >/dev/null; settle
  echo "$opened | $away | $(gs) $(rep)"
}
scenario "the settings: put away (hidden, no strip), and back, with nothing behind them as before" \
  "true/expanded | false/hidden false 0 false | true/expanded true 0 true" sc_settings

sc_from_settings() {
  ipc view settings >/dev/null; settle
  ipc panel acme.demo main >/dev/null; settle; local opened; opened="$(rep) $(ipc geometry | jq -r .integration.open)"
  ipc quiet on probe >/dev/null; settle; local away; away=$(rep)
  ipc quiet off probe >/dev/null; settle; local back; back="$(rep) $(ipc geometry | jq -r .integration.open)"
  echo "$opened | $away | $back | $(ipc back) $(settle; ipc geometry | jq -r '"\(.settingsOpen)/\(.integration.open)"') | $(ipc back) $(settle; st)"
}
scenario "a panel opened from the settings: away, then back with the settings still one step behind it; Back goes there, then closes" \
  "true 1 true true | false 0 false | true 1 true true | back true/false | closed compact" sc_from_settings

sc_key() {
  ipc expand >/dev/null; settle; local opened; opened="$(ipc geometry | jq -r '"\(.state)/\(.view)"')"
  ipc quiet on probe >/dev/null; settle; local away; away=$(st)
  ipc quiet off probe >/dev/null; settle; local back; back="$(ipc geometry | jq -r '"\(.state)/\(.view)"')"
  ipc collapse >/dev/null; settle
  echo "$opened | $away | $back | $(st)"
}
scenario "opened by a key (no panel): hidden, then open again on the same view, and it still closes the way it opened" \
  "expanded/widgets | hidden | expanded/widgets | compact" sc_key

sc_newer() {
  ipc view settings >/dev/null; settle
  ipc quiet on probe >/dev/null; settle
  ipc view menu >/dev/null 2>&1
  ipc quiet off probe >/dev/null; settle
  ipc geometry | jq -r '"settings=\(.settingsOpen) menu=\(.menu.open)"'
}
scenario "something opened while it was away is newer than what was put away, and wins" "settings=false menu=true" sc_newer
rest

# --- C. with plugins --------------------------------------------------------------------

echo; echo "${BOLD}With a plugin's panel and claims${RESET}"
check "a plugin's panel opens at a page" "opened" "$(ipc panel acme.pages deep:1)"; settle
check "…it is on screen" "true acme.pages" "$(ipc geometry | jq -r '"\(.integration.open) \(.integration.id)"')"
ipc quiet on probe >/dev/null; settle
check "quiet: its panel is closed and the notch hidden" "false hidden" \
  "$(ipc geometry | jq -r '"\(.integration.open) \(.state)"')"
check "asking for another panel meanwhile is declined, with the reason" "declined:quiet" "$(ipc panel acme.demo main)"
check "a claim meanwhile is declined the way a hidden bar declines it" "declined:quiet" \
  "$(ipc claim acme.demo '{"title":"x","priority":"persistent","ttlMs":4000}')"
ipc quiet off probe >/dev/null; settle
check "off: the same panel is back" "true acme.pages expanded" \
  "$(ipc geometry | jq -r '"\(.integration.open) \(.integration.id) \(.state)"')"
check "…it is at the page it was opened on, so the strip goes back a page inside it first, then closes" "inside true closed false" \
  "$(ipc back) $(settle; ipc geometry | jq -r .integration.open) $(ipc back) $(settle; ipc geometry | jq -r .integration.open)"

echo; echo "${BOLD}A line already on the notch is not lost${RESET}"
check "a claim with four seconds on it is shown" "shown 1" \
  "$(ipc claim acme.demo '{"title":"Look at the camera","priority":"persistent","ttlMs":4000}') $(ipc activities | jq '.visible | length')"
ipc quiet on probe >/dev/null
sleep 5.5
check "five and a half seconds quiet, longer than its time: it is still on the books" "1" "$(ipc activities | jq '.visible | length')"
ipc quiet off probe >/dev/null
left=$(( $(ipc activities | jq '.visible[0].expiresAt') - $(now_ms) ))
check "off: it has about the time it had when the notch went quiet (3.5 s to 4 s)" "true" \
  "$([[ $left -gt 2800 && $left -le 4000 ]] && echo true || echo "false ($left ms)")"
sleep 4.6
check "…and then it runs out as it would have" "0" "$(ipc activities | jq '.visible | length')"

echo; echo "${BOLD}A plugin that goes away lets its hold go${RESET}"
ipc quiet on acme.demo:probe >/dev/null; settle
check "held under a plugin's name" "true acme.demo:probe hidden" \
  "$(qrep '"\(.quiet) \(.holds[0].owner)"') $(st)"
check "a hold under another name is not touched by its going" "quiet released" \
  "$(ipc quiet on probe) $(ipc quiet off probe)"
harness setNotch '{"batteryPeek":false,"disabledIntegrations":["acme.demo"]}' >/dev/null
for _ in $(seq 1 40); do sleep 0.1; [[ $(qrep .quiet) == false ]] && break; done
check "switched off: the hold is gone and the notch is back" "false" "$(qrep .quiet)"
settle
check "…showing the resting notch" "compact" "$(st)"
harness setNotch '{"batteryPeek":false}' >/dev/null
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc integrations | jq -r '.list[] | select(.id == "acme.demo") | .accepted') == true ]] && break; done

check "no QML errors in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" | head -1 | cut -c1-120)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" || echo none)"
stop

# --- D. the fail-safes ------------------------------------------------------------------

echo; echo "${BOLD}It can never stay hidden${RESET}  ${DIM}lease 1.2 s, cap 3 s, cooldown 2.5 s${RESET}"
start NOTCH_QUIET_LEASE_MS=1200 NOTCH_QUIET_CAP_MS=3000 NOTCH_QUIET_COOLDOWN_MS=2500
ipc view settings >/dev/null; settle
ipc quiet on probe >/dev/null; settle
check "held: the settings are put away" "false hidden" "$(ipc geometry | jq -r '"\(.settingsOpen) \(.state)"')"
sleep 1.0
check "nobody renews it: it lapses by itself, and the notch is back where it was" "false true" \
  "$(qrep .quiet) $(ipc geometry | jq -r .settingsOpen)"
check "…it is not refused afterwards: a lapse is not misbehaviour" "quiet" "$(ipc quiet on probe)"
ipc quiet off probe >/dev/null; ipc back >/dev/null; settle

ipc quiet on probe >/dev/null
for _ in 1 2 3; do sleep 0.7; ipc quiet on probe >/dev/null; done
check "renewed every 0.7 s, it is still held after 2.1 s (more than one lease)" "true" "$(qrep .quiet)"
for _ in $(seq 1 12); do sleep 0.4; ipc quiet on probe >/dev/null; [[ $(qrep .quiet) == false ]] && break; done
check "a requester that never stops is cut off at the cap" "false" "$(qrep .quiet)"
check "…and refused for a while after it, with the reason" "declined:cooldown probe" \
  "$(ipc quiet on probe) $(qrep '.refused | join(",")')"
check "…another owner is not refused for it" "quiet" "$(ipc quiet on other)"
ipc quiet off other >/dev/null
sleep 2.7
check "…once the cooldown is over it may ask again" "quiet" "$(ipc quiet on probe)"
ipc quiet off probe >/dev/null
check "…and the refusal list is empty" "" "$(qrep '.refused | join(",")')"

check "no QML errors in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" | head -1 | cut -c1-120)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" || echo none)"
stop

# --- E. notifications -------------------------------------------------------------------

echo; echo "${BOLD}A notification is never dropped${RESET}  ${DIM}a sandbox live.json, as dev/notifications.sh${RESET}"
nroot="$work/nroot"; ndir="$work/notifications"; live="$ndir/live.json"
mkdir -p "$nroot" "$ndir"; : >"$live"
ln -s "$SHELL_PATH/shell/Commons" "$nroot/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$nroot/Ui"
ln -s "$SHELL_PATH/shell/services" "$nroot/services"
ln -s "$REPO" "$nroot/notch"
cp "$REPO/dev/harness/shell.qml" "$nroot/shell.qml"
n() { quickshell ipc -p "$nroot" call notch "$@" 2>/dev/null; }
notifs() { n notifications; }
state_of() { notifs | jq -r --arg n "$1" '.entries[] | select(.name == $n) | .state'; }
wait_for() { # wait_for <jq filter over `notifications`> <expected> [tries]
  local tries=${3:-40} got
  for _ in $(seq 1 "$tries"); do got=$(notifs | jq -r "$1" 2>/dev/null); [[ $got == "$2" ]] && return 0; sleep 0.1; done
  return 1
}
put() { # put <key> <summary>
  jq -c --arg key "$1" --arg summary "$2" --argjson ts "$(date +%s.%3N)" \
    '(. // []) + [{key: $key, originalId: 1, senderPid: 0, execArgv: "", execActions: "", glyph: "", app: "test", appIcon: "",
       summary: $summary, body: "", rawBody: "", source: "", groupKey: "app:test", urgency: 1,
       expireTimeout: 0, duration: 8000, ts: $ts}]' <"$live" 2>/dev/null >"$live.tmp" || echo "[{\"key\":\"$1\"}]" >"$live.tmp"
  mv "$live.tmp" "$live"
}
echo '[]' >"$live"
NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_FORCE_NOTIFICATIONS=1 NOTCH_NOTIFICATIONS_DIR="$ndir" \
  NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"notificationSeconds":4}' quickshell -p "$nroot" -n >>"$work/qsn.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 80); do sleep 0.1; [[ $(n geometry) == \{* ]] && break; done
sleep 0.5

put n1 "Time to recharge!"
wait_for .claimed 1
check "a toast is on the notch (4 s on its own clock)" "shown activity" "$(state_of n1) $(n geometry | jq -r .state)"
sleep 1
n quiet on probe >/dev/null; settle
check "quiet: the notch is hidden" "hidden" \
  "$(n geometry | jq -r .state)"
put n2 "Arrived while quiet"
wait_for '.entries | map(select(.name == "n2")) | length' 1
check "a toast that arrives meanwhile is declined as a hidden bar declines it, not lost" "declined:quiet" "$(state_of n2)"
sleep 5
check "…five seconds on, longer than the first one's whole life: it is still on the books" "shown 1" \
  "$(state_of n1) $(notifs | jq -r '[.entries[] | select(.state == "shown")] | length')"
n quiet off probe >/dev/null
wait_for '[.entries[] | select(.state == "shown" or .state == "queued")] | length' 2 30
check "off: the toast that was on the notch and the one that arrived meanwhile are both on it" "shown shown" \
  "$(state_of n1) $(state_of n2)"
check "…and the notch is showing one of them" "activity" "$(n geometry | jq -r .state)"
off_at=$(date +%s%3N)
wait_for .claimed 0 80
took=$(( $(date +%s%3N) - off_at ))
check "…they close on their own clock: the first with its remaining 3 s, the second with its 4 s (not before 2.5 s, not after 6.5)" "true" \
  "$([[ $took -gt 2500 && $took -lt 6500 ]] && echo true || echo "false ($took ms)")"
check "…and the notch goes back to rest" "compact" "$(n geometry | jq -r .state)"
check "no QML errors in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qsn.log" | head -1 | cut -c1-120)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qsn.log" || echo none)"
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed.${RESET}"; exit 1; fi
echo "${GREEN}All $checks checks pass.${RESET}"
