#!/bin/bash

# The space windows keep clear at the top, as numbers.
#
#   ./dev/windows.sh
#
#   - windowsToTop follows autoHide unless set: {} → 32 px kept clear,
#     {"autoHide":true} → 0, {"autoHide":true,"windowsToTop":false} → 32,
#     {"windowsToTop":true} → 0
#   - the zone never changes while the notch opens, peeks, hides, reveals or
#     grows into the settings or the menu (so windows never resize)
#   - a test notch never reserves space on the real screen: Hyprland's reserved
#     area is the same before, during and after this whole run
#   - Quickshell/Hyprland probe (a 1 px window, so nothing visible moves): a
#     zone switched off right after a window is created lands in Hyprland when
#     applied zone-first as the notch does

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
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-windows.XXXXXX")
probe=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-probe.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root" "$probe"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
reserved() { hyprctl monitors -j | jq -c '[.[] | .reserved]'; }

echo "${BOLD}Space kept clear for windows${RESET}"
before=$(reserved)
declare -A EXPECT=(['{}']=32 ['{"autoHide":true}']=0 ['{"autoHide":true,"windowsToTop":false}']=32 ['{"windowsToTop":true}']=0)
during=()
for config in '{}' '{"autoHide":true}' '{"autoHide":true,"windowsToTop":false}' '{"windowsToTop":true}'; do
  echo; echo "${BOLD}$config${RESET}"
  merged=$(jq -c '. + {batteryPeek: false}' <<<"$config")
  NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_HARNESS_CONFIG="$merged" quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  sleep 0.6
  zones=()
  zone() { zones+=("$(ipc geometry | jq -r '.window.exclusiveZone')"); }
  zone
  ipc expand >/dev/null; sleep 0.5; zone
  ipc collapse >/dev/null; sleep 0.6; zone
  ipc peek >/dev/null; sleep 0.4; zone
  ipc settings >/dev/null; sleep 0.8; zone
  ipc settings >/dev/null; sleep 0.6; zone
  ipc menu root >/dev/null; sleep 0.9; zone
  ipc menu root >/dev/null; sleep 0.6; zone
  g=$(ipc geometry)
  during+=("$(reserved)")
  echo "  ${DIM}zones through rest/open/closed/peek/settings/menu: ${zones[*]}; applied: $(jq -c .window.applied <<<"$g")${RESET}"
  check "keeps ${EXPECT[$config]} px clear" "${EXPECT[$config]}" "${zones[0]}"
  check "…and the same in every state (open, peek, hide, settings, menu)" "1" "$(printf '%s\n' "${zones[@]}" | sort -u | wc -l)"
  check "a test notch reserves nothing on the real screen" "false 0" "$(jq -r '.window.applied | "\(.onScreen) \(.zone)"' <<<"$g")"
  kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
done
after=$(reserved)
echo
check "Hyprland's reserved area never changed during the run" "true" \
  "$( [[ $before == "$after" ]] && ! printf '%s\n' "${during[@]}" | grep -vqxF "$before" && echo true || echo "before $before during ${during[*]} after $after")"

echo; echo "${BOLD}Quickshell/Hyprland probe (1 px)${RESET}"
cat > "$probe/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
ShellRoot {
  PanelWindow {
    id: w
    property int want: 1
    anchors { top: true; left: true; right: true }
    implicitHeight: 2
    color: "transparent"
    WlrLayershell.namespace: "notch-windows-probe"
    WlrLayershell.layer: WlrLayer.Top
    mask: Region {}
    // The notch's order: zone first, then mode.
    function apply() { exclusiveZone = want; exclusionMode = want > 0 ? ExclusionMode.Normal : ExclusionMode.Ignore }
    Component.onCompleted: { apply(); Qt.callLater(function() { w.want = 0; w.apply() }) }
  }
  IpcHandler { target: "probe"; function ping(): string { return "ok" } }
}
QML
base=$(hyprctl monitors -j | jq -r '.[0].reserved[1]')
quickshell -p "$probe" -n >"$probe/log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 30); do sleep 0.1; quickshell ipc -p "$probe" call probe ping >/dev/null 2>&1 && break; done
sleep 0.6
now=$(hyprctl monitors -j | jq -r '.[0].reserved[1]')
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
check "a 1 px zone switched off just after creation leaves Hyprland's top reservation at $base px" "$base" "$now"

if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
