#!/bin/bash

# Omarchy's on-screen display, shown in the notch.
#
#   ./dev/osd.sh
#
# Omarchy sends every OSD call -- the volume and brightness keys, the media
# buttons -- to whichever enabled plugin says `clonedFrom: omarchy.osd`. That
# is companion/kalinewb.notch-osd, whose go-between hands each call to the
# notch when the notch will take it and to Omarchy's own card when it will not.
#
# The notch and the companion run here in one throwaway Quickshell instance
# laid out like ~/.config/omarchy/plugins, so the go-between resolves the
# notch's bridge at the same relative path it uses live -- no override. That is
# the one line deciding whether a real install routes to the notch at all.
#
# Omarchy's own OSD is stood in for (dev/harness/FakeStockOsd.qml): the real one
# maps a full-screen layer-shell window, which a test must not do on the user's
# screen.
#
# Sections:
#   A  the bridge: the notch registers, the go-between finds it, versions gate it
#   B  routing: the setting on and off, and with no notch behind the companion
#   C  a key press never does nothing: every decline still shows something
#   D  what the notch draws: Omarchy's own glyph and readout, on the notch's row
#   E  bin/notch-companion installs THIS companion, told which one it is

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
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-osd.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
# Laid out like the plugins folder, so "../kalinewb.notch/bridge/Connector.qml"
# resolves exactly as it does live.
ln -s "$REPO" "$root/kalinewb.notch"
ln -s "$REPO/companion/kalinewb.notch-osd" "$root/kalinewb.notch-osd"
cp "$REPO/dev/harness/osd-shell.qml" "$root/shell.qml"
cp "$REPO/dev/harness/FakeStockOsd.qml" "$root/FakeStockOsd.qml"
MANIFEST=$(jq -c . "$REPO/companion/kalinewb.notch-osd/manifest.json")

ipc() { quickshell ipc -p "$root" call osd-test "$@" 2>/dev/null; }
notch_ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
# Unpadded: Quickshell's IPC CLI reads an argument containing "=" as an option
# and refuses the call. The harness puts the padding back.
b64() { printf '%s' "$1" | base64 -w0 | tr -d '='; }
state() { ipc state; }
field() { jq -r "$2" <<<"$1"; }

start() { # start <notch config json> [env...]
  local config=$1; shift
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_HARNESS_CONFIG="$config" OSD_MANIFEST="$MANIFEST" \
    NOTCH_OSD_STOCK_URL="file://$root/FakeStockOsd.qml" "$@" \
    quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 60); do sleep 0.1; [[ $(state) == \{* ]] && break; done
  sleep 0.6
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

# Wait for the notch to be showing what the check is about, rather than
# sleeping long enough that it usually is.
settle() { # settle <want> <command...>
  local want=$1; shift
  local got="" deadline=$((SECONDS + 8))
  while :; do
    got=$("$@" 2>/dev/null)
    [[ $got == "$want" ]] && break
    (( SECONDS >= deadline )) && break
    sleep 0.05
  done
  printf '%s' "$got"
}
notch_state() { notch_ipc geometry | jq -r .state; }

# ---------------------------------------------------------------------------
echo "${BOLD}A. The bridge${RESET}"
start '{"replaceOsd":true,"batteryPeek":false}'
s=$(state)
check "1. the go-between loaded, with its manifest's version" "true 1.0.0" \
  "$(field "$s" .facade) $(field "$s" .version)"
check "2. it found the notch's bridge at the live relative path" "true" "$(field "$s" .bridge)"
check "3. …and the notch had registered an API it can use" "true" "$(field "$s" .notchSeen)"
stop

# A companion that speaks another API version must not reach a notch that
# speaks this one: it uses Omarchy's own OSD instead.
start '{"replaceOsd":true,"batteryPeek":false}' NOTCH_OSD_BRIDGE_API=99
s=$(state)
check "4. a version mismatch hides the notch from the go-between" "true false" \
  "$(field "$s" .bridge) $(field "$s" .notchSeen)"
check "5. …and the call goes to Omarchy's own OSD" "stock true" \
  "$(ipc send "$(b64 '{"icon":"volume","value":30}')") $(field "$(state)" .stock.opened)"
stop

# ---------------------------------------------------------------------------
echo; echo "${BOLD}B. Routing${RESET}"
start '{"replaceOsd":true,"batteryPeek":false}'
check "6. with the setting on, the notch takes it" "notch" "$(ipc send "$(b64 '{"icon":"volume","value":40}')")"
check "7. …and the notch is showing an OSD" "osd" "$(settle osd notch_state)"
# Not "shut": never built. Omarchy's Osd.qml owns the `osd` IPC target the CLI
# calls, so the go-between loads it only when a fallback is really needed --
# otherwise a volume key reaches the card this plugin loaded for itself instead
# of the notch.
check "8. …and Omarchy's own card was never even loaded" "null" \
  "$(field "$(state)" .stock)"
stop

start '{"replaceOsd":false,"batteryPeek":false}'
check "9. with the setting off, Omarchy's own OSD takes it" "stock" \
  "$(ipc send "$(b64 '{"icon":"volume","value":40}')")"
check "10. …and the notch drew nothing" "compact" "$(notch_state)"
check "11. …which is what the shell's toggle reads" "true" "$(field "$(state)" .opened)"
stop

start '{"replaceOsd":true,"batteryPeek":false}' OSD_NO_NOTCH=1
check "12. with no notch behind it, Omarchy's own OSD takes it" "stock" \
  "$(ipc send "$(b64 '{"icon":"volume","value":40}')")"
check "13. …and the go-between says there was no notch to ask" "false" \
  "$(field "$(state)" .notchSeen)"
stop

# ---------------------------------------------------------------------------
echo; echo "${BOLD}C. A key press never does nothing${RESET}"
start '{"replaceOsd":true,"batteryPeek":false}'
# A panel is what the user opened, and an OSD over it would cover it. The notch
# declines in words, and the card answers instead.
notch_ipc settings >/dev/null; sleep 0.6
check "14. with a panel open the notch declines, in words" "stock declined:panel-open" \
  "$(ipc send "$(b64 '{"icon":"volume","value":40}')") $(field "$(state)" .declined)"
check "15. …and Omarchy's own card showed it" "true 1" \
  "$(field "$(state)" .stock.opened) $(field "$(state)" .stock.opens)"
notch_ipc toggle >/dev/null; sleep 0.6

# Neither display may be left up under the other: one event, one answer.
check "16. back with no panel, the notch takes it again" "notch" \
  "$(ipc send "$(b64 '{"icon":"volume","value":45}')")"
check "17. …and Omarchy's card was closed as the notch took over" "false 1" \
  "$(field "$(state)" .stock.opened) $(field "$(state)" .stock.closes)"

check "18. a payload that isn't JSON is declined rather than drawn" "stock declined:bad-payload" \
  "$(ipc send "$(b64 'not json')") $(field "$(state)" .declined)"
stop

# ---------------------------------------------------------------------------
echo; echo "${BOLD}D. What the notch draws${RESET}"
start '{"replaceOsd":true,"batteryPeek":false,"compact":[]}'
rest=$(notch_ipc geometry | jq -r '.bar.width | floor')
ipc send "$(b64 '{"icon":"volume","value":40}')" >/dev/null
settle osd notch_state >/dev/null
check "19. a volume OSD widens the notch: icon, bar and readout" "true" \
  "$(notch_ipc geometry | jq -r --argjson rest "$rest" '(.bar.width | floor) > $rest')"
check "20. …and it is one row: the notch never grows down for an OSD" "true" \
  "$(notch_ipc geometry | jq -r '(.bar.height | floor) <= 33')"
# The duration is Omarchy's, from the payload.
ipc send "$(b64 '{"icon":"volume","value":40,"duration":250}')" >/dev/null
check "21. it goes when its duration is up, and the notch rests" "compact" "$(settle compact notch_state)"
stop

# ---------------------------------------------------------------------------
echo; echo "${BOLD}E. Installing this companion, not the other one${RESET}"
# One script installs both; NOTCH_COMPANION_ID says which. Against a sandbox
# plugins folder, never the user's.
mkdir -p "$root/plugins"
comp() { NOTCH_COMPANION_ID=kalinewb.notch-osd NOTCH_COMPANION_SOURCE_ID=omarchy.osd \
  NOTCH_COMPANION_DIR="$root/plugins" NOTCH_COMPANION_LIST="echo []" NOTCH_COMPANION_ENABLE="true" \
  NOTCH_COMPANION_VALIDATE="true" NOTCH_COMPANION_STATE_DIR="$root/state" \
  NOTCH_COMPANION_DISCOVER_MS=1 "$REPO/bin/notch-companion" "$@" 2>/dev/null; }

check "22. nothing installed to begin with" "false" "$(comp status | jq -r .installed)"
comp install "$root/state/companion-osd.json" >/dev/null
check "23. install put THIS companion in the folder" "true true" \
  "$([[ -f $root/plugins/kalinewb.notch-osd/manifest.json ]] && echo true || echo false) $(comp status | jq -r .installed)"
check "24. …and not the menu's" "false" \
  "$([[ -d $root/plugins/kalinewb.notch-menu ]] && echo true || echo false)"
check "25. …with the id and the clonedFrom Omarchy routes on" "kalinewb.notch-osd omarchy.osd" \
  "$(jq -r '.id' "$root/plugins/kalinewb.notch-osd/manifest.json") $(jq -r '.omarchy.clonedFrom' "$root/plugins/kalinewb.notch-osd/manifest.json")"
check "26. …and the install names this companion, not the other one" "true" \
  "$(jq -r '.message | test("kalinewb.notch-osd")' "$root/state/companion-osd.json")"
# The sync and remove paths are where the script has to say which companion it
# is talking about in words, since both read the same otherwise.
comp sync "$root/state/companion-osd.json" >/dev/null
check "26a. …and a sync says so in the OSD's words, not the menu's" "true" \
  "$(jq -r '.message | test("OSD")' "$root/state/companion-osd.json")"

check "27. no QML errors anywhere in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log" || echo none)"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
