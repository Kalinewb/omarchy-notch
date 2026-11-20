#!/bin/bash

# One way back: the strip at the top centre of the notch (SURFACE-HOSTING.md section 15).
#
#   ./dev/backone.sh
#
# A. Origin. Back from a plugin's home goes to where the panel was opened from, not just closed:
#    from the widgets row (grown by a key, a click or the pointer), from the settings, from the
#    Plugins page, and -- with nowhere to go back to -- to the resting notch. The order of one press
#    is an open menu level, then the panel's own pages, then the notch's history, then close.
# B. The zone. The strip is as wide and as tall as the resting notch and the whole of it is the
#    target; nothing of a panel that takes a press sits inside it. `notch backZone` reports every such
#    control of the open panel; the fixture panel (dev/fixtures/zone) puts them in different
#    places, and every page the notch itself draws must report none.
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

work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-backone.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

plugins="$work/plugins"; mkdir -p "$plugins" "$work/state" "$work/markers" "$work/bin"
cp -r "$REPO/dev/fixtures/back/plugins/acme.pages" "$plugins/acme.pages"
cp -r "$REPO/dev/fixtures/zone/plugins/acme.zone" "$plugins/acme.zone"
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
widget() { quickshell ipc -p "$root" call "acme.demo.s0" "$@" 2>/dev/null; }
settle() { sleep 0.9; }
st() { ipc geometry | jq -r '"\(.state)/\(.view)"'; }
rep() { ipc backReport | jq -r '"\(.offered) \(.depth)"'; }
pages() { grep -a 'PAGES ' "$work/qs.log" | tail -n 1 | sed 's/.*PAGES //'; }
rest() { for _ in 1 2 3 4; do [[ $(ipc geometry | jq -r .state) == compact ]] && return; ipc back >/dev/null; ipc collapse >/dev/null; settle; done; }

env PATH="$work/bin:$PATH" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
  NOTCH_FORCE_PLATFORM=1 NOTCH_PLUGINS_DIR="$plugins" NOTCH_PLATFORM_ENABLED="*" \
  NOTCH_PLATFORM_STATE_DIR="$work/state" NOTCH_FIXTURE_MARKER_DIR="$work/markers" \
  NOTCH_PLATFORM_WIDGETS='{"acme.demo": "acme.demo/Widget.qml"}' NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"compactWidth":180}' \
  quickshell -p "$root" -n >"$work/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc integrations | jq -r '.scannedAt > 0') == true ]] && break; done
for _ in $(seq 1 30); do sleep 0.1; [[ $(ipc geometry | jq -r .menu.rowsLoaded) == true ]] && break; done
sleep 0.6

# The notch closes a panel when the session's focus moves (HyprlandFocusGrab), and a suite runs in a session
# someone is using, so a scenario is run again, up to three times, before a mismatch is believed.
scenario() { # scenario <description> <expected> <function>
  local got
  for _ in 1 2 3; do rest; got=$("$3"); [[ $got == "$2" ]] && break; done
  check "$1" "$2" "$got"
}

check "the notch says it has a back zone (the feature word)" "true" \
  "$(ipc integrations | jq -r '.features | index("backZone") != null')"

# --- A. origin ---------------------------------------------------------------------------

echo; echo "${BOLD}Back from a plugin's home goes to where it was opened from${RESET}"

sc_key() {
  ipc expand >/dev/null; settle; local from; from=$(st)
  widget open main >/dev/null; settle; local at; at="$(ipc geometry | jq -r .integration.open) $(rep)"
  echo "$from | $at | $(ipc back) $(settle; st) | $(ipc back) $(settle; st)"
}
scenario "the widgets row grown by a key, the bar button pressed: back from the home returns to the row; the next press has nothing to do" \
  "expanded/widgets | true true 1 | back expanded/widgets | closed expanded/widgets" sc_key

sc_hover() {
  ipc view widgets >/dev/null; settle; local from; from=$(st)
  widget open main >/dev/null; settle
  echo "$from | $(rep) | $(ipc back) $(settle; st)"
}
scenario "the row grown by the pointer: the same" "expanded/widgets | true 1 | back expanded/widgets" sc_hover

sc_settings() {
  ipc view settings >/dev/null; settle
  widget open main >/dev/null; settle; local at; at=$(rep)
  echo "$at | $(ipc back) $(settle; ipc geometry | jq -r '"\(.settingsOpen)/\(.integration.open)"') | $(ipc back) $(settle; st)"
}
scenario "from the settings: back returns to the settings, then closes" "true 1 | back true/false | closed compact/settings" sc_settings

sc_plugins() {
  ipc plugins open >/dev/null; settle
  ipc panel acme.pages main >/dev/null; settle; local at; at=$(rep)
  echo "$at | $(ipc back) $(settle; ipc geometry | jq -r '"\(.view)/\(.integration.open)"')"
}
scenario "from the Plugins page: back returns to the page" "true 1 | back plugins/false" sc_plugins

sc_ipc() {
  ipc panel acme.pages main >/dev/null; settle; local at; at=$(rep)
  echo "$at | $(ipc back) $(settle; ipc geometry | jq -r '"\(.state)/\(.integration.open)"')"
}
scenario "opened by IPC from the resting notch, with no origin: back goes to the resting notch" \
  "true 0 | closed compact/false" sc_ipc

sc_order() {
  ipc expand >/dev/null; settle
  ipc panel acme.pages deep:2 >/dev/null; settle; local at; at="$(rep) $(pages)"
  echo "$at | $(ipc back) $(settle; pages) | $(ipc back) $(settle; pages) | $(ipc back) $(settle; st) | $(ipc back) $(settle; st)"
}
scenario "the order of one press: the panel's own pages first, then the notch it was opened from" \
  "true 1 home/p1/p2 | inside home/p1 | inside home | back expanded/widgets | closed expanded/widgets" sc_order

sc_panel_over_panel() {
  ipc expand >/dev/null; settle
  ipc panel acme.demo main >/dev/null; settle
  ipc panel acme.pages main >/dev/null; settle; local at; at=$(rep)
  echo "$at | $(ipc back) $(settle; ipc geometry | jq -r .integration.id) | $(ipc back) $(settle; st)"
}
scenario "a panel opened from a panel opened from the row: back to the first, then to the row" \
  "true 2 | back acme.demo | back expanded/widgets" sc_panel_over_panel

# --- B. the zone --------------------------------------------------------------------------

echo; echo "${BOLD}The way-back zone${RESET}  ${DIM}notch backZone, dev/fixtures/zone${RESET}"
zone() {
  local got
  for _ in 1 2 3; do
    ipc panel acme.zone "$1" >/dev/null; settle
    got=$(ipc backZone | jq -r '"\(.open) \(.zone.width)x\(.zone.height) \([.hits[].type | sub("QQuick"; "")] | join(","))"')
    [[ $got == integration* ]] && break
    rest
  done
  echo "$got"
}
named() { ipc backZone | jq -r '[.hits[].name] | join(",")'; }
# The resting notch of this notch: compactWidth 180 and compactHeight 32, the defaults.
rest_w=180; rest_h=32
rest
rz=$(zone clear)
check "the zone is as wide and as tall as the resting notch" "${rest_w}x${rest_h}" "$(cut -d' ' -f2 <<<"$rz")"
check "…and the panel is told the same (surfaceHost.backZoneWidth and backZoneHeight)" "ZONE ${rest_w}x${rest_h}" \
  "$(grep -a 'ZONE ' "$work/qs.log" | tail -n 1 | sed 's/.*ZONE/ZONE/')"
check "a header that starts below the zone: nothing collides" "integration ${rest_w}x${rest_h} " "$rz"
check "a control beside the zone, in the same row: nothing collides" "integration ${rest_w}x${rest_h} " "$(zone gutter)"
check "text in the zone is not a control" "integration ${rest_w}x${rest_h} " "$(zone label)"
check "an invisible control in the zone is not a collision" "integration ${rest_w}x${rest_h} " "$(zone hidden)"
check "a panel-sized backdrop under everything is the panel's surface, not a collision" "integration ${rest_w}x${rest_h} " "$(zone backdrop)"
check "a button in the zone is found (its MouseArea too)" "integration ${rest_w}x${rest_h} MouseArea" "$(zone button)"
check "a bare MouseArea in the zone is found" "integration ${rest_w}x${rest_h} MouseArea" "$(zone mouse)"
check "an item with a TapHandler in the zone is found" "integration ${rest_w}x${rest_h} Item" "$(zone tap)"
zone input >/dev/null
check "a text input in the zone is found, by name" "input" "$(named)"
zone tap >/dev/null
check "…and so is the tap item" "tapItem" "$(named)"
zone button >/dev/null
check "…and the button's own MouseArea is found with it" "headerMouse" "$(named)"
harness setNotch '{"batteryPeek":false,"compactWidth":230}' >/dev/null; settle
check "the zone follows the resting width when it is changed (230)" "integration 230x${rest_h} MouseArea" "$(zone button)"
harness setNotch '{"batteryPeek":false,"compactWidth":180}' >/dev/null; settle
rest

echo; echo "${BOLD}Every page the notch draws itself keeps the zone clear${RESET}"
sc_page() { # sc_page <settings|plugins>
  if [[ $1 == plugins ]]; then ipc plugins open >/dev/null; else ipc view settings >/dev/null; fi
  settle; ipc backZone | jq -r '"\(.open) \([.hits[].type] | join(","))"'
}
sc_settings_page() { sc_page settings; }
sc_plugins_page() { sc_page plugins; }
scenario "the settings page: no control takes a press in the zone" "settings " sc_settings_page
scenario "the Plugins page: no control takes a press in the zone" "plugins " sc_plugins_page
sc_menu() { ipc menu root >/dev/null; sleep 1.5; ipc backZone | jq -r '"\(.open) \([.hits[].type] | join(","))"'; }
scenario "the menu: no control takes a press in the zone" "menu " sc_menu

echo; echo "${BOLD}One control: the notch's pages have no back button of their own${RESET}"
check "the Plugins and Setup pages no longer carry a '‹ Settings' button" "0" \
  "$(grep -c '‹ Settings\|backRequested' "$REPO/plugins/NotchPlugins.qml" "$REPO/NotchSetup.qml" | awk -F: '{s+=$2} END {print s}')"

check "no QML errors in the run" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" | head -1 | cut -c1-120)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" || echo none)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed.${RESET}"; exit 1; fi
echo "${GREEN}All $checks checks pass.${RESET}"
