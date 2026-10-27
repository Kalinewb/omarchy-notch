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
#    service when the companion has it loaded, its `notifications` IPC target
#    (the one its keybinds use) when not, and for a toast that has already
#    ended, what the service would have done with the toast's data.
#
# A test notch has no pointer: `notch pointer` and `notch press` stand in for
# one, going down the same functions the real handlers call. A fake
# `omarchy-shell` on PATH records the IPC calls instead of making them, and
# dev/harness/notifications-interact-shell.qml stands in for the companion's
# loaded service. Nothing here touches the user's notifications folder.

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
mkdir -p "$root" "$dir/history" "$bin"
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
key_of() { notifs | jq -r --arg n "$1.json" '.entries[] | select(.name == $n) | .key'; }
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
write() { # write <stamp> <id> <summary> [body] [execArgv json]
  local f="$dir/$1-$2.json"
  jq -nc --argjson id "$2" --arg summary "$3" --arg body "${4:-}" --arg exec "${5:-}" --argjson ts "$1" \
     '{id: $id, originalId: $id, app: "test", appIcon: "", summary: $summary, body: $body,
       image: "", glyph: "", execArgv: $exec, urgency: 1, expireTimeout: 0, timestamp: $ts}' >"$f.tmp"
  mv "$f.tmp" "$f"
}
expire() { mv "$dir/$1.json" "$dir/history/$1.json"; }
now_ms() { date +%s%3N; }
clear_files() { find "$dir" -maxdepth 1 -name '*.json' -delete; }
calls_or_empty() { [[ -s $cli ]] && echo calls || echo empty; }
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

stamp=$(now_ms)
write "$stamp" 1 "Timed"
wait_for '.claimed' 1
t0=$(now_ms)
sleep 1.0
check "3. close after 2 s: still there at one second" "1 activity" "$(notifs | jq -r .claimed) $(st)"
wait_for '.claimed' 0 40
took=$(( $(now_ms) - t0 ))
check "4. …gone about two seconds after it appeared (${took} ms)" "true" "$(within "$took" 1700 3300)"
check "5. …its file untouched, and it does not come back while the file stays" "true closed compact" \
  "$([[ -f $dir/$stamp-1.json ]] && echo true || echo false) $(state_of "$stamp-1.json") $(sleep 1.5; st)"
expire "$stamp-1"
wait_for '.entries | length' 0
check "6. when the file goes too it is forgotten" "0" "$(notifs | jq -r '.entries | length')"

# Omarchy's toast ending does not end the copy.
setnotch '{"batteryPeek":false,"notificationSeconds":4}'
stamp=$(now_ms)
write "$stamp" 2 "Outlives its toast"
wait_for '.claimed' 1
expire "$stamp-2"
sleep 2.0
check "7. Omarchy's toast ended two seconds ago: the notch's copy is still up, no longer linked" "1 false activity" \
  "$(notifs | jq -r .claimed) $(notifs | jq -r '.entries[0].live') $(st)"
wait_for '.claimed' 0 40
check "8. …and goes on its own clock, taking its entry with it" "0 0" "$(notifs | jq -r .claimed) $(notifs | jq -r '.entries | length')"

# Stay until I act.
setnotch '{"batteryPeek":false,"notificationSeconds":2,"notificationStay":true}'
stamp=$(now_ms)
write "$stamp" 3 "Stays"
wait_for '.claimed' 1
expire "$stamp-3"
sleep 4.5
check "9. stay until I act: 4.5 s on, past the seconds, its toast long gone: still up" "true 1 activity" \
  "$(notifs | jq -r .stay) $(notifs | jq -r .claimed) $(st)"
setnotch '{"batteryPeek":false,"notificationSeconds":2,"notificationStay":false}'
wait_for '.claimed' 0 60
check "10. switching to close-after takes effect on the line already up" "0" "$(notifs | jq -r .claimed)"

# The pointer waits the clock.
stamp=$(now_ms)
write "$stamp" 4 "Held under the pointer"
wait_for '.claimed' 1
n pointer true >/dev/null
sleep 3.6
check "11. the pointer on the notch holds the clock: well past 2 s, still up" "1 true" "$(notifs | jq -r .claimed) $(notifs | jq -r .pointerOver)"
n pointer false >/dev/null
wait_for '.claimed' 0 50
check "12. …and it closes once the pointer leaves" "0" "$(notifs | jq -r .claimed)"
expire "$stamp-4"; sleep 0.5
stop

# --- pointing at it is not the hover view ---------------------------------------------
echo; echo "${BOLD}Hover${RESET}"
clear_files
start '{"batteryPeek":false,"hoverItems":["clock"],"openWith":["click"],"notificationStay":true}'
n pointer true >/dev/null; sleep 0.8
check "13. with no toast, hovering shows the hover view (the chain works here)" "expanded hover" "$(n geometry | jq -r '"\(.state) \(.view)"')"
n pointer false >/dev/null; sleep 1.0
check "14. …and it settles back" "compact" "$(st)"
stamp=$(now_ms)
write "$stamp" 5 "Hover me"
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
stamp=$(now_ms)
write "$stamp" 6 "Arrives under the pointer"
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
stamp=$(now_ms)
write "$stamp" 7 "Click me"
wait_for '.claimed' 1
sleep 0.6
n press click >/dev/null; sleep 0.6
check "18. left click: opened through Omarchy's IPC (invokeLast), the notch copy gone" "-q notifications invokeLast|0 dismissed" \
  "$(paste -sd'|' "$cli")|$(notifs | jq -r .claimed) $(state_of "$stamp-7.json")"
check "19. …and that click was not also the notch's: the widgets did not open" "compact" "$(st)"
expire "$stamp-7"; sleep 0.5

: >"$cli"
stamp=$(now_ms)
write "$stamp" 8 "Dismiss me"
wait_for '.claimed' 1
sleep 0.6
n press rightClick >/dev/null; sleep 0.6
check "20. right click: dismissed through Omarchy (dismissOne), and the settings did not open" "-q notifications dismissOne|0 compact false" \
  "$(paste -sd'|' "$cli")|$(notifs | jq -r .claimed) $(st) $(n geometry | jq -r .settingsOpen)"
expire "$stamp-8"; sleep 0.5

# No toast: the same presses are the notch's own again.
n press click >/dev/null; sleep 0.9
check "21. with no toast up, a click is the notch's click again" "expanded" "$(st)"
n collapse >/dev/null; sleep 0.6

# Two toasts: the one clicked is not the newest Omarchy has.
: >"$cli"; rm -f "$sb/ran"
older=$(now_ms)
write "$older" 9 "Older one" "" "[\"touch\",\"$sb/ran\"]"
wait_for '.claimed' 1
sleep 0.05
newer=$(now_ms)
write "$newer" 10 "Newer one"
wait_for '.claimed' 2
k=$(key_of "$older-9")
r=$(n interactNotification "$k" open)
sleep 0.8
check "22. open the older of two: not what invokeLast would act on, so its own action runs and it is dismissed by name" "local true -q notifications dismiss Older one" \
  "$r $([[ -f $sb/ran ]] && echo true || echo false) $(paste -sd'|' "$cli")"
: >"$cli"
k=$(key_of "$newer-10")
n interactNotification "$k" dismiss >/dev/null
check "23. dismiss the newer: dismissOne" "-q notifications dismissOne" "$(sleep 0.3; paste -sd'|' "$cli")"
check "24. an unknown toast is answered as such" "no-such-notification" "$(n interactNotification nonsense open)"
expire "$older-9"; expire "$newer-10"; sleep 0.5

# A toast Omarchy has already ended: not in its service any more.
: >"$cli"; rm -f "$sb/ran"
stamp=$(now_ms)
write "$stamp" 11 "Already ended" "" "[\"touch\",\"$sb/ran\"]"
wait_for '.claimed' 1
expire "$stamp-11"
wait_for '.entries[0].live' false
k=$(key_of "$stamp-11")
r=$(n interactNotification "$k" open)
sleep 0.8
check "25. open one whose toast has ended: its action runs, Omarchy is not asked" "local true empty 0" \
  "$r $([[ -f $sb/ran ]] && echo true || echo false) $(calls_or_empty) $(notifs | jq -r .claimed)"
stamp=$(now_ms)
write "$stamp" 12 "Ended and dismissed"
wait_for '.claimed' 1
expire "$stamp-12"
wait_for '.entries[0].live' false
k=$(key_of "$stamp-12")
check "26. dismiss one whose toast has ended: only the notch's copy goes" "notch 0 empty" \
  "$(n interactNotification "$k" dismiss) $(notifs | jq -r .claimed) $(calls_or_empty)"

# Through the companion's loaded service.
: >"$cli"
t facade true >/dev/null
stamp=$(now_ms)
t popup 99 $((stamp - 5)) >/dev/null
write "$stamp" 13 "Via the service"
t popup 13 "$stamp" >/dev/null
t popup 98 $((stamp + 5)) >/dev/null
wait_for '.claimed' 1
check "27. with the service loaded the report says so" "true" "$(notifs | jq -r .service)"
n press click >/dev/null; sleep 0.6
check "28. left click: the service is asked to invoke this toast's own row (index 1 of 3), not Omarchy's IPC" '["invoke 1"] empty 0' \
  "$(t calls | jq -c .) $(calls_or_empty) $(notifs | jq -r .claimed)"
expire "$stamp-13"; sleep 0.4
stamp=$(now_ms)
write "$stamp" 14 "Dismissed via the service"
t popup 14 "$stamp" >/dev/null
wait_for '.claimed' 1
sleep 0.4
n press rightClick >/dev/null; sleep 0.6
check "29. right click: the service dismisses that row" "invoke 1|dismiss 0 empty" \
  "$(t calls | jq -r 'join("|")') $(calls_or_empty)"
expire "$stamp-14"; sleep 0.4
# …and a toast that is not on its list goes the IPC way.
stamp=$(now_ms)
write "$stamp" 15 "Not on the list"
wait_for '.claimed' 1
sleep 0.4
n press click >/dev/null; sleep 0.6
check "30. a toast the service does not list falls back to the IPC target" "-q notifications invokeLast" "$(paste -sd'|' "$cli")"
expire "$stamp-15"; sleep 0.4
t facade false >/dev/null

# --- stay mode, three at once -------------------------------------------------------------
echo; echo "${BOLD}Three at once, staying${RESET}"
clear_files; sleep 0.6
a=$(now_ms); write "$a" 21 "First"; wait_for '.claimed' 1
b=$((a + 10)); write "$b" 22 "Second"; wait_for '.claimed' 2
c=$((a + 20)); write "$c" 23 "Third"; sleep 1.0
check "31. the newest is on the notch, the oldest steps back to waiting rather than being dropped" "Third|Second,Third|waiting" \
  "$(n activities | jq -r '.visible | sort_by(.shownAt) | last | .title')|$(n activities | jq -r '[.visible[].title] | sort | join(",")')|$(state_of "$a-21.json")"
sleep 11
check "32. …and nothing is dropped later (the queue would drop a waiting line after ten seconds)" "1 3" \
  "$(notifs | jq -r '[.entries[] | select(.state == "waiting")] | length') $(notifs | jq -r '.entries | length')"
n press click >/dev/null; sleep 0.6
check "33. acting on the newest brings the oldest back" "dismissed shown" "$(state_of "$c-23.json") $(state_of "$a-21.json")"
clear_files

check "34. no QML errors anywhere in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"
stop

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
