#!/bin/bash

# The notch stays rounded while it moves, as numbers.
#
#   ./dev/motion.sh
#
# While the notch hides into the edge (auto-hide) and comes back, its height
# passes through every value between the resting height and zero. At every
# sample the corners must be what fits, never sharp:
#   bottom radius = min(bottomRadius, width / 2, height / 2)
#   fillet radius = min(filletRadius, height − bottom radius)
# and both stay above zero while any of the notch shows. Top corners stay
# square (fused to the edge, never a pill).

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
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-motion.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }

echo "${BOLD}Rounded while moving${RESET}"
samples="[]"
for r in "8 10" "10 10" "4 12"; do
  set -- $r
  NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_HARNESS_CONFIG="{\"autoHide\":true,\"bottomRadius\":$1,\"filletRadius\":$2,\"batteryPeek\":false,\"collapseDelay\":0}" \
    quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  sleep 0.8
  run="[]"
  for round in 1 2 3; do
    ipc expand >/dev/null
    for _ in $(seq 1 14); do run=$(jq -c --argjson g "$(ipc geometry | jq -c '{bar, radii}')" '. + [$g]' <<<"$run"); done
    ipc collapse >/dev/null
    for _ in $(seq 1 14); do run=$(jq -c --argjson g "$(ipc geometry | jq -c '{bar, radii}')" '. + [$g]' <<<"$run"); done
  done
  kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
  samples=$(jq -c --argjson run "$run" --argjson b "$1" --argjson f "$2" '. + [$run[] | . + {b: $b, f: $f}]' <<<"$samples")
done

report=$(python3 - "$samples" <<'PY'
import json, sys
s = json.loads(sys.argv[1])
moving = [x for x in s if 0 < x["bar"]["height"] and (x["bar"]["height"] < 31.5 or x["bar"]["width"] != 180)]
partial = [x for x in s if 0 < x["bar"]["height"] < 31.5]
bad, sharp, top = [], 0, 0
for x in s:
    h, w = x["bar"]["height"], x["bar"]["width"]
    if h <= 0: continue
    rb = max(0, min(x["b"], w / 2, h / 2))
    rf = max(0, min(x["f"], h - rb))
    r = x["radii"]
    if abs(r["bottomLeft"] - rb) > 0.01 or abs(r["bottomRight"] - rb) > 0.01 or abs(r["fillet"] - rf) > 0.01:
        bad.append({"h": h, "w": w, "bottom": r["bottomLeft"], "want": rb, "fillet": r["fillet"], "wantFillet": rf})
    if h >= 1 and (r["bottomLeft"] <= 0 or r["fillet"] <= 0): sharp += 1
    if r["topLeft"] != 0 or r["topRight"] != 0: top += 1
heights = sorted({round(x["bar"]["height"], 1) for x in partial})
print(json.dumps({"samples": len(s), "partial": len(partial), "heights": heights[:12], "bad": bad[:5], "badCount": len(bad), "sharp": sharp, "top": top}))
PY
)
echo "  ${DIM}$(jq -c '{samples, partial, heights}' <<<"$report")${RESET}"
check "caught the notch part-way into the edge (samples with 0 < height < resting)" "true" "$(jq -r '.partial >= 3' <<<"$report")"
check "every sample: bottom = min(bottomRadius, w/2, h/2), fillet = min(filletRadius, h − bottom)" "0" "$(jq -r .badCount <<<"$report")"
[[ $(jq -r .badCount <<<"$report") != 0 ]] && jq -c '.bad' <<<"$report"
check "never sharp: bottom corners and fillets above zero whenever at least 1 px of the notch shows" "0" "$(jq -r .sharp <<<"$report")"
check "top corners square in every sample" "0" "$(jq -r .top <<<"$report")"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
