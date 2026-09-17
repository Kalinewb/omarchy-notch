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
  # The battery peek depends on the machine's charging state at the moment the
  # notch starts, which would make a recorded snapshot depend on the laptop's
  # battery. Off for every case.
  local bar
  bar=$(jq -c '.notch = ((.notch // {}) + {batteryPeek: false})' <<<"$1")
  NOTCH_HARNESS=1 NOTCH_HARNESS_BAR="$bar" quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
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

# ---------------------------------------------------------------------------
# The contract itself (no slots yet)
# ---------------------------------------------------------------------------

failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

echo; echo "${BOLD}Contract${RESET}"
DECLARE='{"acme.beta":{"hideable":false,"priority":"transient","groupable":false,"preferredHeight":120},"acme.gamma":{"priority":"bogus","hideable":"no","preferredHeight":-4,"closedView":"nonsense"}}'
BAR="{\"layout\":$LAYOUT,\"notch\":{\"hiddenPlugins\":[\"acme.beta\",\"acme.delta\"],\"compact\":[\"clock\",\"battery\"],\"hoverItems\":[\"media\"]}}"
NOTCH_HARNESS=1 NOTCH_HARNESS_BAR="$BAR" NOTCH_HARNESS_DECLARE="$DECLARE" quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc contract) == \{* ]] && break; done
sleep 1.5
ct=$(ipc contract)
ipc view widgets >/dev/null; sleep 0.9
sn=$(ipc snapshot)
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
p() { jq -c --arg id "$1" '.plugins[] | select(.id == $id)' <<<"$ct"; }

check "built-ins are registered under reserved ids, first, in order" "notch.clock notch.date notch.media notch.battery notch.settings notch.menu notch.update" \
  "$(jq -r '[.plugins[] | select(.kind == "builtin") | .id] | join(" ")' <<<"$ct")"
check "every layout widget is registered once, in layout order, by its layout id" "acme.alpha acme.beta omarchy.clock acme.gamma omarchy.spacer acme.delta acme.epsilon" \
  "$(jq -r '[.plugins[] | select(.kind == "widget") | .id] | join(" ")' <<<"$ct")"
check "short names resolve to reserved ids at read time (config keeps its format)" '["notch.clock","notch.battery"] ["notch.media"]' \
  "$(jq -c '.shortNames.compact' <<<"$ct") $(jq -c '.shortNames.hover' <<<"$ct")"
check "notch.settings is a plugin: expandedView \"settings\", hideable false" "settings false builtin" "$(p notch.settings | jq -r '"\(.expandedView) \(.hideable) \(.kind)"')"
check "…and the settings panel renders through the expanded-view host (has a size)" "true" "$(jq -r '.settingsPanel.width > 0 and .settingsPanel.height > 32' <<<"$sn")"
check "an undeclared widget gets the adapter defaults" "widget null persistent-low true true false" \
  "$(p acme.alpha | jq -r '"\(.closedView) \(.expandedView) \(.priority) \(.groupable) \(.hideable) \(.declared)"')"
check "a widget's notch property overrides the defaults field by field" "transient false false 120 true" \
  "$(p acme.beta | jq -r '"\(.priority) \(.groupable) \(.hideable) \(.preferredHeight) \(.declared)"')"
check "invalid declared values fall back to the defaults, and are reported" "persistent-low true widget 32 closedView,hideable,preferredHeight,priority" \
  "$(p acme.gamma | jq -r '"\(.priority) \(.hideable) \(.closedView) \(.preferredHeight) \(.invalid | sort_by(.) | join(","))"')" 
check "hideable: false — a widget in hiddenPlugins that declares it is not hidden" '["acme.beta","acme.delta"] ["acme.delta"]' \
  "$(jq -c '.hiddenConfigured' <<<"$ct") $(jq -c '.hiddenEffective' <<<"$ct")"
check "…so it stays in the open row, while the hideable one is left out" "true false" \
  "$(jq -r '[(.row | map(split(":")[0]) | index("acme.beta") != null), (.row | map(split(":")[0]) | index("acme.delta") != null)] | map(tostring) | join(" ")' <<<"$sn")"
check "…and the hide picker still lists it (locked, not removed)" "true" "$(jq -r '[.pickers[].value] | index("acme.beta") != null' <<<"$sn")"
if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
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
checks=$((checks + 1))
if (( n == 0 )); then
  echo "  ${GREEN}pass${RESET}  every recorded value matches the baseline exactly"
else
  echo "  ${RED}FAIL${RESET}  $n values differ from the baseline:"
  jq -r '.diffs[] | "        \(.path): baseline \(.baseline | tojson) → now \(.now | tojson)"' <<<"$report" | head -60
  failures=$((failures + 1))
fi
echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
