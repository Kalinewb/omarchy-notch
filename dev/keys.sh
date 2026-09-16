#!/bin/bash

# Keybinds, as numbers.
#
#   ./dev/keys.sh
#
# 1. keys.js, which turns a key press in a settings record button into a
#    Hyprland combination, over a table of presses.
# 2. The auto-hide keybind in a throwaway notch: it is bound in the running
#    Hyprland with the right command, replaced when changed, and gone when
#    cleared. Uses combinations nobody binds (SUPER+ALT+CTRL+F9/F10) and
#    removes them again whatever happens.

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
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-keys.XXXXXX")
qs_pid=""
cleanup() {
  [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null
  hyprctl eval 'hl.unbind("SUPER + ALT + CTRL + F9"); hl.unbind("SUPER + ALT + CTRL + F10")' >/dev/null 2>&1
  rm -rf "$root"
}
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
cp "$REPO/dev/harness/keys-cases.qml" "$root/keys-cases.qml"

echo "${BOLD}Keybinds${RESET}  ${DIM}plugin: $REPO${RESET}"
echo; echo "${BOLD}Record button: key press → combination${RESET}"
cases=$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 20 qml6 "$root/keys-cases.qml" 2>&1 | sed -n 's/^.*KEYS //p')
get() { jq -r --arg n "$1" "select(.name == \$n) | $2" <<<"$cases"; }
for n in "SUPER + N" "SUPER + ALT + N" "F12 alone" "CTRL + RETURN" "SUPER + SPACE" "ALT + 5" "SUPER + LEFT"; do
  check "$n" "$(awk -F' alone' '{print $1}' <<<"$n")" "$(get "$n" .combo)"
done
check "modifiers always come out as SUPER, CTRL, ALT, SHIFT" "SUPER + CTRL + ALT + SHIFT + K" "$(get "order is SUPER CTRL ALT SHIFT" .combo)"
check "a plain letter is refused (it would fire while typing)" "|add SUPER, CTRL or ALT" "$(get "plain letter" '"\(.combo)|\(.reason)"')"
check "SHIFT + a letter is refused too" "|add SUPER, CTRL or ALT" "$(get "SHIFT + letter" '"\(.combo)|\(.reason)"')"
check "holding only a modifier keeps listening" "true|" "$(get "modifier held alone" '"\(.waiting)|\(.combo)"')"
check "a key with no bindable name is refused" "|that key can't be bound" "$(get "unbindable key" '"\(.combo)|\(.reason)"')"
check "Escape (which cancels recording) is Qt's Escape" "true" "$(get "escape code" .escape)"

echo; echo "${BOLD}Auto-hide keybind in the running Hyprland${RESET}"
binds() { hyprctl binds -j | jq -c '[.[] | select(.description == "Toggle notch auto-hide") | {key, modmask, arg}]'; }
ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
check "no auto-hide bind before the test" "[]" "$(binds)"

NOTCH_HARNESS_CONFIG='{"autoHideKey":"SUPER + ALT + CTRL + F9"}' quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 1.5
bound=$(binds)
keys_report=$(ipc geometry | jq -c .keys)
echo "  ${DIM}bound: $bound; notch reports $keys_report${RESET}"
check "the auto-hide keybind is bound once, to F9 with SUPER+ALT+CTRL (modmask 76)" "1 F9 76" "$(jq -r 'if length == 1 then "1 \(.[0].key) \(.[0].modmask)" else "\(length)" end' <<<"$bound")"
# Hyprland reports the action only as a function reference, so read the Lua
# the notch sent.
check "…with the action omarchy-shell -q notch autoHide toggle" "true" "$(jq -r '.lastLua | contains("hl.bind(\"SUPER + ALT + CTRL + F9\", hl.dsp.exec_cmd(\"omarchy-shell -q notch autoHide toggle\")")' <<<"$keys_report")"
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
hyprctl eval 'hl.unbind("SUPER + ALT + CTRL + F9")' >/dev/null 2>&1

NOTCH_HARNESS_CONFIG='{"autoHideKey":"SUPER + ALT + CTRL + F10"}' quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 1.5
check "a different combination binds that one instead" "F10" "$(binds | jq -r '[.[].key] | join(",")')"
autohide_before=$(ipc geometry | jq -r .autoHide.on)
state=$(ipc autoHide toggle)
check "the IPC call the bind runs (autoHide toggle) answers with the new value" "true" "$( [[ $state == "true" || $state == "unsaved" ]] && echo true || echo "$state")"
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
hyprctl eval 'hl.unbind("SUPER + ALT + CTRL + F10")' >/dev/null 2>&1
check "after cleanup no auto-hide bind is left" "[]" "$(binds)"
echo "  ${DIM}(the throwaway notch has no shell.json to save to, so autoHide toggle answers \"unsaved\" there; before: $autohide_before, answer: $state)${RESET}"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
