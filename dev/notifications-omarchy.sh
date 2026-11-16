#!/bin/bash

# The notch, the notifications companion and Omarchy's own notification service
# together, as numbers.
#
#   ./dev/notifications-omarchy.sh
#
# dev/notifications.sh and dev/notifications-companion.sh test each half
# against a stand-in. This one runs the real service: a copy of Omarchy's
# Service.qml (with only its notification server cut out, so it cannot take the
# real bus name from the running shell) in a throwaway Quickshell instance,
# with its state folder under a temporary $HOME. Cards arrive the way the
# service's own arrival path puts them up; what comes out is the service's own
# live.json, the notch reading it, and the service's own windows being on or
# off. It is the check that Omarchy has not moved what the companion finds by
# shape. Needs a display (the service draws real windows, briefly, when the
# notch is not taking a card).

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
STOCK="$SHELL_PATH/shell/plugins/notifications"
[[ -f $STOCK/Service.qml && -f $STOCK/Store.js ]] || { echo "notifications-omarchy: no Omarchy 4.5 notifications service at $STOCK" >&2; exit 1; }

sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-omarchy.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "${sb:?}"; }
trap cleanup EXIT

root="$sb/root"; home="$sb/home"; dir="$home/.local/state/omarchy/notifications"; live="$dir/live.json"
mkdir -p "$root/stock" "$home"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
# Laid out like the plugins folder, so the companion's "../kalinewb.notch/bridge/Connector.qml"
# is the very file the notch imports (one bridge, not two).
ln -s "$REPO" "$root/kalinewb.notch"
ln -s "$REPO/companion/kalinewb.notch-notifications" "$root/kalinewb.notch-notifications"
cp "$STOCK"/*.js "$STOCK"/*.qml "$root/stock/"
# Everything but the server: the model, the windows, the store, the IPC.
python3 - "$root/stock/Service.qml" <<'PY'
import re, sys
p = sys.argv[1]
s = open(p).read()
i = s.index("  NotificationServer {")
depth, j = 0, s.index("{", i)
while True:
    depth += (s[j] == "{") - (s[j] == "}")
    j += 1
    if depth == 0: break
open(p, "w").write(s[:i] + s[j:])
PY
cp "$REPO/dev/harness/notifications-omarchy-shell.qml" "$root/shell.qml"

n() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
o() { quickshell ipc -p "$root" call omarchytest "$@" 2>/dev/null; }
notifs() { n notifications; }
state_of() { notifs | jq -r --arg k "$1" '.entries[] | select(.name == $k) | .state'; }
wait_for() { # wait_for <command printing the value> <expected> [tries]
  local tries=${3:-50} got
  for _ in $(seq 1 "$tries"); do
    got=$(eval "$1" 2>/dev/null)
    [[ $got == "$2" ]] && return 0
    sleep 0.1
  done
  return 1
}
mapped() { o state | jq -r '[.mapped[] | select(.)] | length'; }
is_mapped() { [[ $(mapped) -gt 0 ]] && echo true || echo false; }
live_keys() { jq -r '[.[].key] | join(",")' "$live" 2>/dev/null; }
# Whether any window of Omarchy's was on screen at any moment in the next n samples.
ever_mapped() { # ever_mapped <samples>
  local seen=0
  for _ in $(seq 1 "$1"); do [[ $(mapped) != 0 ]] && seen=1; sleep 0.05; done
  echo "$seen"
}

HOME="$home" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
  NOTCH_FORCE_NOTIFICATIONS=1 NOTCH_NOTIFICATIONS_DIR="$dir" \
  NOTCH_NOTIFICATIONS_STOCK_URL="file://$root/stock/Service.qml" \
  NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"suppressNativeToast":true,"notificationStay":true}' \
  quickshell -p "$root" -n >"$sb/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 100); do sleep 0.1; [[ $(n geometry) == \{* ]] && break; done
wait_for "o state | jq -r .ready" true 100

echo "${BOLD}The notch, the companion and Omarchy's own service${RESET}  ${DIM}$STOCK${RESET}"
check "1. the companion loads Omarchy's service and finds its toast list and its windows by shape" "true true true true true" \
  "$(o info | jq -r '[.loaded, .stock, .model, .bound > 0, .suppressible] | map(tostring) | join(" ")')"
check "2. the notch is taking toasts, and with none on screen the service's windows are off" "true 0" \
  "$(o info | jq -r .takeOver) $(mapped)"

# --- a card arrives -----------------------------------------------------------------
o arrive c1 "Time to recharge" plain >/dev/null
seen=$(ever_mapped 12)
wait_for 'notifs | jq -r .claimed' 1
check "3. a card arrives: the service writes it to live.json under its own key" "c1" "$(live_keys)"
check "4. …the notch draws it" "shown" "$(state_of c1)"
check "5. …and Omarchy's own toast was never on screen, not even for a moment" "0" "$seen"
check "6. …and the notch tells the companion it has it" "true false" \
  "$(notifs | jq -r '.entries[0] | "\(.drawn) \(.drawnNext)"')"

# --- updated in place ---------------------------------------------------------------
sleep 0.3
o arrive c1 "Time to recharge, again" plain >/dev/null
seen=$(ever_mapped 12)
check "7. the card is updated in place: the notch draws the new words, one line, no toast" "Time to recharge, again 1 0" \
  "$(n activities | jq -r '.visible[0].title') $(notifs | jq -r '.entries | length') $seen"

# --- the user acts on the notch's copy ------------------------------------------------
key=$(notifs | jq -r '.entries[0].key')
check "8. dismiss it in the notch: Omarchy's service closes that card by its key" "service" "$(n interactNotification "$key" dismiss)"
wait_for 'o state | jq -r .count' 0
wait_for 'live_keys' ""
check "9. …and it is gone from the service's list and from live.json" "0 " "$(o state | jq -r .count) $(live_keys)"

# --- cards the notch cannot draw ------------------------------------------------------
o arrive t1 "Asked not to be kept" transient >/dev/null
wait_for 'is_mapped' true
check "10. a card that asks not to be kept is not in live.json, so Omarchy's own toast shows for it" "none true 0" \
  "$(live_keys | sed 's/^$/none/') $(is_mapped) $(notifs | jq -r .claimed)"
o close t1 >/dev/null
wait_for 'mapped' 0
check "11. …and its window goes again when the card leaves" "0" "$(mapped)"

o arrive v1 "Your code is 123456" plain >/dev/null
wait_for 'notifs | jq -r --arg k v1 ".entries[] | select(.name == \$k) | .state"' stock
check "12. a card with a code in it is kept only as a placeholder: the notch leaves it, Omarchy's toast shows" "stock true 0" \
  "$(state_of v1) $(is_mapped) $(notifs | jq -r .claimed)"
o close v1 >/dev/null
wait_for 'mapped' 0

# --- the notch stops taking them -------------------------------------------------------
quickshell ipc -p "$root" call harness setNotch '{"batteryPeek":false,"suppressNativeToast":false,"notificationStay":true}' >/dev/null 2>&1
sleep 0.6
check "13. with the switch off the companion is Omarchy's own: its idle window is mapped again" "false true" \
  "$(o info | jq -r .takeOver) $(is_mapped)"
o arrive c2 "Shown by both" plain >/dev/null
wait_for 'live_keys' c2
check "14. …and a card shows in Omarchy's toast as usual" "true" "$(is_mapped)"

check "15. no QML errors anywhere in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-120)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
