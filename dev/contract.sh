#!/bin/bash

# The plugin contract migration must not change what the notch shows.
#
#   ./dev/contract.sh --record   record the baseline from the current code
#   ./dev/contract.sh            compare the current code with the baseline
#
# Runs the real Bar.qml against a fake widget catalogue (every layout id is a
# plain widget whose width comes from its id: dev/harness/contract-shell.qml)
# for a set of bar configs, opens each view the notch has, and records the
# read-only `notch snapshot`: which widgets the row shows, in order, with
# widths; which glance items each place resolves to; the plugin pickers'
# choices; every resolved setting; the settings panel's size. Nothing that
# changes on its own (clock text, media, battery) is recorded.
#
# Cases:
#   user        your own ~/.config/omarchy/shell.json `bar` object, as it is
#               when recorded (baseline kept in dev/baselines/local/, which is
#               gitignored: it holds your layout and settings)
#   defaults, hidden, hover-mix, legacy-keys, open-actions   synthetic
#
# Compare mode reports every difference and the counts; it passes only when
# every recorded value matches exactly.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
MODE=${1:-compare}
BASE="$REPO/dev/baselines"
mkdir -p "$BASE/local"

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-contract.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/contract-shell.qml" "$root/shell.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }

LAYOUT='{"left":[{"id":"acme.alpha"},{"id":"acme.beta"}],"center":[{"id":"omarchy.clock"},{"id":"acme.gamma"},{"id":"omarchy.spacer"},{"id":"omarchy.spacer"}],"right":[{"id":"acme.delta"},{"id":"acme.epsilon"}]}'
declare -A CASES=(
  [defaults]="{\"layout\":$LAYOUT,\"notch\":{}}"
  [hidden]="{\"layout\":$LAYOUT,\"notch\":{\"hiddenPlugins\":[\"acme.beta\",\"acme.delta\",\"nobody.there\"],\"expanded\":[\"battery\"],\"compact\":[\"clock\",\"date\"]}}"
  [hover-mix]="{\"layout\":$LAYOUT,\"notch\":{\"openWith\":[\"click\"],\"hoverItems\":[\"clock\",\"media\"],\"hoverPlugins\":[\"acme.alpha\",\"acme.epsilon\"],\"openAction\":\"plugin\",\"openPlugin\":\"acme.gamma\"}}"
  [legacy-keys]="{\"layout\":$LAYOUT,\"notch\":{\"expandOn\":\"click\",\"hoverAction\":\"plugin\",\"hoverPlugin\":\"acme.alpha\"}}"
  [open-actions]="{\"layout\":$LAYOUT,\"notch\":{\"openAction\":\"battery\",\"openPlugin\":\"omarchy.spacer\",\"hiddenPlugins\":[\"omarchy.clock\"],\"compact\":[\"battery\"],\"expanded\":[]}}"
)
ORDER=(user defaults hidden hover-mix legacy-keys open-actions)
VIEWS=(rest widgets plugin hover clock battery)

user_bar=$(jq -c '.bar | {layout, notch}' "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json")
CASES[user]=$user_bar

# snapshot_case <bar json> -> {"<view>": snapshot, ...}
snapshot_case() {
  NOTCH_HARNESS=1 NOTCH_HARNESS_BAR="$1" quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc snapshot) == \{* ]] && break; done
  sleep 1.5
  local out="{}"
  for view in "${VIEWS[@]}"; do
    if [[ $view == rest ]]; then ipc collapse >/dev/null
    else ipc view "$view" >/dev/null; fi
    sleep 0.9
    out=$(jq -c --arg v "$view" --argjson s "$(ipc snapshot)" '. + {($v): $s}' <<<"$out")
    ipc collapse >/dev/null; sleep 0.5
  done
  if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
    out=$(jq -c --arg e "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -3)" '. + {qmlErrors: $e}' <<<"$out")
  fi
  kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
  printf '%s' "$out"
}

echo "${BOLD}Contract baseline${RESET}  ${DIM}mode: $MODE, plugin: $REPO${RESET}"
current="{}"
for c in "${ORDER[@]}"; do
  snap=$(snapshot_case "${CASES[$c]}")
  current=$(jq -c --arg c "$c" --argjson s "$snap" '. + {($c): $s}' <<<"$current")
  echo "  ${DIM}$c: $(jq -r '[to_entries[] | select(.key != "qmlErrors") | "\(.key) \(.value.row | length) widgets / \(.value.widgetsWidth) px"] | join(", ")' <<<"$snap")${RESET}"
done

synthetic=$(jq -c 'del(.user)' <<<"$current")
user=$(jq -c '{user}' <<<"$current")

if [[ $MODE == --record ]]; then
  jq -S . <<<"$synthetic" > "$BASE/synthetic.json"
  jq -S . <<<"$user" > "$BASE/local/user.json"
  jq -S '.bar | {layout, notch}' "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json" > "$BASE/local/user-shell-bar.json"
  echo
  echo "recorded $(jq '[.[] | to_entries[] | select(.key != "qmlErrors")] | length' <<<"$current") view snapshots across ${#ORDER[@]} cases"
  echo "  $BASE/synthetic.json"
  echo "  $BASE/local/user.json (and the shell.json bar object it came from)"
  errors=$(jq -r '[.[] | .qmlErrors // empty] | length' <<<"$current")
  (( errors == 0 )) || { echo "${RED}QML errors while recording:${RESET}"; jq -r '.[] | .qmlErrors // empty' <<<"$current"; exit 1; }
  exit 0
fi

[[ -f $BASE/synthetic.json && -f $BASE/local/user.json ]] || { echo "no baseline: run ./dev/contract.sh --record first" >&2; exit 1; }
if ! diff -q <(jq -S . "$BASE/local/user-shell-bar.json") <(jq -S '.bar | {layout, notch}' "${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json") >/dev/null; then
  echo "${RED}your shell.json bar config changed since the baseline was recorded; the user case compares the recorded config${RESET}"
  CASES[user]=$(jq -c . "$BASE/local/user-shell-bar.json")
  snap=$(snapshot_case "${CASES[user]}")
  current=$(jq -c --argjson s "$snap" '. + {user: $s}' <<<"$current")
  user=$(jq -c '{user}' <<<"$current")
fi

baseline=$(jq -s -c '.[0] + .[1]' "$BASE/synthetic.json" "$BASE/local/user.json")
report=$(python3 - "$baseline" "$current" <<'PY'
import json, sys
base, cur = json.loads(sys.argv[1]), json.loads(sys.argv[2])
diffs, compared = [], 0
def walk(path, a, b):
    global compared
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            walk(path + [k], a.get(k, "<missing>"), b.get(k, "<missing>"))
    elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for i, (x, y) in enumerate(zip(a, b)):
            walk(path + [str(i)], x, y)
    else:
        compared += 1
        if a != b:
            diffs.append({"path": "/".join(path), "baseline": a, "now": b})
walk([], base, cur)
print(json.dumps({"compared": compared, "diffs": diffs,
                  "cases": len(base), "views": sum(len([k for k in v if k != "qmlErrors"]) for v in base.values())}))
PY
)
n=$(jq -r '.diffs | length' <<<"$report")
echo
echo "  ${DIM}$(jq -r '"\(.cases) cases, \(.views) view snapshots, \(.compared) recorded values compared"' <<<"$report")${RESET}"
if (( n == 0 )); then
  echo "  ${GREEN}pass${RESET}  every recorded value matches the baseline exactly"
  exit 0
fi
echo "  ${RED}FAIL${RESET}  $n values differ from the baseline:"
jq -r '.diffs[] | "        \(.path): baseline \(.baseline | tojson) → now \(.now | tojson)"' <<<"$report" | head -60
exit 1
