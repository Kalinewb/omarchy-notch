#!/bin/bash

# The Settings, Setup and Plugins pages on a fake bar, with no window on a screen.
#
#   ./dev/panels.sh
#
# dev/harness/panels/tst_panels.qml.in runs under qmltestrunner (QT_QPA_PLATFORM=
# offscreen), loading the real NotchSettings.qml, NotchSetup.qml and
# plugins/NotchPlugins.qml against FakeBar.qml, with the Omarchy shell's own
# Commons and Ui and a stand-in for Quickshell's module (dev/harness/panels/
# stubs). It checks what dev/settings.sh, setup.sh and plugins.sh cannot say
# without a display: that every button Tab can reach is focusable, that the
# controls carry Accessible metadata, that reduced motion stops every loop, and
# that Reset asks twice. Its result is one line per case.

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
RUNNER=/usr/lib/qt6/bin/qmltestrunner
work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-panels.XXXXXX")
trap 'rm -rf "$work"' EXIT

echo "${BOLD}The pages on a fake bar${RESET}  ${DIM}qmltestrunner offscreen, no display${RESET}"
[[ -x $RUNNER ]] || { check "qmltestrunner is installed" "yes" "no"; exit 1; }
mkdir -p "$work/imp" "$work/t"
ln -s "$SHELL_PATH/shell" "$work/imp/qs"
ln -s "$REPO/dev/harness/panels/stubs/Quickshell" "$work/imp/Quickshell"
sed -e "s#@REPO@#$REPO#g" "$REPO/dev/harness/panels/tst_panels.qml.in" >"$work/t/tst_panels.qml"
out=$(cd "$work/t" && env -u WAYLAND_DISPLAY QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$work}" timeout 120 "$RUNNER" -import "$work/imp" -input "$work/t" 2>&1)

ran=0
while IFS= read -r line; do
  ran=$((ran + 1))
  name=${line#*Panels::}; name=${name%%(*}; name=${name#test_}; name=${name//_/ }
  case $line in
    PASS*) check "$name" pass pass ;;
    FAIL*) check "$name" pass "FAIL: $(grep -A4 -F "$line" <<<"$out" | grep -E 'Actual|Expected|Loc|Error' | tr -s ' ' | tr '\n' ' ' | cut -c1-300)" ;;
  esac
done < <(grep -E '^(PASS|FAIL).*::test_' <<<"$out")
want=$(grep -c '^  function test_' "$REPO/dev/harness/panels/tst_panels.qml.in")
check "every case ran: $want" "$want" "$ran"
errors=$(grep -E 'TypeError|ReferenceError|is not a type|Cannot assign|unavailable' <<<"$out" | sort -u | head -3 | cut -c1-200)
check "no QML errors in the run" "" "$errors"

# Reduced motion, as source: one reader of the environment, and no loop that ignores it.
cd "$REPO"
check "reduced motion has one source: Bar.reducedMotion reads the environment, no page does" "Bar.qml" \
  "$(git ls-files '*.qml' ':!dev/**' | xargs grep -l 'env("OMARCHY_REDUCED_MOTION")' | tr '\n' ' ' | sed 's/ $//')"
check "every infinite animation runs only while motion is allowed" "" "$(python3 - <<'PY'
import re, subprocess
files = subprocess.run(["git", "ls-files", "*.qml", ":!dev/**"], capture_output=True, text=True).stdout.split()
bad = []
for f in files:
    lines = open(f).read().split("\n")
    for i, ln in enumerate(lines):
        if "Animation.Infinite" in ln:
            near = "\n".join(lines[max(0, i - 4):i + 4])
            if not re.search(r"running:.*(still|reducedMotion|dancing)", near): bad.append(f"{f}:{i + 1}")
print(" ".join(bad))
PY
)"
check "the equaliser's three callers give it Bar.reducedMotion (its dancing follows animate)" "3" "$(grep -c 'animate:.*!root.reducedMotion' Bar.qml)"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
