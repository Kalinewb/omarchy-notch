#!/bin/bash

# Replacing the Omarchy menu, as numbers.
#
#   ./dev/menu-replace.sh
#
# The companion plugin (companion/graveklar.notch-menu) is what Omarchy routes
# every menu call to. Its go-between hands each request to the notch when the
# "Replace the Omarchy menu" setting is on, and to Omarchy's own menu
# otherwise. Here the notch and the companion run in one throwaway Quickshell
# instance laid out like ~/.config/omarchy/plugins, so the go-between finds the
# notch's bridge at the same relative path it uses live -- no override.
#
# Omarchy's own menu is stood in for (dev/harness/FakeStockMenu.qml): the real
# one opens a full-screen window that takes the keyboard, which a test must
# never do on the user's screen.
#
# Sections:
#   A  the bridge: the notch registers, the go-between finds it, versions gate it
#   B  routing: setting on/off, no notch, and what the shell's toggle reads
#   C  pickers: a superseded or destroyed request is released, never left hanging
#   D  close, refresh and ping reach both sides
#   E  the notch's own settings still alias omarchy.menu to the companion's button
#   F  bin/notch-companion against a sandbox plugins folder

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
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-menu-replace.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
# Laid out like the plugins folder: the go-between resolves the notch's bridge
# through "../graveklar.notch/bridge/Connector.qml", exactly as it does live.
ln -s "$REPO" "$root/graveklar.notch"
ln -s "$REPO/companion/graveklar.notch-menu" "$root/graveklar.notch-menu"
cp "$REPO/dev/harness/menu-replace-shell.qml" "$root/shell.qml"
cp "$REPO/dev/harness/FakeStockMenu.qml" "$root/FakeStockMenu.qml"
MANIFEST=$(jq -c . "$REPO/companion/graveklar.notch-menu/manifest.json")

ipc() { quickshell ipc -p "$root" call menu-replace "$@" 2>/dev/null; }
notch_ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
b64() { printf '%s' "$1" | base64 -w0; }
start() { # start <notch config json> [env...]
  local config=$1; shift
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_HARNESS_CONFIG="$config" MENU_REPLACE_MANIFEST="$MANIFEST" \
    NOTCH_MENU_STOCK_URL="file://$root/FakeStockMenu.qml" "$@" \
    quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc state) == \{* ]] && break; done
  sleep 0.6
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

echo "${BOLD}A. The bridge${RESET}"
start '{"replaceMenu":true,"batteryPeek":false}'
s=$(ipc state)
echo "  ${DIM}$(jq -c '{facade, bridge, notchSeen, version, stockSource: (.stockSource | split("/") | last)}' <<<"$s")${RESET}"
check "the go-between loads, finds the notch's bridge and its menu API" "true true true" \
  "$(jq -r '"\(.facade) \(.bridge) \(.notchSeen)"' <<<"$s")"
check "…with the companion's own version, and Omarchy's menu as its first source" "1.0.0 FakeStockMenu.qml" \
  "$(jq -r '"\(.version) \(.stockSource | split("/") | last)"' <<<"$s")"
check "the notch reports the companion as active, with the setting on" "true active active-on" \
  "$(notch_ipc geometry | jq -r '.menu.replace | "\(.bridged) \(.companion) \(.status)"')"
stop
start '{"replaceMenu":true,"batteryPeek":false}' NOTCH_MENU_BRIDGE_API=2
check "a bridge API the companion doesn't speak means no notch (it uses Omarchy's menu)" "true false" \
  "$(ipc state | jq -r '"\(.bridge) \(.notchSeen)"')"
stop

echo; echo "${BOLD}B. Routing${RESET}"
start '{"replaceMenu":true,"batteryPeek":false}'
route=$(ipc open "$(b64 '{"menu":"root"}')")
sleep 1.0
s=$(ipc state); g=$(notch_ipc geometry)
check "setting on: the request goes to the notch, which opens its menu" "notch true expanded menu" \
  "$route $(jq -r '.stock.opens == 0' <<<"$s") $(jq -r '"\(.state) \(.view)"' <<<"$g")"
check "…and the shell's toggle sees the menu as open" "true" "$(jq -r .opened <<<"$s")"
ipc close >/dev/null; sleep 0.9
check "close closes it" "false false" "$(notch_ipc geometry | jq -r .menu.open) $(ipc state | jq -r .opened)"
stop

start '{"replaceMenu":false,"batteryPeek":false}'
route=$(ipc open "$(b64 '{"menu":"root"}')")
sleep 0.8
s=$(ipc state)
check "setting off: Omarchy's own menu takes it, the notch stays shut" "stock 1 true false" \
  "$route $(jq -r '.stock.opens' <<<"$s") $(jq -r .opened <<<"$s") $(notch_ipc geometry | jq -r .menu.open)"
check "…and the notch reports the setting off" "false active-off stock" \
  "$(notch_ipc geometry | jq -r '.menu.replace | "\(.setting) \(.status) \(.facadeRoute)"')"
ipc close >/dev/null; sleep 0.6
notch_ipc menu root >/dev/null; sleep 0.9
check "a notch menu opened its own way doesn't swallow SUPER + SPACE while the setting is off" "true false" \
  "$(notch_ipc geometry | jq -r .menu.open) $(ipc state | jq -r .opened)"
ipc open "$(b64 '{"menu":"root"}')" >/dev/null; sleep 0.9
check "…and opening Omarchy's menu closes it, so there is only ever one menu" "false true" \
  "$(notch_ipc geometry | jq -r .menu.open) $(ipc state | jq -r .stock.opened)"
stop

start '{"replaceMenu":true,"batteryPeek":false}' MENU_REPLACE_NO_NOTCH=1
route=$(ipc open "$(b64 '{"menu":"root"}')")
check "no notch running: Omarchy's own menu takes it" "stock false 1" \
  "$route $(ipc state | jq -r '"\(.notchSeen) \(.stock.opens)"' | tr '\n' ' ' | sed 's/ $//')"
stop

echo; echo "${BOLD}C. Pickers${RESET}"
start '{"replaceMenu":true,"batteryPeek":false}'
sel="$root/sel1"; done1="$root/done1"; done2="$root/done2"
ipc open "$(b64 "{\"mode\":\"select\",\"prompt\":\"Pick\",\"options\":[\"a\",\"b\"],\"selectionFile\":\"$sel\",\"doneFile\":\"$done1\"}")" >/dev/null
sleep 1.0
check "a picker opens in the notch and waits (no done file yet)" "expanded menu false" \
  "$(notch_ipc geometry | jq -r '"\(.state) \(.view)"') $([[ -e $done1 ]] && echo true || echo false)"
ipc open "$(b64 "{\"mode\":\"select\",\"prompt\":\"Again\",\"options\":[\"c\"],\"selectionFile\":\"$sel\",\"doneFile\":\"$done2\"}")" >/dev/null
for _ in $(seq 1 30); do sleep 0.1; [[ -e $done1 ]] && break; done
check "a second picker releases the first, so its caller isn't left hanging" "true false" \
  "$([[ -e $done1 ]] && echo true || echo false) $([[ -e $done2 ]] && echo true || echo false)"
ipc unload notch >/dev/null
for _ in $(seq 1 30); do sleep 0.1; [[ -e $done2 ]] && break; done
check "the notch going away (a plugin reload) releases the picker still waiting" "true" "$([[ -e $done2 ]] && echo true || echo false)"
stop

start '{"replaceMenu":false,"batteryPeek":false}'
done3="$root/done3"; done4="$root/done4"
ipc open "$(b64 "{\"mode\":\"select\",\"options\":[\"a\"],\"selectionFile\":\"$sel\",\"doneFile\":\"$done3\"}")" >/dev/null
sleep 0.5
check "with the setting off, the picker goes to Omarchy's menu and waits" "true true false" \
  "$(ipc state | jq -r '"\(.stock.opened) \(.stock.requestActive)"') $([[ -e $done3 ]] && echo true || echo false)"
ipc open "$(b64 "{\"mode\":\"select\",\"options\":[\"b\"],\"selectionFile\":\"$sel\",\"doneFile\":\"$done4\"}")" >/dev/null
for _ in $(seq 1 30); do sleep 0.1; [[ -e $done3 ]] && break; done
check "…and a second one releases it there too" "true" "$([[ -e $done3 ]] && echo true || echo false)"
ipc unload facade >/dev/null
for _ in $(seq 1 30); do sleep 0.1; [[ -e $done4 ]] && break; done
check "…as does the companion going away" "true" "$([[ -e $done4 ]] && echo true || echo false)"
stop

echo; echo "${BOLD}D. The rest of the lifecycle${RESET}"
start '{"replaceMenu":true,"batteryPeek":false}'
check "ping answers" "ok" "$(ipc ping)"
check "refresh reaches Omarchy's menu as well as the notch's" "ok 1" "$(ipc refresh) $(ipc state | jq -r .stock.refreshes)"
stop

echo; echo "${BOLD}E. The menu button's id${RESET}"
# Its own root, laid out like the contract harness (which imports "notch").
alias_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-menu-alias.XXXXXX")
ln -s "$SHELL_PATH/shell/Commons" "$alias_root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$alias_root/Ui"
ln -s "$REPO" "$alias_root/notch"
cp "$REPO/dev/harness/contract-shell.qml" "$alias_root/shell.qml"
alias_ipc() { quickshell ipc -p "$alias_root" call notch "$@" 2>/dev/null; }
LAYOUT='{"left":[{"id":"graveklar.notch-menu"}],"center":[],"right":[]}'
NOTCH_HARNESS=1 NOTCH_HARNESS_BAR="{\"layout\":$LAYOUT,\"notch\":{\"hoverPlugins\":[\"omarchy.menu\"],\"batteryPeek\":false}}" \
  quickshell -p "$alias_root" -n >>"$root/qs.log" 2>&1 &
alias_pid=$!
for _ in $(seq 1 50); do sleep 0.1; [[ $(alias_ipc geometry) == \{* ]] && break; done
sleep 0.8
check "with the companion's button in the layout, a setting naming omarchy.menu follows it" '["graveklar.notch-menu"]' \
  "$(alias_ipc geometry | jq -c .hoverPlugins)"
kill "$alias_pid" 2>/dev/null; wait "$alias_pid" 2>/dev/null; rm -rf "$alias_root"

echo; echo "${BOLD}F. bin/notch-companion${RESET}"
sb="$root/sandbox"; mkdir -p "$sb/plugins" "$sb/state"
comp() { NOTCH_COMPANION_DIR="$sb/plugins" NOTCH_COMPANION_LIST="${LIST:-echo []}" NOTCH_COMPANION_ENABLE="true" \
         NOTCH_COMPANION_VALIDATE="omarchy plugin validate" NOTCH_COMPANION_STATE_DIR="$sb/state" \
         NOTCH_COMPANION_DISCOVER_MS=300 "$REPO/bin/notch-companion" "$@"; }
check "a hook without the sandbox folder is refused" '2 {"error":"sandbox"}' \
  "$(NOTCH_COMPANION_LIST="echo []" "$REPO/bin/notch-companion" status >"$root/out" 2>/dev/null; echo $?) $(cat "$root/out")"
check "status before anything is installed" "false null " "$(comp status | jq -r '"\(.installed) \(.inSync) \(.conflict)"')"
comp install "$sb/state/companion.json" >/dev/null 2>&1
check "install copies the companion in, with the notch's version" "done true true 1.0.0" \
  "$(jq -r .phase "$sb/state/companion.json") $(comp status | jq -r '"\(.installed) \(.inSync) \(.version)"')"
check "…and validates as an Omarchy plugin" "0" "$(omarchy plugin validate "$sb/plugins/graveklar.notch-menu" >/dev/null 2>&1; echo $?)"
before=$(stat -c %Y "$sb/plugins/graveklar.notch-menu/manifest.json")
comp sync "$sb/state/companion.json" >/dev/null 2>&1
check "sync with identical files writes nothing (no plugin reload)" "done $before" \
  "$(jq -r .phase "$sb/state/companion.json") $(stat -c %Y "$sb/plugins/graveklar.notch-menu/manifest.json")"
echo "// changed" >>"$sb/plugins/graveklar.notch-menu/BarWidget.qml"
check "…and a changed installed copy is out of sync" "false" "$(comp status | jq -r .inSync)"
comp sync "$sb/state/companion.json" >/dev/null 2>&1
check "sync copies it again, and keeps the old one as a backup" "done true 1" \
  "$(jq -r .phase "$sb/state/companion.json") $(comp status | jq -r .inSync) $(ls "$sb/state/backups" | wc -l)"
LIST='echo [{"id":"someone.else","enabled":true}]'
mkdir -p "$sb/plugins/someone.else" && jq -n '{schemaVersion:1, id:"someone.else", omarchy:{clonedFrom:"omarchy.menu"}}' >"$sb/plugins/someone.else/manifest.json"
check "another plugin already replacing Omarchy's menu is a conflict" "someone.else" "$(comp status | jq -r .conflict)"
comp install "$sb/state/companion.json" >/dev/null 2>&1
check "…and install refuses while it is there" "failed" "$(jq -r .phase "$sb/state/companion.json")"
rm -rf "$sb/plugins/someone.else"; LIST='echo []'
check "a locked session refuses too" "failed" \
  "$(NOTCH_COMPANION_SESSION_LOCKED=true comp install "$sb/state/companion.json" >/dev/null 2>&1; jq -r .phase "$sb/state/companion.json")"
comp remove "$sb/state/companion.json" >/dev/null 2>&1
check "remove hands it to omarchy plugin remove" "done" "$(NOTCH_COMPANION_REMOVE="rm -rf $sb/plugins/graveklar.notch-menu --" comp remove "$sb/state/companion.json" >/dev/null 2>&1; jq -r .phase "$sb/state/companion.json")"
check "…and it is gone" "false" "$(comp status | jq -r .installed)"

if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
