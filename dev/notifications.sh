#!/bin/bash

# Omarchy's toasts, shown in the notch, as numbers.
#
#   ./dev/notifications.sh
#
# The notch is a display surface only. It does not own
# org.freedesktop.Notifications, never watches the bus and never closes a
# notification: Omarchy keeps the cards on its screen in one file, live.json,
# and the notch watches that file. So this drives the real thing -- a throwaway
# notch, a sandbox folder, and a live.json rewritten whole and replaced in one
# step the way Omarchy's own service writes it (rows as Omarchy 4.5's Store.js
# persistable() writes them: key, originalId, app, summary, body, glyph,
# execArgv, urgency, ts in seconds, ...).
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

root="$sb/root"; dir="$sb/notifications"; live="$dir/live.json"
mkdir -p "$root" "$dir"
# Omarchy makes the file, empty, before it writes anything to it.
: >"$live"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"

n() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
notifs() { n notifications; }
state_of() { notifs | jq -r --arg n "$1" '.entries[] | select(.name == $n) | .state'; }
# Wait for a condition rather than sleeping a guessed amount: the watch is a
# real one and its timing is the machine's, not ours.
wait_for() { # wait_for <jq filter over `notifications`> <expected> [tries]
  local tries=${3:-40} got
  for _ in $(seq 1 "$tries"); do
    got=$(notifs | jq -r "$1" 2>/dev/null)
    [[ $got == "$2" ]] && return 0
    sleep 0.1
  done
  return 1
}

now_s() { date +%s.%3N; }
ago_s() { awk -v n="$(now_s)" -v a="$1" 'BEGIN { printf "%.3f", n - a }'; }

# Omarchy rewrites the whole file and replaces it in one step (a temporary file,
# then a rename), so a reader never sees half of it. put() and drop() do the
# same to the row list: oldest first, a row for a key already there replaced in
# place.
replace() { jq -c "$@" <"$live" >"$live.tmp" && mv "$live.tmp" "$live"; }
# An empty file, and one that will not parse, are no rows.
rows() { local r; r=$(jq -c . "$live" 2>/dev/null); echo "${r:-[]}"; }
put() { # put <key> <ts> <summary> [body] [urgency] [execArgv]
  rows | jq -c --arg key "$1" --argjson ts "$2" --arg summary "$3" --arg body "${4:-}" \
     --argjson urgency "${5:-1}" --arg exec "${6:-}" \
     '{key: $key, originalId: 1, senderPid: 0, execArgv: $exec, execActions: "", glyph: "", app: "test", appIcon: "",
       summary: $summary, body: $body, rawBody: "", source: "", groupKey: "app:test", urgency: $urgency,
       expireTimeout: 0, duration: 8000, ts: $ts} as $r
     | (map(.key) | index($key)) as $i | if $i == null then . + [$r] else .[$i] = $r end' >"$live.tmp"
  mv "$live.tmp" "$live"
}
drop() { rows | jq -c --arg key "$1" 'map(select(.key != $key))' >"$live.tmp"; mv "$live.tmp" "$live"; }

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

echo "${BOLD}Omarchy's notifications in the notch${RESET}  ${DIM}$live${RESET}"

start '{"batteryPeek":false,"notificationSeconds":3}'
check "1. the source is on, watching the sandbox and nothing else" "true true" \
  "$(notifs | jq -r --arg d "$dir" '"\(.enabled) \(.dir == $d)"')"
check "2. it watches rather than polls when the file is there" "inotify" "$(wait_for .watch inotify; notifs | jq -r .watch)"
check "3. nothing is claimed before anything arrives" "0 compact" \
  "$(notifs | jq -r .claimed) $(n geometry | jq -r .state)"

# --- a toast arrives ------------------------------------------------------------
put n1 "$(now_s)" "Time to recharge!" "Battery is down to 10%"
wait_for '.claimed' 1
g=$(n geometry)
check "4. the row claims an activity, shown" "shown" "$(state_of n1)"
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
check "8a. the companion is told it is drawn: this version of the card, not an update of it" "true false" \
  "$(notifs | jq -r '.entries[0] | "\(.drawn) \(.drawnNext)"')"

# --- it ends on the notch's own clock ---------------------------------------------
# (3 s here, the setting; the row leaving is Omarchy's toast ending, which the
# copy outlives -- dev/notifications-interact.sh has that, with the clock off.)
drop n1
wait_for '.claimed' 0 60
check "9. it closes by itself, and the notch goes back to its resting size" "0 compact 180" \
  "$(notifs | jq -r .claimed) $(n geometry | jq -r '"\(.state) \(.target.width)"')"
check "10. …and it is forgotten, not kept as a dead entry" "0" "$(notifs | jq -r '.entries | length')"

# --- markup, which Omarchy's cards render and the notch must not ------------------
put n2 "$(now_s)" "<b>Bold</b> &amp; <i>italic" "line one
line two"
wait_for '.claimed' 1
check "11. markup is stripped and entities decoded, not drawn" "Bold & italic" \
  "$(n activities | jq -r '.visible[0].title')"
check "12. newlines become spaces: one line, not a torn row" "line one line two" \
  "$(n activities | jq -r '.visible[0].detail')"
drop n2; wait_for '.claimed' 0 60

# --- a file that will not parse -----------------------------------------------------
#
# Omarchy replaces the file in one step, so this is somebody else's file. What is
# on screen stays on screen.
put n3 "$(now_s)" "Still here"
wait_for '.claimed' 1
printf '[{"key":"n3","summ' >"$live"
sleep 1.2
check "13. a file that will not parse is read again and then left alone: what was shown is kept" "1 shown" \
  "$(notifs | jq -r .claimed) $(state_of n3)"
check "14. …and it said so once, naming the file" "1" \
  "$(grep -ac "skipped unreadable notification file $live" "$sb/qs.log")"
# Putting a whole file back is a change, and the notch reads it again.
put n3 "$(now_s)" "Finished after all"
wait_for '.entries[0].name' n3
check "15. a file that is whole again is picked up, and the card it names is updated, not doubled" "1 Finished after all" \
  "$(wait_for '.claimed' 1; notifs | jq -r .claimed) $(n activities | jq -r '.visible[0].title')"
drop n3; wait_for '.claimed' 0 60

# --- what predates the notch ------------------------------------------------------
#
# Omarchy restores the cards it had on screen when it restarts, with their old
# times, so a row's `ts` decides, not when the notch happened to look.
put n4 "$(ago_s 600)" "From before this notch started"
# Wait for the read to have seen it and decided, rather than for a guessed
# second: an entry that has not been looked at yet reads as no entry at all,
# which is indistinguishable here from one that was read and ignored.
for _ in $(seq 1 40); do [[ -n $(state_of n4) ]] && break; sleep 0.1; done
check "16. a row stamped before the notch started is ignored, never drawn" "ignored-old 0 false" \
  "$(state_of n4) $(notifs | jq -r .claimed) $(notifs | jq -r '.entries[0].drawn')"
drop n4

# --- dismissing -------------------------------------------------------------------
put n5 "$(now_s)" "Dismiss me"
wait_for '.claimed' 1
key=$(notifs | jq -r '.entries[] | select(.name == "n5") | .key')
check "17. dismissing clears it from the notch" "dismissed 0 compact" \
  "$(n dismissNotification "$key") $(sleep 0.5; notifs | jq -r .claimed) $(n geometry | jq -r .state)"
check "18. …and the file is left exactly as it was: nothing written, nothing told to Omarchy" "1 dismissed" \
  "$(rows | jq length) $(state_of n5)"
check "19. …and it does not come back while its row stays as it was" "0 dismissed" \
  "$(sleep 2.2; notifs | jq -r .claimed) $(state_of n5)"
# A card Omarchy updates in place says something new, as its own toast does.
put n5 "$(now_s)" "Dismissed, then changed"
wait_for '.claimed' 1
check "19a. …but an update to that card brings it back, with its new words" "1 Dismissed, then changed" \
  "$(notifs | jq -r .claimed) $(n activities | jq -r '.visible[0].title')"
drop n5; wait_for '.claimed' 0 60

# --- updated in place ---------------------------------------------------------------
t1=$(now_s)
put n6 "$t1" "First words"
wait_for '.claimed' 1
sleep 0.3
t2=$(now_s)
put n6 "$t2" "Second words"
for _ in $(seq 1 40); do [[ $(n activities | jq -r '.visible[0].title') == "Second words" ]] && break; sleep 0.1; done
check "20. a card updated in place is the same line with its new words, not a second one" "1 Second words 1" \
  "$(notifs | jq -r .claimed) $(n activities | jq -r '.visible[0].title') $(notifs | jq -r '.entries | length')"
check "20a. …and the companion is told the new version is drawn too" "true" "$(notifs | jq -r '.entries[0].drawn')"
drop n6; wait_for '.claimed' 0 60

# --- a card with a code in it -------------------------------------------------------
#
# Omarchy keeps such a card in the file only as a placeholder. The notch leaves
# it to Omarchy's own toast, which has the button for the code.
put n7 "$(now_s)" "Verification notification" "[redacted]"
for _ in $(seq 1 40); do [[ -n $(state_of n7) ]] && break; sleep 0.1; done
check "21. a placeholder is left to Omarchy's toast: not drawn, not claimed, and the companion told so" "stock 0 false" \
  "$(state_of n7) $(notifs | jq -r .claimed) $(notifs | jq -r '.entries[0].drawn')"
drop n7
wait_for '.entries | length' 0
check "21a. …and forgotten with its row" "0" "$(notifs | jq -r '.entries | length')"

# --- more at once than the notch will hold -----------------------------------------
for i in 1 2 3 4 5 6; do put "b$i" "$(now_s)" "Burst $i"; sleep 0.02; done
sleep 1.5
claimed=$(notifs | jq -r '[.entries[] | select(.state == "shown" or .state == "queued")] | length')
waiting=$(notifs | jq -r '[.entries[] | select(.state == "waiting")] | length')
check "22. a burst is capped at the owner limit, the rest wait rather than flood the queue" "4 2" \
  "$claimed $waiting"
# The queue holds two at once and the notch draws one of them (Bar.qml
# activityLine): sideways placement has no room for a second line.
check "23. …the queue holds at most its two, and the notch stays one row tall" "true 32" \
  "$(n activities | jq -r '.visible | length <= 2') $(n geometry | jq -r '.target.height')"
check "23a. …the ones still waiting are not drawn, so Omarchy's toast stays for them" "4 2" \
  "$(notifs | jq -r '[.entries[] | select(.drawn)] | length') $(notifs | jq -r '[.entries[] | select(.drawn | not)] | length')"
echo '[]' >"$live.tmp"; mv "$live.tmp" "$live"
wait_for '.claimed' 0 80
check "24. they all go when their rows do, and the ones that waited never come up late" "0 0" \
  "$(notifs | jq -r '.entries | length') $(notifs | jq -r .claimed)"

# --- the file going away ----------------------------------------------------------------
put n8 "$(now_s)" "Before the file goes"
wait_for '.claimed' 1
mv "$live" "$sb/moved.json"
for _ in $(seq 1 40); do [[ $(notifs | jq -r .watch) == "waiting-file" ]] && break; sleep 0.1; done
check "25. the file disappearing releases everything rather than holding stale lines" "waiting-file 0 compact" \
  "$(notifs | jq -r .watch) $(notifs | jq -r .claimed) $(n geometry | jq -r .state)"
mv "$sb/moved.json" "$live"
for _ in $(seq 1 60); do [[ $(notifs | jq -r .watch) == "inotify" ]] && break; sleep 0.1; done
check "26. …and it picks the file back up by itself" "inotify" "$(notifs | jq -r .watch)"
drop n8; wait_for '.claimed' 0

# --- the setting is the whole of the user's part --------------------------------------
put n9 "$(now_s)" "Switched off under it"
wait_for '.claimed' 1
quickshell ipc -p "$root" call harness setNotch '{"batteryPeek":false,"notifications":false}' >/dev/null 2>&1
sleep 0.8
check "27. switching it off lets go at once and leaves nothing behind" "false 0 0 compact" \
  "$(notifs | jq -r .enabled) $(notifs | jq -r .claimed) $(notifs | jq -r '.entries | length') $(n geometry | jq -r .state)"
stop

# --- polling, for a machine where the watch will not hold -------------------------------
echo '[]' >"$live"
NOTCH_NOTIFICATIONS_WATCH=poll start '{"batteryPeek":false,"notificationSeconds":3}'
check "28. told to poll, it polls" "poll" "$(wait_for .watch poll; notifs | jq -r .watch)"
put p1 "$(now_s)" "Found by polling"
wait_for '.claimed' 1 60
check "29. …and finds a toast anyway" "shown Found by polling" \
  "$(state_of p1) $(n activities | jq -r '.visible[0].title')"
drop p1
wait_for '.claimed' 0 60
check "30. …and lets go of it anyway" "0" "$(notifs | jq -r .claimed)"
stop

# --- a notification must never be silently missed ----------------------------------------
echo '[]' >"$live"
start '{"batteryPeek":false,"autoHide":true,"collapseDelay":0,"notificationSeconds":3}'
check "31. with auto-hide on, the notch is tucked into the edge" "true hidden" \
  "$(n geometry | jq -r '.autoHide.on') $(n geometry | jq -r .state)"
put a1 "$(now_s)" "Arrived while tucked away"
wait_for '.claimed' 1
check "32. a toast arriving brings it back out rather than being missed" "activity false" \
  "$(n geometry | jq -r .state) $(n geometry | jq -r '.autoHide.hidden')"
drop a1
wait_for '.claimed' 0
check "33. …and it tucks away again once the toast ends" "hidden true" \
  "$(sleep 0.8; n geometry | jq -r .state) $(n geometry | jq -r '.autoHide.hidden')"
stop

# --- the promise itself -------------------------------------------------------------------
# Comments in those files say what the notch does not do, so only code counts.
check "34. no D-Bus, no notification server, no closing, no do-not-disturb" "0" \
  "$(grep -vE "^\s*(//|\*)" "$REPO/NotchNotifications.qml" "$REPO/notifications.js" \
      | grep -cE "NotificationServer|CloseNotification|org\.freedesktop\.Notifications|DBus|doNotDisturb")"
# What a click does (open, dismiss) is Omarchy's, dev/notifications-interact.sh;
# what is drawn is still text.
check "35. no image or icon is read: text only" "0" \
  "$(grep -vE "^\s*(//|\*)" "$REPO/NotchNotifications.qml" "$REPO/notifications.js" \
      | grep -cE "appIcon|\bimage\b")"
check "36. no QML errors anywhere in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
