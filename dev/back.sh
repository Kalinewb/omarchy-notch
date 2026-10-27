#!/bin/bash

# The way back -- the strip at the top centre of an open panel -- as numbers.
#
#   ./dev/back.sh
#
# 1. The press itself, in a bare Qt test (qmltestrunner, offscreen): the strip
#    under a parent that handles taps like the notch's island. A press must
#    step back once and must not also reach the island's own click.
# 2. The logic, on a throwaway notch over IPC: when the strip is offered, what
#    one press does at each depth, and that the menu goes up one level before it
#    leaves. `notch back` is the call the strip makes.

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

work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-back.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

echo "${BOLD}The press on the strip${RESET}  ${DIM}BackStrip.qml, qmltestrunner offscreen${RESET}"
RUNNER=/usr/lib/qt6/bin/qmltestrunner
if [[ -x $RUNNER ]]; then
  mkdir -p "$work/t"
  sed -e "s#@REPO@#$REPO#g" "$REPO/dev/harness/back-strip/tst_back.qml.in" >"$work/t/tst_back.qml"
  out=$(cd "$work/t" && QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$work}" timeout 60 "$RUNNER" -input "$work/t" 2>&1)
  while IFS= read -r line; do
    name=${line#* : BackStrip::}; name=${name%%(*}
    case $line in
      PASS*) check "${name#test_}" pass pass ;;
      FAIL*) check "${name#test_}" pass "FAIL: $(grep -A3 -F "$line" <<<"$out" | grep -E 'Actual|Expected' | tr -s ' ' | tr '\n' ' ')" ;;
    esac
  done < <(grep -E '^(PASS|FAIL).*::test_' <<<"$out")
  check "the test ran all four cases" "4" "$(grep -cE '^(PASS|FAIL).*::test_' <<<"$out")"
else
  check "qmltestrunner is installed" "yes" "no"
fi

echo; echo "${BOLD}The way back, over IPC${RESET}"
root="$work/root"; mkdir -p "$root"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
rep() { ipc backReport | jq -r '"\(.offered) \(.depth) \(.panel) \(.menu)"'; }
settle() { sleep 0.9; }

NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' \
  quickshell -p "$root" -n >"$work/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
for _ in $(seq 1 30); do sleep 0.1; [[ $(ipc geometry | jq -r .menu.rowsLoaded) == true ]] && break; done
sleep 0.8

check "nothing open: nothing to press" "false 0 false " "$(rep)"
ipc view settings >/dev/null; settle
check "the settings, opened from rest: the strip is offered" "true 0 true " "$(rep)"
check "…one press closes them: there was nothing further back" "closed compact" "$(ipc back) $(settle; ipc geometry | jq -r .state)"
ipc view settings >/dev/null; settle
ipc view setup >/dev/null; settle
check "Setup, one step in: offered, one step behind" "true 1 true " "$(rep)"
check "…a press goes back to the settings" "back true" "$(ipc back) $(settle; ipc geometry | jq -r .settingsOpen)"
check "…and another closes, because that was the way in" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .settingsOpen)"

ipc menu root >/dev/null; settle
check "the menu at its top: offered" "true 0 true root" "$(rep)"
check "…a press closes it" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .menu.open)"
ipc menu system >/dev/null; settle
check "the menu inside a submenu" "true 0 true system" "$(rep)"
check "…a press goes up one level and leaves the menu open" "back true root" "$(ipc back) $(settle; ipc geometry | jq -r '.menu.open') $(rep | cut -d' ' -f4)"
check "…the next closes it" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .menu.open)"

ipc view settings >/dev/null; settle
ipc menu system >/dev/null; settle
check "a submenu opened from the settings: two steps to take" "true 1 true system" "$(rep)"
check "…the first goes up the menu, still on the menu" "back root 1" "$(ipc back) $(settle; rep | cut -d' ' -f4) $(rep | cut -d' ' -f2)"
check "…the second goes back to the settings" "back true" "$(ipc back) $(settle; ipc geometry | jq -r .settingsOpen)"
ipc collapse >/dev/null; settle

check "no QML errors in the run" "none" "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" || echo none)"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
