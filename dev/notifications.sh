#!/bin/bash

# Omarchy's toasts, shown in the notch, as numbers.
#
#   ./dev/notifications.sh
#
# The notch is a display surface only. It does not own
# org.freedesktop.Notifications, never watches the bus and never closes a
# notification: Omarchy writes one JSON file per live toast into a folder, and
# the notch watches that folder. So this drives the real thing -- a throwaway
# notch, a sandbox folder, and files written and moved the way Omarchy's own
# service writes and moves them (verified against a real file: the fields are
# app, summary, body, glyph, urgency, timestamp).
#
# Nothing here touches the user's own notifications folder: the source only
# reads $NOTCH_NOTIFICATIONS_DIR here, and a test notch is refused the real one.

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

sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-notifications.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

root="$sb/root"; dir="$sb/notifications"
mkdir -p "$root" "$dir/history"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"

n() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
notifs() { n notifications; }
state_of() { notifs | jq -r --arg n "$1" '.entries[] | select(.name == $n) | .state'; }
# Wait for a condition rather than sleeping a guessed amount: the watcher is a
# real process and its timing is the machine's, not ours.
wait_for() { # wait_for <jq filter over `notifications`> <expected> [tries]
  local tries=${3:-40} got
  for _ in $(seq 1 "$tries"); do
    got=$(notifs | jq -r "$1" 2>/dev/null)
    [[ $got == "$2" ]] && return 0
    sleep 0.1
  done
  return 1
}

# Omarchy writes the file, then the watch fires on close. Writing to a .tmp and
# moving it is how a half-written file is avoided; write() does the same.
write() { # write <stamp> <id> <summary> [body] [urgency]
  local f="$dir/$1-$2.json"
  jq -nc --argjson id "$2" --arg app "test" --arg summary "$3" --arg body "${4:-}" \
     --argjson urgency "${5:-1}" --argjson ts "$1" \
     '{id: $id, originalId: $id, app: $app, appIcon: "", summary: $summary, body: $body,
       image: "", glyph: "", execArgv: "", urgency: $urgency, expireTimeout: 0, timestamp: $ts}' \
     >"$f.tmp"
  mv "$f.tmp" "$f"
}
expire() { mv "$dir/$1.json" "$dir/history/$1.json"; }   # what Omarchy does when a toast ends
now_ms() { date +%s%3N; }

start() { # start [extra notch config json]
  NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_FORCE_NOTIFICATIONS=1 NOTCH_NOTIFICATIONS_DIR="$dir" \
    NOTCH_HARNESS_CONFIG="${1:-{\"batteryPeek\":false\}}" \
    quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 80); do sleep 0.1; [[ $(n geometry) == \{* ]] && break; done
  sleep 0.5
}
# The generic harness has no quit IPC (only hosting-shell.qml has one), so this
# stops the notch the way dev/colours.sh does. Waiting on a quit that never
# arrives is a hang, not a failure.
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

echo "${BOLD}Omarchy's notifications in the notch${RESET}  ${DIM}$dir${RESET}"

start '{"batteryPeek":false}'
check "1. the source is on, watching the sandbox and nothing else" "true true" \
  "$(notifs | jq -r --arg d "$dir" '"\(.enabled) \(.dir == $d)"')"
check "2. it watches rather than polls when inotifywait is there" "inotify" "$(notifs | jq -r .watch)"
check "3. nothing is claimed before anything arrives" "0 compact" \
  "$(notifs | jq -r .claimed) $(n geometry | jq -r .state)"

# --- a toast arrives ------------------------------------------------------------
stamp=$(now_ms)
write "$stamp" 1 "Time to recharge!" "Battery is down to 10%"
wait_for '.claimed' 1
g=$(n geometry)
check "4. the file claims an activity, shown" "shown" "$(state_of "$stamp-1.json")"
check "5. the notch is showing it" "activity" "$(jq -r .state <<<"$g")"
# It grows sideways for the title and DOWN for the body -- one elided row was a
# notification you could watch arrive and could not read. Sampled once it has
# settled, because the growth is the notch's usual spring and reading mid-flight
# measures the animation instead of the result.
for _ in $(seq 1 60); do
  g=$(n geometry)
  [[ $(jq -r '.bar.height > 32 and .bar.width > 180' <<<"$g") == true ]] && break
  sleep 0.1
done
check "6. …and grew sideways for the title and down for the body" "true true" \
  "$(jq -r '.bar.height > 32' <<<"$g") $(jq -r '.bar.width > 180' <<<"$g")"
check "6a. …still one surface on the screen edge: square top corners, top edge at zero" "0 0 0" \
  "$(jq -r '.bar.y' <<<"$g") $(jq -r '.radii.topLeft' <<<"$g") $(jq -r '.radii.topRight' <<<"$g")"
check "6b. …and it is a notch, not a panel: no taller than a third of the screen" "true" \
  "$(jq -r '.bar.height < 300' <<<"$g")"
check "7. the summary is the title and the body the detail" "Time to recharge! Battery is down to 10%" \
  "$(n activities | jq -r '.visible[0] | "\(.title) \(.detail)"')"
check "8. it is the notch's own owner, at transient priority" "notch.notifications transient" \
  "$(n activities | jq -r '.visible[0] | "\(.owner) \(.priority)"')"

# --- it ends the way Omarchy ends it --------------------------------------------
expire "$stamp-1"
wait_for '.claimed' 0
check "9. the file leaving releases it, and the notch goes back to its resting size" "0 compact 180" \
  "$(notifs | jq -r .claimed) $(n geometry | jq -r '"\(.state) \(.target.width)"')"
check "10. …and it is forgotten, not kept as a dead entry" "0" "$(notifs | jq -r '.entries | length')"

# --- markup, which Omarchy's cards render and the notch must not ------------------
stamp=$(now_ms)
write "$stamp" 2 "<b>Bold</b> &amp; <i>italic" "line one
line two"
wait_for '.claimed' 1
check "11. markup is stripped and entities decoded, not drawn" "Bold & italic" \
  "$(n activities | jq -r '.visible[0].title')"
check "12. newlines become spaces: one line, not a torn row" "line one line two" \
  "$(n activities | jq -r '.visible[0].detail')"
expire "$stamp-2"; wait_for '.claimed' 0

# --- a file caught mid-write ------------------------------------------------------
stamp=$(now_ms)
printf '{"id":3,"summary":"half' >"$dir/$stamp-3.json"
sleep 0.9
check "13. an unparseable file is retried and then skipped, not claimed" "skipped 0" \
  "$(state_of "$stamp-3.json") $(notifs | jq -r .claimed)"
check "14. …and it said so once, naming the file" "1" \
  "$(grep -ac "skipped unreadable notification $stamp-3.json" "$sb/qs.log")"
# Finishing the write is a CLOSE_WRITE, and the notch tries again.
write "$stamp" 3 "Finished after all"
wait_for '.claimed' 1
check "15. a file that finishes being written is picked up on the next close" "shown Finished after all" \
  "$(state_of "$stamp-3.json") $(n activities | jq -r '.visible[0].title')"
expire "$stamp-3"; wait_for '.claimed' 0

# --- what predates the notch ------------------------------------------------------
#
# Omarchy rewrites restored toasts under their old names at restart, so the name's
# stamp decides, not the mtime: otherwise every shell restart replays old toasts.
old=$(( $(now_ms) - 600000 ))
write "$old" 4 "From before this notch started"
# Wait for the watcher to have seen it and decided, rather than for a guessed
# second: an entry that has not been looked at yet reads as no entry at all,
# which is indistinguishable here from one that was read and ignored.
for _ in $(seq 1 40); do [[ -n $(state_of "$old-4.json") ]] && break; sleep 0.1; done
check "16. a file stamped before the notch started is ignored, never read" "ignored-old 0" \
  "$(state_of "$old-4.json") $(notifs | jq -r .claimed)"
rm -f "$dir/$old-4.json"

# --- dismissing -------------------------------------------------------------------
stamp=$(now_ms)
write "$stamp" 5 "Dismiss me"
wait_for '.claimed' 1
key=$(notifs | jq -r --arg n "$stamp-5.json" '.entries[] | select(.name == $n) | .key')
check "17. dismissing clears it from the notch" "dismissed 0 compact" \
  "$(n dismissNotification "$key") $(sleep 0.5; notifs | jq -r .claimed) $(n geometry | jq -r .state)"
check "18. …and the file is left exactly as it was: nothing written, nothing told to Omarchy" "true dismissed" \
  "$([[ -f $dir/$stamp-5.json ]] && echo true || echo false) $(state_of "$stamp-5.json")"
check "19. …and it does not come back while its file stays" "0" \
  "$(sleep 2.2; notifs | jq -r .claimed)"
expire "$stamp-5"

# --- more at once than the notch will hold -----------------------------------------
base=$(now_ms)
for i in 1 2 3 4 5 6; do write $((base + i)) "1$i" "Burst $i"; done
sleep 1.5
claimed=$(notifs | jq -r '[.entries[] | select(.state == "shown" or .state == "queued")] | length')
waiting=$(notifs | jq -r '[.entries[] | select(.state == "waiting")] | length')
check "20. a burst is capped at the owner limit, the rest wait rather than flood the queue" "4 2" \
  "$claimed $waiting"
# The queue holds two at once and the notch draws one of them (Bar.qml
# activityLine): sideways placement has no room for a second line.
check "21. …the queue holds at most its two, and the notch stays one row tall" "true 32" \
  "$(n activities | jq -r '.visible | length <= 2') $(n geometry | jq -r '.target.height')"
for i in 1 2 3 4 5 6; do expire "$((base + i))-1$i"; done
wait_for '.claimed' 0
check "22. they all go when their files do" "0 0" \
  "$(notifs | jq -r '.entries | length') $(notifs | jq -r .claimed)"

# --- the folder going away ----------------------------------------------------------
stamp=$(now_ms)
write "$stamp" 7 "Before the folder goes"
wait_for '.claimed' 1
mv "$dir" "$sb/moved"
for _ in $(seq 1 40); do [[ $(notifs | jq -r .watch) == "waiting-dir" ]] && break; sleep 0.1; done
check "23. the folder disappearing releases everything rather than holding stale lines" "waiting-dir 0 compact" \
  "$(notifs | jq -r .watch) $(notifs | jq -r .claimed) $(n geometry | jq -r .state)"
mv "$sb/moved" "$dir"
for _ in $(seq 1 60); do [[ $(notifs | jq -r .watch) == "inotify" ]] && break; sleep 0.1; done
check "24. …and it picks the folder back up by itself" "inotify" "$(notifs | jq -r .watch)"
expire "$stamp-7"; wait_for '.claimed' 0

# --- the setting is the whole of the user's part --------------------------------------
stamp=$(now_ms)
write "$stamp" 8 "Switched off under it"
wait_for '.claimed' 1
quickshell ipc -p "$root" call harness setNotch '{"batteryPeek":false,"notifications":false}' >/dev/null 2>&1
sleep 0.8
check "25. switching it off lets go at once and leaves nothing behind" "false 0 0 compact" \
  "$(notifs | jq -r .enabled) $(notifs | jq -r .claimed) $(notifs | jq -r '.entries | length') $(n geometry | jq -r .state)"
stop

# --- polling, for a machine without inotifywait -----------------------------------------
rm -f "$dir"/*.json
NOTCH_NOTIFICATIONS_WATCH=poll start '{"batteryPeek":false}'
check "26. told to poll, it polls" "poll" "$(notifs | jq -r .watch)"
stamp=$(now_ms)
write "$stamp" 9 "Found by polling"
wait_for '.claimed' 1 60
check "27. …and finds a toast anyway" "shown Found by polling" \
  "$(state_of "$stamp-9.json") $(n activities | jq -r '.visible[0].title')"
expire "$stamp-9"
wait_for '.claimed' 0 60
check "28. …and lets go of it anyway" "0" "$(notifs | jq -r .claimed)"
stop

# --- a notification must never be silently missed ----------------------------------------
rm -f "$dir"/*.json
start '{"batteryPeek":false,"autoHide":true,"collapseDelay":0}'
check "29. with auto-hide on, the notch is tucked into the edge" "true hidden" \
  "$(n geometry | jq -r '.autoHide.on') $(n geometry | jq -r .state)"
stamp=$(now_ms)
write "$stamp" 10 "Arrived while tucked away"
wait_for '.claimed' 1
check "30. a toast arriving brings it back out rather than being missed" "activity false" \
  "$(n geometry | jq -r .state) $(n geometry | jq -r '.autoHide.hidden')"
expire "$stamp-10"
wait_for '.claimed' 0
check "31. …and it tucks away again once the toast ends" "hidden true" \
  "$(sleep 0.8; n geometry | jq -r .state) $(n geometry | jq -r '.autoHide.hidden')"
stop

# --- the promise itself -------------------------------------------------------------------
# Comments in those files say what the notch does not do, so only code counts.
check "32. no D-Bus, no notification server, no closing, no do-not-disturb" "0" \
  "$(grep -vE "^\s*(//|\*)" "$REPO/NotchNotifications.qml" "$REPO/notifications.js" \
      | grep -cE "NotificationServer|CloseNotification|org\.freedesktop\.Notifications|DBus|doNotDisturb")"
check "33. no image, icon or action is read: text only" "0" \
  "$(grep -cE "appIcon|execArgv|\bimage\b" "$REPO/NotchNotifications.qml" "$REPO/notifications.js" \
      | awk -F: '{s+=$2} END {print s+0}')"
check "34. no QML errors anywhere in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
