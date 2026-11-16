#!/bin/bash

# Acting on a toast in the notch, and how long it stays, as numbers.
#
#   ./dev/notifications-interact.sh
#
# 1. How long the notch's copy stays: until the user acts, or a number of
#    seconds after it appears (the two Notifications settings), whatever
#    Omarchy's own toast does -- and the pointer waits the clock.
# 2. Pointing at a toast is not reaching for the hover view.
# 3. Left click opens it, right click dismisses it, by Omarchy's own calls: its
#    service (`activate` / `closeToast`, by the card's key) when the companion has it loaded, its `notifications` IPC target
#    (the one its keybinds use) when not, and for a toast that has already
#    ended, what the service would have done with the toast's data.
#
# A test notch has no pointer: `notch pointer` and `notch press` stand in for
# one, going down the same functions the real handlers call. A fake
# `omarchy-shell` on PATH records the IPC calls instead of making them, and
# dev/harness/notifications-interact-shell.qml stands in for the companion's
# loaded service. Nothing here touches the user's notifications folder: the
# rows are written to a sandbox live.json, replaced in one step the way
# Omarchy 4.5 replaces its own.

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

sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-interact.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "${sb:?}"; }
trap cleanup EXIT

root="$sb/root"; dir="$sb/notifications"; bin="$sb/bin"; cli="$sb/cli.log"
mkdir -p "$root" "$dir" "$bin"
: >"$dir/live.json"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/notifications-interact-shell.qml" "$root/shell.qml"
printf '#!/bin/sh\necho "$*" >> "%s"\n' "$cli" >"$bin/omarchy-shell"; chmod +x "$bin/omarchy-shell"
: >"$cli"

n() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
t() { quickshell ipc -p "$root" call notifytest "$@" 2>/dev/null; }
notifs() { n notifications; }
state_of() { notifs | jq -r --arg n "$1" '.entries[] | select(.name == $n) | .state'; }
key_of() { notifs | jq -r --arg n "$1" '.entries[] | select(.name == $n) | .key'; }
st() { n geometry | jq -r .state; }
wait_for() { # wait_for <jq filter over `notifications`> <expected> [tries]
  local tries=${3:-40} got
  for _ in $(seq 1 "$tries"); do
    got=$(notifs | jq -r "$1" 2>/dev/null)
    [[ $got == "$2" ]] && return 0
    sleep 0.1
  done
  return 1
}
live="$dir/live.json"
# Omarchy rewrites the whole file and replaces it in one step; put() and drop()
# do the same to the row list: oldest first, a key already there replaced in place.
rows() { local r; r=$(jq -c . "$live" 2>/dev/null); echo "${r:-[]}"; }
put() { # put <key> <ts> <summary> [body] [execArgv json]
  rows | jq -c --arg key "$1" --argjson ts "$2" --arg summary "$3" --arg body "${4:-}" --arg exec "${5:-}" \
     '{key: $key, originalId: 1, senderPid: 0, execArgv: $exec, execActions: "", glyph: "", app: "test", appIcon: "",
       summary: $summary, body: $body, rawBody: "", source: "", groupKey: "app:test", urgency: 1,
       expireTimeout: 0, duration: 8000, ts: $ts} as $r
     | (map(.key) | index($key)) as $i | if $i == null then . + [$r] else .[$i] = $r end' >"$live.tmp"
  mv "$live.tmp" "$live"
}
drop() { rows | jq -c --arg key "$1" 'map(select(.key != $key))' >"$live.tmp"; mv "$live.tmp" "$live"; }
now_s() { date +%s.%3N; }
now_ms() { date +%s%3N; }
clear_files() { echo '[]' >"$live.tmp"; mv "$live.tmp" "$live"; }
# What was asked of Omarchy, leaving out the read-only isDnd the notch's menu
# makes to decide which of its entries to show (Omarchy 4.5's menu file asks).
cli_calls() { grep -v ' isDnd$' "$cli" | paste -sd'|'; }
calls_or_empty() { [[ -n $(cli_calls) ]] && echo calls || echo empty; }
within() { (( $1 >= $2 && $1 <= $3 )) && echo true || echo false; }

start() { # start <notch config json>
  PATH="$bin:$PATH" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_FORCE_NOTIFICATIONS=1 NOTCH_NOTIFICATIONS_DIR="$dir" NOTCH_HARNESS_CONFIG="$1" \
    quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 80); do sleep 0.1; [[ $(n geometry) == \{* ]] && break; done
  sleep 0.5
}
# The settings reach a test notch whole (it has no shell.json to write to).
setnotch() { quickshell ipc -p "$root" call harness setNotch "$1" >/dev/null 2>&1; sleep 0.4; }
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

echo "${BOLD}Notifications: how long, and acting on them${RESET}  ${DIM}$dir${RESET}"

# --- how long it stays --------------------------------------------------------------
echo; echo "${BOLD}How long it stays${RESET}"
start '{"batteryPeek":false}'
check "1. by default: close after 6 seconds, not stay" "false 6000" "$(notifs | jq -r '"\(.stay) \(.lifetimeMs)"')"
setnotch '{"batteryPeek":false,"notificationSeconds":0}'
a=$(notifs | jq -r .lifetimeMs)
setnotch '{"batteryPeek":false,"notificationSeconds":999}'
b=$(notifs | jq -r .lifetimeMs)
setnotch '{"batteryPeek":false,"notificationSeconds":"nonsense"}'
c=$(notifs | jq -r .lifetimeMs)
setnotch '{"batteryPeek":false,"notificationSeconds":2.4}'
d=$(notifs | jq -r .lifetimeMs)
check "2. the seconds are held to 1..60, a whole number, and nonsense is the default" "1000 60000 6000 2000" "$a $b $c $d"
setnotch '{"batteryPeek":false,"notificationSeconds":2}'

put k1 "$(now_s)" "Timed"
wait_for '.claimed' 1
t0=$(now_ms)
sleep 1.0
check "3. close after 2 s: still there at one second" "1 activity" "$(notifs | jq -r .claimed) $(st)"
wait_for '.claimed' 0 40
took=$(( $(now_ms) - t0 ))
check "4. …gone about two seconds after it appeared (${took} ms)" "true" "$(within "$took" 1700 3300)"
check "5. …its file untouched, and it does not come back while the file stays" "true closed compact" \
  "$(rows | jq "any(.key == \"k1\")") $(state_of k1) $(sleep 1.5; st)"
drop k1
wait_for '.entries | length' 0
check "6. when the file goes too it is forgotten" "0" "$(notifs | jq -r '.entries | length')"

# Omarchy's toast ending does not end the copy.
setnotch '{"batteryPeek":false,"notificationSeconds":4}'
put k2 "$(now_s)" "Outlives its toast"
wait_for '.claimed' 1
drop k2
sleep 2.0
check "7. Omarchy's toast ended two seconds ago: the notch's copy is still up, no longer linked" "1 false activity" \
  "$(notifs | jq -r .claimed) $(notifs | jq -r '.entries[0].live') $(st)"
wait_for '.claimed' 0 40
check "8. …and goes on its own clock, taking its entry with it" "0 0" "$(notifs | jq -r .claimed) $(notifs | jq -r '.entries | length')"

# Stay until I act.
setnotch '{"batteryPeek":false,"notificationSeconds":2,"notificationStay":true}'
put k3 "$(now_s)" "Stays"
wait_for '.claimed' 1
drop k3
sleep 4.5
check "9. stay until I act: 4.5 s on, past the seconds, its toast long gone: still up" "true 1 activity" \
  "$(notifs | jq -r .stay) $(notifs | jq -r .claimed) $(st)"
setnotch '{"batteryPeek":false,"notificationSeconds":2,"notificationStay":false}'
wait_for '.claimed' 0 60
check "10. switching to close-after takes effect on the line already up" "0" "$(notifs | jq -r .claimed)"

# The pointer waits the clock.
put k4 "$(now_s)" "Held under the pointer"
wait_for '.claimed' 1
n pointer true >/dev/null
sleep 3.6
check "11. the pointer on the notch holds the clock: well past 2 s, still up" "1 true" "$(notifs | jq -r .claimed) $(notifs | jq -r .pointerOver)"
n pointer false >/dev/null
wait_for '.claimed' 0 50
check "12. …and it closes once the pointer leaves" "0" "$(notifs | jq -r .claimed)"
drop k4; sleep 0.5
stop

# --- pointing at it is not the hover view ---------------------------------------------
echo; echo "${BOLD}Hover${RESET}"
clear_files
start '{"batteryPeek":false,"hoverItems":["clock"],"openWith":["click"],"notificationStay":true}'
n pointer true >/dev/null; sleep 0.8
check "13. with no toast, hovering shows the hover view (the chain works here)" "expanded hover" "$(n geometry | jq -r '"\(.state) \(.view)"')"
n pointer false >/dev/null; sleep 1.0
check "14. …and it settles back" "compact" "$(st)"
put k5 "$(now_s)" "Hover me"
wait_for '.claimed' 1
sleep 0.6
n pointer true >/dev/null; sleep 1.0
check "15. hovering a toast does not switch to the hover view" "activity" "$(st)"
n pointer false >/dev/null; sleep 0.6
check "16. …and leaving it does nothing to it" "activity 1" "$(st) $(notifs | jq -r .claimed)"
n press click >/dev/null; sleep 0.8
n collapse >/dev/null
# A toast arriving under a resting pointer replaces the hover view.
n pointer true >/dev/null; sleep 0.8
hv=$(st)
put k6 "$(now_s)" "Arrives under the pointer"
wait_for '.claimed' 1
sleep 0.8
check "17. hover view up, a toast arrives: it takes the notch rather than hiding under the hover view" "expanded activity" "$hv $(st)"
n pointer false >/dev/null; sleep 0.4
n press click >/dev/null; sleep 0.8
stop

# --- acting on it -----------------------------------------------------------------------
echo; echo "${BOLD}Acting on it${RESET}"
clear_files; : >"$cli"
start '{"batteryPeek":false,"openWith":["click"],"settingsWith":["rightClick"],"notificationStay":true}'
put k7 "$(now_s)" "Click me"
wait_for '.claimed' 1
sleep 0.6
n press click >/dev/null; sleep 0.6
check "18. left click: opened through Omarchy's IPC (invokeLast), the notch copy gone" "-q notifications invokeLast|0 dismissed" \
  "$(cli_calls)|$(notifs | jq -r .claimed) $(state_of k7)"
check "19. …and that click was not also the notch's: the widgets did not open" "compact" "$(st)"
drop k7; sleep 0.5

: >"$cli"
put k8 "$(now_s)" "Dismiss me"
wait_for '.claimed' 1
sleep 0.6
n press rightClick >/dev/null; sleep 0.6
check "20. right click: dismissed through Omarchy (dismissOne), and the settings did not open" "-q notifications dismissOne|0 compact false" \
  "$(cli_calls)|$(notifs | jq -r .claimed) $(st) $(n geometry | jq -r .settingsOpen)"
drop k8; sleep 0.5

# No toast: the same presses are the notch's own again.
n press click >/dev/null; sleep 0.9
check "21. with no toast up, a click is the notch's click again" "expanded" "$(st)"
n collapse >/dev/null; sleep 0.6

# Two toasts: the one clicked is not the newest Omarchy has.
: >"$cli"; rm -f "$sb/ran"
put k9 "$(now_s)" "Older one" "" "[\"touch\",\"$sb/ran\"]"
wait_for '.claimed' 1
sleep 0.05
put k10 "$(now_s)" "Newer one"
wait_for '.claimed' 2
k=$(key_of k9)
r=$(n interactNotification "$k" open)
sleep 0.8
check "22. open the older of two: not what invokeLast would act on, so its own action runs and it is dismissed by name" "local true -q notifications dismiss Older one" \
  "$r $([[ -f $sb/ran ]] && echo true || echo false) $(cli_calls)"
: >"$cli"
k=$(key_of k10)
n interactNotification "$k" dismiss >/dev/null
check "23. dismiss the newer: dismissOne" "-q notifications dismissOne" "$(sleep 0.3; cli_calls)"
check "24. an unknown toast is answered as such" "no-such-notification" "$(n interactNotification nonsense open)"
drop k9; drop k10; sleep 0.5

# A toast Omarchy has already ended: not in its service any more.
: >"$cli"; rm -f "$sb/ran"
put k11 "$(now_s)" "Already ended" "" "[\"touch\",\"$sb/ran\"]"
wait_for '.claimed' 1
drop k11
wait_for '.entries[0].live' false
k=$(key_of k11)
r=$(n interactNotification "$k" open)
sleep 0.8
check "25. open one whose toast has ended: its action runs, Omarchy is not asked" "local true empty 0" \
  "$r $([[ -f $sb/ran ]] && echo true || echo false) $(calls_or_empty) $(notifs | jq -r .claimed)"
put k12 "$(now_s)" "Ended and dismissed"
wait_for '.claimed' 1
drop k12
wait_for '.entries[0].live' false
k=$(key_of k12)
check "26. dismiss one whose toast has ended: only the notch's copy goes" "notch 0 empty" \
  "$(n interactNotification "$k" dismiss) $(notifs | jq -r .claimed) $(calls_or_empty)"

# Through the companion's loaded service.
: >"$cli"
t facade true >/dev/null
t popup k99 >/dev/null
put k13 "$(now_s)" "Via the service"
t popup k13 >/dev/null
t popup k98 >/dev/null
wait_for '.claimed' 1
check "27. with the service loaded the report says so" "true" "$(notifs | jq -r .service)"
n press click >/dev/null; sleep 0.6
check "28. left click: the service is asked to open this toast by its key (one of three on its list), not Omarchy's IPC" '["activate k13"] empty 0' \
  "$(t calls | jq -c .) $(calls_or_empty) $(notifs | jq -r .claimed)"
drop k13; sleep 0.4
put k14 "$(now_s)" "Dismissed via the service"
t popup k14 >/dev/null
wait_for '.claimed' 1
sleep 0.4
n press rightClick >/dev/null; sleep 0.6
check "29. right click: the service closes that card by its key" "activate k13|close k14 dismissed empty" \
  "$(t calls | jq -r 'join("|")') $(calls_or_empty)"
drop k14; sleep 0.4
# …and a toast that is not on its list goes the IPC way.
put k15 "$(now_s)" "Not on the list"
wait_for '.claimed' 1
sleep 0.4
n press click >/dev/null; sleep 0.6
check "30. a toast the service does not list falls back to the IPC target" "-q notifications invokeLast" "$(cli_calls)"
drop k15; sleep 0.4
t facade false >/dev/null

# --- stay mode, three at once -------------------------------------------------------------
echo; echo "${BOLD}Three at once, staying${RESET}"
clear_files; sleep 0.6
put k21 "$(now_s)" "First"; wait_for '.claimed' 1
put k22 "$(now_s)" "Second"; wait_for '.claimed' 2
put k23 "$(now_s)" "Third"; sleep 1.0
check "31. the newest is on the notch, the oldest steps back to waiting rather than being dropped" "Third|Second,Third|waiting" \
  "$(n activities | jq -r '.visible | sort_by(.shownAt) | last | .title')|$(n activities | jq -r '[.visible[].title] | sort | join(",")')|$(state_of k21)"
sleep 11
check "32. …and nothing is dropped later (the queue would drop a waiting line after ten seconds)" "1 3" \
  "$(notifs | jq -r '[.entries[] | select(.state == "waiting")] | length') $(notifs | jq -r '.entries | length')"
n press click >/dev/null; sleep 0.6
check "33. acting on the newest brings the oldest back" "dismissed shown" "$(state_of k23) $(state_of k21)"
clear_files

check "34. no QML errors anywhere in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"
stop

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
