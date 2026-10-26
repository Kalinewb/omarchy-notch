#!/bin/bash

# The one place the notch starts a job that has to outlive it, as numbers.
#
#   ./dev/detached.sh
#
# 1. Detached.qml is the only runtime file that builds a systemd-run command,
#    and every job the notch detaches (its update, the plugin jobs, Setup's
#    fixes, the three companions) goes through its launch().
# 2. What it builds, run in a throwaway shell: a transient user unit with the
#    base environment and the job's own variables when they are set, or a plain
#    detached child when the job's mode variable says setsid.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

echo "${BOLD}Detached.qml${RESET}"
cd "$REPO" || exit 1
# Code, not comments: a line whose first non-blank characters aren't //.
sites=$(git ls-files '*.qml' '*.js' 'bin/*' 'install.sh' | grep -v '^dev/' | xargs grep -nE 'systemd-run' | grep -vE ':[0-9]+:\s*(//|#)' | cut -d: -f1 | sort -u | tr '\n' ' ')
check "1. only Detached.qml builds a systemd-run command" "Detached.qml " "$sites"
launchers=$(grep -lE 'detached\.launch\(' Bar.qml Companion.qml SetupService.qml | tr '\n' ' ')
check "2. the notch's update and plugin jobs, the companions and Setup all launch through it" "Bar.qml Companion.qml SetupService.qml " "$launchers"
check "3. Bar.qml names two units (update, plugins), each prefix once" "kalinewb-notch-plugins kalinewb-notch-update" \
  "$(grep -oE 'detached\.launch\("[a-z-]+"' Bar.qml | sed 's/.*("//; s/"//' | sort | tr '\n' ' ' | sed 's/ $//')"

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-detached.XXXXXX")
trap 'rm -rf "$root"' EXIT
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/detached-shell.qml" "$root/shell.qml"
argv() { # argv [env...]: Detached.argv's answer, as one line
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 HOME=/home/x PATH="$PATH" "$@" timeout 10 quickshell -p "$root" -n >"$root/out" 2>&1 </dev/null
  sed -n 's/^.*ARGV //p' "$root/out" | head -n 1
}
a=$(argv NOTCH_TEST_ONE=one)
check "4. a transient unit, named by its prefix and a timestamp" "systemd-run --user --collect --quiet true" \
  "$(jq -r '"\(.[0]) \(.[1]) \(.[2]) \(.[3]) \(.[4] == "--unit" and (.[5] | test("^unit-prefix-[0-9]+$")))"' <<<"$a")"
check "5. the job's own variable is handed on when set, and one that isn't is not" "true false" \
  "$(jq -r 'map(select(startswith("--setenv="))) as $e | "\($e | index("--setenv=NOTCH_TEST_ONE=one") != null) \($e | any(test("NOTCH_TEST_UNSET")))"' <<<"$a")"
check "6. the base environment goes along (HOME, PATH)" "true true" \
  "$(jq -r 'map(select(startswith("--setenv="))) as $e | "\($e | index("--setenv=HOME=/home/x") != null) \($e | any(test("^--setenv=PATH=")))"' <<<"$a")"
check "7. the job itself comes last, as given" '["job","run"]' "$(jq -c '.[-2:]' <<<"$a")"
check "8. the mode variable at setsid: a plain detached child, no unit" '["setsid","-f","job","run"]' "$(jq -c . <<<"$(argv NOTCH_TEST_DETACH=setsid)")"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"; else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
