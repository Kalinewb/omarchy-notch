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
    for _ in $(seq 1 14); do run=$(jq -c --argjson g "$(ipc geometry | jq -c '{bar, radii, panelBar}')" '. + [$g]' <<<"$run"); done
    ipc collapse >/dev/null
    for _ in $(seq 1 14); do run=$(jq -c --argjson g "$(ipc geometry | jq -c '{bar, radii, panelBar}')" '. + [$g]' <<<"$run"); done
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
# The bottom radius is capped to half the height, so a short notch can only
# stay round if it narrows too: a 180 px wide, 2 px tall bar has a 1 px corner
# nobody can see, which is what made a tuck end looking sharp. The drawn width
# tapers with the height (Bar.qml, tuckWidth) by exactly the amount that holds
# the corner's share of the silhouette constant, so the test is that share --
# not the radius, which was always right, but how much of the shape it is.
# Every sample should match the share the same run has at rest.
def share(x):
    w, h = x["bar"]["width"], x["bar"]["height"]
    return x["radii"]["bottomLeft"] / w if w > 0 else 0
shares = {}
for x in s:
    if x["bar"]["height"] >= 31.5 and x["b"] > 0: shares.setdefault(x["b"], share(x))
flat = [{"h": round(x["bar"]["height"], 2), "w": round(x["bar"]["width"], 2),
         "share": round(share(x), 4), "rest": round(shares[x["b"]], 4)}
        for x in s if x["bar"]["height"] >= 1 and x["b"] > 0 and x["b"] in shares
        and share(x) < shares[x["b"]] * 0.99]
# The notch draws its shape in two windows and they overlap during the handoff,
# so every number has to agree. A panel island drawn from a different width is
# literally a second notch on screen, and every other check here reads only the
# bar window's island, so none of them can see it.
twoNotches = [{"h": round(x["bar"]["height"], 2), "bar": round(x["bar"]["width"], 2),
               "panel": round(x["panelBar"]["width"], 2)}
              for x in s if "panelBar" in x
              and (abs(x["panelBar"]["width"] - x["bar"]["width"]) > 0.01
                   or abs(x["panelBar"]["height"] - x["bar"]["height"]) > 0.01
                   or abs(x["panelBar"]["bottom"] - x["radii"]["bottomLeft"]) > 0.01
                   or abs(x["panelBar"]["fillet"] - x["radii"]["fillet"]) > 0.01)]
worst = min((share(x) / shares[x["b"]] for x in s
             if x["bar"]["height"] >= 1 and x["b"] > 0 and x["b"] in shares), default=1)
heights = sorted({round(x["bar"]["height"], 1) for x in partial})
print(json.dumps({"samples": len(s), "partial": len(partial), "heights": heights[:12], "bad": bad[:5], "badCount": len(bad), "sharp": sharp, "top": top,
                  "worstShare": round(worst, 3), "flat": flat[:5], "flatCount": len(flat),
                  "twoNotches": twoNotches[:5], "twoNotchesCount": len(twoNotches)}))
PY
)
echo "  ${DIM}$(jq -c '{samples, partial, heights}' <<<"$report")${RESET}"
check "caught the notch part-way into the edge (samples with 0 < height < resting)" "true" "$(jq -r '.partial >= 3' <<<"$report")"
check "every sample: bottom = min(bottomRadius, w/2, h/2), fillet = min(filletRadius, h − bottom)" "0" "$(jq -r .badCount <<<"$report")"
[[ $(jq -r .badCount <<<"$report") != 0 ]] && jq -c '.bad' <<<"$report"
check "never sharp: bottom corners and fillets above zero whenever at least 1 px of the notch shows" "0" "$(jq -r .sharp <<<"$report")"
check "top corners square in every sample" "0" "$(jq -r .top <<<"$report")"
echo "  ${DIM}$(jq -c '{worstShare}' <<<"$report")${RESET}"
check "never a rule: the bottom corner keeps its share of the drawn width all the way in" "0" "$(jq -r .flatCount <<<"$report")"
check "one notch: the panel window's island matches the bar window's, size and radii" "0" "$(jq -r .twoNotchesCount <<<"$report")"
[[ $(jq -r .twoNotchesCount <<<"$report") != 0 ]] && jq -c '.twoNotches' <<<"$report"
[[ $(jq -r .flatCount <<<"$report") != 0 ]] && jq -c '.flat' <<<"$report"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
