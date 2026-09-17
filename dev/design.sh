#!/bin/bash

# One radius (DESIGN-PHILOSOPHY.md, 5), as numbers.
#
#   ./dev/design.sh
#
# Every button, chip, field, switch, highlight, outline and card in the
# settings panel and the menu uses the notch's bottom radius, capped at half
# its height, whatever the theme's Hyprland rounding is. Runs the real Bar.qml
# in throwaway notches with several bottomRadius values, walks every item with
# a radius in the settings panel and the menu (all of them, folded sections and
# the closed uninstall dialog included) and checks each drawn one:
#
#     radius = min(bottomRadius, height / 2, width / 2)
#
# Slider parts are the one exception (DESIGN-PHILOSOPHY.md: circles stay
# circles): a slider's track, fill and knob are round, radius = height / 2.
# Hairlines (1–2 px separators) and gradient fades are not boxes and are
# skipped.

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
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-design.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
start() {
  NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_HARNESS_CONFIG="$1" quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  for _ in $(seq 1 30); do sleep 0.1; [[ $(ipc geometry | jq -r .menu.rowsLoaded) == true ]] && break; done
  sleep 0.5
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

echo "${BOLD}One radius${RESET}  ${DIM}Hyprland rounding now: $(hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r .int)${RESET}"

for r in ${RADII:-10 8 3 16}; do
  echo; echo "${BOLD}bottomRadius $r${RESET}"
  start "{\"bottomRadius\":$r,\"batteryPeek\":false}"
  # Open both panels once so every delegate exists at its real size.
  ipc settings >/dev/null; sleep 0.9; ipc settings >/dev/null
  ipc menu root >/dev/null; sleep 1.1
  d=$(ipc design)
  ipc menu root >/dev/null
  report=$(python3 - "$d" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
r = d["radius"]
def audit(items):
    drawn = [i for i in items if i["drawn"] and i["width"] > 0 and i["height"] > 0]
    bad, round_parts = [], 0
    for i in drawn:
        if i["gradient"]:
            continue  # scroll fades, not boxes
        want = max(0, min(r, i["height"] / 2, i["width"] / 2))
        if abs(i["radius"] - want) <= 0.01:
            continue
        if "PanelSlider" in i["path"] and abs(i["radius"] - i["height"] / 2) <= 0.01:
            round_parts += 1
            continue
        if min(i["width"], i["height"]) <= 2:
            continue  # hairline rules (separators) are lines, not rounded boxes
        bad.append(f'{i["type"]} {i["width"]}x{i["height"]} radius {i["radius"]} (want {want:g}) at {i["path"]}')
    return {"total": len(items), "drawn": len(drawn), "roundParts": round_parts, "bad": bad}
out = {"radius": r, "settings": audit(d["settings"]), "menu": audit(d["menu"]),
       "tooltipOk": abs(d["tooltip"]["radius"] - max(0, min(r, d["tooltip"]["height"] / 2))) <= 0.01}
print(json.dumps(out))
PY
)
  echo "  ${DIM}$(jq -c '{radius, settings: (.settings | {total, drawn, roundParts, bad: (.bad | length)}), menu: (.menu | {total, drawn, roundParts, bad: (.bad | length)})}' <<<"$report")${RESET}"
  jq -r '(.settings.bad[:6] + .menu.bad[:14])[] | "        \(.)"' <<<"$report"
  check "the notch's radius is bottomRadius ($r)" "$r" "$(jq -r .radius <<<"$d")"
  check "settings: every drawn rounded item has radius min($r, height / 2, width / 2)" "true 0" \
    "$(jq -r '.settings | "\(.drawn > 20) \(.bad | length)"' <<<"$report")"
  check "menu: every drawn rounded item (rows, dialog, buttons) has radius min($r, height / 2, width / 2)" "true 0" \
    "$(jq -r '.menu | "\(.drawn > 0) \(.bad | length)"' <<<"$report")"
  check "the tooltip bubble has the notch's radius" "true" "$(jq -r .tooltipOk <<<"$report")"
  stop
done

if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
