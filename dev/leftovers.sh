#!/bin/bash

# Nothing a suite starts may outlive it.
#
#   ./dev/leftovers.sh
#
# dev/check.sh runs every suite with a private TMPDIR and, ten seconds after each,
# fails it if a process that carries that TMPDIR is still alive (then ends it, so one
# leak does not pile onto the next). The ten seconds are for the children of a killed
# test notch, such as a `notch-setup detect` mid-run, which finish on their own. That is how a test notch's `inotifywait` children, once
# about 60 of them, would show up. This suite tests the test: the finder sees a
# marked process, ignores an unmarked one, and the notch's own code starts no
# inotifywait of its own (Omarchy's shell does: PluginRegistry.qml and
# InputDevices.qml, two per shell).

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}
# shellcheck source=harness/leftovers.sh
source "$REPO/dev/harness/leftovers.sh"

dir=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-leftovers.XXXXXX")
pids=()
cleanup() { (( ${#pids[@]} )) && kill "${pids[@]}" 2>/dev/null; rm -rf "$dir"; }
trap cleanup EXIT

echo "${BOLD}Processes a suite leaves behind${RESET}"
check "nothing carries the private TMPDIR before anything starts" "" "$(leftovers "$dir")"

env TMPDIR="$dir" sleep 300 & pids+=($!); marked=$!
env TMPDIR="$dir/other" sleep 300 & pids+=($!)
sleep 0.2
check "a process started with the TMPDIR is found, by pid" "$marked" "$(leftovers "$dir" | cut -d' ' -f1)"
check "…and one started with another TMPDIR is not" "1" "$(leftovers "$dir" | wc -l)"
kill "$marked"; wait "$marked" 2>/dev/null
check "once it has ended there is nothing left to find" "" "$(leftovers "$dir")"

# check.sh's own use: a suite that leaves a process makes the run fail.
fake=$(mktemp -d "$dir/suites.XXXXXX")
mkdir -p "$fake/dev/harness" && cp "$REPO/dev/check.sh" "$fake/dev/" && cp "$REPO/dev/harness/leftovers.sh" "$fake/dev/harness/"
printf '#!/bin/bash\nexit 0\n' >"$fake/dev/lint.sh"
printf '#!/bin/bash\n(exec -a leaked-sleeper sleep 300) &\nexit 0\n' >"$fake/dev/leaky.sh"
printf '#!/bin/bash\nexit 0\n' >"$fake/dev/tidy.sh"
chmod +x "$fake"/dev/*.sh
out=$("$fake/dev/check.sh" lint leaky tidy 2>&1); rc=$?
check "check.sh fails a suite that leaves a process, and names it" "1 true" \
  "$rc $(grep -q 'failed: leaky' <<<"$out" && grep -q 'left running' <<<"$out" && echo true || echo false)"
check "…and ended it, so nothing from the run survives" "0" "$(pgrep -fc leaked-sleeper)"
check "…while a suite that leaves nothing passes" "0" "$("$fake/dev/check.sh" lint tidy >/dev/null 2>&1; echo $?)"

# Where the old leak could have come from.
check "the notch's own code starts no inotifywait" "0" \
  "$(cd "$REPO" && git ls-files bin companion '*.qml' '*.js' | xargs grep -l 'inotifywait' 2>/dev/null | wc -l)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
