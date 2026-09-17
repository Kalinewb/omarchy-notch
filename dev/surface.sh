#!/bin/bash

# One surface that never blinks, and the ways in and out of it, as numbers.
#
#   ./dev/surface.sh
#
# - No surface showing the notch is ever resized or recreated while the
#   settings and the menu open and close: every layer of a throwaway notch keeps
#   one size and one address, sampled from Hyprland's socket as fast as it
#   answers (dev/layer_sampler.py). Hyprland draws a resized layer's old buffer
#   stretched for 1-5 frames, which blinked like a reload.
# - The handoff between the bar window and the panel window never leaves a gap:
#   at every sample, if the bar window's shape is hidden the panel window draws.
# - The open keybind from the settings or the menu goes to the open view (or
#   just closes the panel when that panel is the open action). A key-opened
#   view doesn't arm the click-outside grab.
# - A click outside (another client's focus grab) closes the settings.
# - stayOpen keeps the open view up through collapse, the keybind and a panel,
#   and its keybind is bound in the running Hyprland.

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
KEY="SUPER + ALT + CTRL + F7"
TAG=" [surface.sh]"
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-surface.XXXXXX")
qs_pid=""; sampler_pid=""
cleanup() {
  [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null
  [[ -n $sampler_pid ]] && kill "$sampler_pid" 2>/dev/null
  hyprctl eval "hl.unbind(\"$KEY\")" >/dev/null 2>&1
  rm -rf "$root"
}
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
mkdir -p "$root/grabber" && cp "$REPO/dev/harness/grabber.qml" "$root/grabber/shell.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
start() { # start <config json> [env...]
  local config=$1; shift
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_HARNESS_CONFIG="$config" "$@" \
    quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  for _ in $(seq 1 30); do sleep 0.1; [[ $(ipc geometry | jq -r .menu.rowsLoaded) == true ]] && break; done
  sleep 0.8
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }
g() { ipc geometry; }
shape() { g | jq -c '{shape: .panel.shape, hidden: .panel.barShapeHidden, tall: .panel.tall, h: .bar.height}'; }

echo "${BOLD}One surface, never resized${RESET}"
start '{"batteryPeek":false}'
python3 "$REPO/dev/layer_sampler.py" "$qs_pid" 11 "$root/layers.txt" &
sampler_pid=$!
sleep 0.5
handoff="$root/handoff.jsonl"
sample_for() { local end=$((SECONDS + $1)); while (( SECONDS < end )); do shape >>"$handoff"; done; }
ipc settings >/dev/null; sample_for 2
ipc settings >/dev/null; sample_for 2
ipc menu root >/dev/null; sample_for 2
ipc menu root >/dev/null; sample_for 2
wait "$sampler_pid"; sampler_pid=""
report=$(python3 - "$root/layers.txt" <<'PY'
import sys, json, re
lines = open(sys.argv[1]).read().splitlines()
samples = int(re.search(r"samples (\d+)", lines[-1]).group(1)) if lines and lines[-1].startswith("samples") else 0
sizes, addresses, changes = {}, set(), 0
for line in lines:
    if line.startswith("samples"): continue
    changes += 1
    for layer in line.split(" ", 1)[1].split(" | "):
        ns, addr, geo = layer.split(" ")
        addresses.add(addr)
        sizes.setdefault(ns + " " + addr, set()).add(geo.split("@")[0])
print(json.dumps({"samples": samples, "changes": changes, "layers": len(sizes), "addresses": len(addresses),
                  "sizes": {k: sorted(v) for k, v in sizes.items()}}))
PY
)
echo "  ${DIM}$(jq -c '{samples, changes, sizes}' <<<"$report")${RESET}"
check "Hyprland was sampled densely (more than 500 samples over the run)" "true" "$(jq -r '.samples > 500' <<<"$report")"
check "three layers (bar, panel, glow), each created once: the set never changed" "3 3 1" "$(jq -r '"\(.layers) \(.addresses) \(.changes)"' <<<"$report")"
check "every layer kept one size through settings and menu open/close" "true" "$(jq -r '[.sizes[] | length == 1] | all' <<<"$report")"
check "the bar window is 36 px tall, the panel window taller" "true" \
  "$(jq -r '[.sizes | to_entries[] | select(.key | startswith("omarchy-bar")) | .value[0] | split("x")[1] | tonumber] | sort | (.[0] == 36 and .[1] > 400)' <<<"$report")"
n=$(wc -l <"$handoff")
gaps=$(jq -s '[.[] | select(.hidden and (.shape | not))] | length' "$handoff")
mid=$(jq -s '[.[] | select(.h > 40)] | length' "$handoff")
check "handoff never leaves a gap: bar shape hidden only while the panel draws ($n samples, $mid mid-growth)" "0 true" "$gaps $( (( mid > 0 )) && echo true || echo false)"
check "…and a tall notch is always drawn by the panel window" "0" "$(jq -s '[.[] | select(.h > 40 and (.shape | not))] | length' "$handoff")"
sleep 0.5
check "at rest, the bar window draws the notch again" "false false" "$(g | jq -r '"\(.panel.shape) \(.panel.barShapeHidden)"')"

echo; echo "${BOLD}The open keybind from a panel${RESET}"
ipc settings >/dev/null; sleep 0.9
ipc toggle >/dev/null; sleep 0.9
k=$(g)
check "from the settings: widgets open, settings closed" "expanded widgets false" "$(jq -r '"\(.state) \(.view) \(.settingsOpen)"' <<<"$k")"
check "…opened by key, so no click-outside grab is armed" "true false" "$(jq -r '"\(.open.key) \(.open.click)"' <<<"$k")"
ipc toggle >/dev/null; sleep 0.8
check "the keybind again closes it" "compact false" "$(g | jq -r '"\(.state) \(.open.key)"')"
ipc menu root >/dev/null; sleep 1.0
ipc toggle >/dev/null; sleep 0.9
check "from the menu: widgets open, menu closed" "expanded widgets false false" "$(g | jq -r '"\(.state) \(.view) \(.menu.open) \(.menu.opened)"')"
ipc collapse >/dev/null; sleep 0.8
stop

start '{"batteryPeek":false,"openAction":"settings"}'
ipc settings >/dev/null; sleep 0.9
ipc toggle >/dev/null; sleep 0.9
check "when the open action is the settings, the keybind from the settings just closes them" "compact false" "$(g | jq -r '"\(.state) \(.settingsOpen)"')"

echo; echo "${BOLD}A click outside closes the settings${RESET}"
ipc settings >/dev/null; sleep 1.0
before=$(g | jq -r .settingsOpen)
timeout 5 quickshell -p "$root/grabber" -n >"$root/grabber.log" 2>&1
sleep 0.6
check "another client's focus grab (a click outside) closes them" "true false" "$before $(g | jq -r .settingsOpen)"
stop

echo; echo "${BOLD}Keep the notch open${RESET}"
start '{"batteryPeek":false,"stayOpen":true,"openAction":"clock"}'
check "stayOpen: open at rest on the open view" "expanded clock true" "$(g | jq -r '"\(.state) \(.view) \(.open.pinned)"')"
ipc collapse >/dev/null; sleep 0.8
check "…collapse doesn't close it" "expanded clock" "$(g | jq -r '"\(.state) \(.view)"')"
ipc toggle >/dev/null; sleep 0.8
check "…nor does the open keybind" "expanded clock" "$(g | jq -r '"\(.state) \(.view)"')"
ipc settings >/dev/null; sleep 0.9
over=$(g | jq -r '"\(.view) \(.settingsOpen)"')
# A test notch can lose its focus grab (which closes the settings) on its own;
# close them only if they are still open.
[[ $(g | jq -r .settingsOpen) == true ]] && ipc settings >/dev/null
sleep 1.0
check "…the settings open over it, and it comes back when they close" "settings true expanded clock" "$over $(g | jq -r '"\(.state) \(.view)"')"
stop
start '{"batteryPeek":false,"stayOpen":true,"openAction":"menu"}'
check "when the open action is a panel, it keeps the widgets open" "expanded widgets false" "$(g | jq -r '"\(.state) \(.view) \(.menu.open)"')"
stop

echo; echo "${BOLD}Keep-open keybind in the running Hyprland${RESET}"
binds() { hyprctl binds -j | jq -c --arg d "Keep the notch open$TAG" '[.[] | select(.description == $d) | {key, modmask}]'; }
check "no test bind before the test notch starts" "[]" "$(binds)"
start "{\"batteryPeek\":false,\"stayOpenKey\":\"$KEY\"}" NOTCH_NO_KEYBINDS=0 NOTCH_FORCE_KEYBINDS=1 NOTCH_KEYBIND_TAG="$TAG"
sleep 0.7
check "bound once, to F7 with SUPER+ALT+CTRL (modmask 76)" "1 F7 76" "$(binds | jq -r 'if length == 1 then "1 \(.[0].key) \(.[0].modmask)" else "\(length)" end')"
check "…running omarchy-shell -q notch stayOpen toggle" "true" \
  "$(g | jq -r --arg k "$KEY" '.keys.lastLua | contains("hl.bind(\"" + $k + "\", hl.dsp.exec_cmd(\"omarchy-shell -q notch stayOpen toggle\")")')"
check "the IPC call the bind runs answers (unsaved in a test notch)" "unsaved" "$(ipc stayOpen toggle)"
stop
hyprctl eval "hl.unbind(\"$KEY\")" >/dev/null 2>&1
check "after cleanup no test bind is left" "[]" "$(binds)"

if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
