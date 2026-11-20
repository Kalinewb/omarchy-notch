#!/bin/bash

# A notch that is shown stays shown when what was opened from it is closed.
#
#   ./dev/keepshown.sh
#
# The report: with the notch shown -- always (auto-hide off), or opened with the open key and so
# shown until that key says otherwise, or kept open (stayOpen) -- opening an app or a panel from it and
# closing that put the notch back into its resting state, and with auto-hide on, into the screen edge.
# The cause was the six handlers that run when a panel goes down (settings, menu, Plugins, Setup, an
# integration, a hosted panel): each cleared the key's open state along with the pointer's and the
# click's, so the notch was no longer open, and (Bar.qml `panelClosed`) a notch the key opened is now put
# back on the view it was opened on. The pointer's and a click's way of opening end with the panel, as
# before, and so does the open key's own toggle.
#
#   A. shown always (auto-hide off): a panel, the menu, a picker hosted in the notch and the quiet cycle
#      never take it away; it is never seen hidden.
#   B. opened with the open key, auto-hide on: the same panels, closed by Back, by the picker's own Esc,
#      by hide and by the key, leave it open on its view; the key closes it; quiet puts it back.
#   C. kept open (stayOpen): the same.
#   D. the ordinary auto-hide notch is unchanged: from rest a panel closes into the edge, the pointer's
#      hover view is gone with the panel, and an explicit collapse still collapses.
#
# Real Bar.qml in a throwaway notch with the real emoji picker behind the overlay companion's go-between
# (held down: its window never maps). Nothing live is touched.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}
settle() { # settle <want> <command...>
  local want=$1; shift
  local got="" deadline=$((SECONDS + ${SETTLE_SECONDS:-8}))
  while :; do
    got=$("$@" 2>/dev/null)
    [[ $got == "$want" ]] && break
    (( SECONDS >= deadline )) && break
    sleep 0.05
  done
  printf '%s' "$got"
}

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"

sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-keepshown.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

nroot="$sb/root"
mkdir -p "$nroot"
for dir in Commons Ui services; do ln -sfn "$SHELL_PATH/shell/$dir" "$nroot/$dir"; done
ln -sfn "$REPO" "$nroot/kalinewb.notch"
ln -sfn "$REPO/companion/kalinewb.notch-clipboard" "$nroot/kalinewb.notch-clipboard"
cp "$REPO/dev/harness/overlay-notch-shell.qml" "$nroot/shell.qml"
mkdir -p "$sb/setup-home/.config/omarchy" "$sb/setup-state" "$sb/setup-run"
echo '{"bar":{"id":"kalinewb.notch","layout":{"left":[],"center":[],"right":[]}}}' >"$sb/setup-home/.config/omarchy/shell.json"

notch() { quickshell ipc -p "$nroot" call notch "$@" 2>/dev/null; }
harness() { quickshell ipc -p "$nroot" call harness "$@" 2>/dev/null; }
notch_ready() { [[ $(notch geometry) == \{* ]] && echo yes || echo no; }

start() { # start <notch config json>
  env OMARCHY_SHELL_PATH="$SHELL_PATH/shell" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_FORCE_SETUP=1 NOTCH_SETUP_HOME="$sb/setup-home" NOTCH_SETUP_CONFIG_DIR="$sb/setup-home/.config" \
    NOTCH_SETUP_TOGGLES_DIR="$sb/setup-home/toggles" NOTCH_SETUP_STATE_DIR="$sb/setup-state" \
    NOTCH_SETUP_STATUS="$sb/setup-run/setup.json" NOTCH_SETUP_PLUGINS_STATE=true \
    NOTCH_HARNESS_CONFIG="$1" OVERLAY_CLONED_FROM=omarchy.emojis \
    quickshell -p "$nroot" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  settle yes notch_ready >/dev/null
  sleep 0.8
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

# What the notch is, as the one line a check compares: its state and its view.
shape() { notch geometry | jq -r '"\(.state) \(.view)"'; }
state() { notch geometry | jq -r '.state'; }
flags() { notch geometry | jq -r '"\(.open.key) \(.open.click) \(.open.hover)"'; }
# Whether the notch was ever seen hidden while `$@` ran and for a moment after: it is sampled every
# 40 ms, because a dip into the edge and back is the thing a final-state check cannot see.
never_hidden() { # never_hidden <command...>
  local seen=no end
  "$@" >/dev/null 2>&1
  end=$((SECONDS + 2))
  while (( SECONDS < end )); do
    [[ $(state) == hidden ]] && { seen=yes; break; }
    sleep 0.04
  done
  echo "$seen"
}
# A picker opened through the overlay companion and held in the notch, until the notch has it.
hosted_open() {
  local try
  for try in 1 2 3; do
    harness open >/dev/null
    [[ $(settle hosted bash -c "quickshell ipc -p '$nroot' call notch geometry | jq -r '.view'") == hosted ]] && return 0
    harness close >/dev/null; sleep 0.4
  done
  return 1
}
view() { notch geometry | jq -r '.view'; }

CFG_ON='{"batteryPeek":false,"hostedPanels":["omarchy.emojis"]'

# ===================================================================================
echo "${BOLD}A. Shown always (auto-hide off)${RESET}"
# ===================================================================================
start "$CFG_ON,\"autoHide\":false}"
check "at rest it is the resting notch, shown" "compact widgets" "$(shape)"
notch settings >/dev/null; settle "expanded settings" shape >/dev/null
check "a panel opened and closed with Back: the resting notch again, never hidden" "no" "$(never_hidden notch back)"
check "…and shown" "compact" "$(settle compact state)"
notch menu root >/dev/null; settle "expanded menu" shape >/dev/null
check "the menu (where an app is launched from) opened and closed: never hidden" "no" "$(never_hidden notch back)"
hosted_open
check "a picker hosted in the notch: it is in the notch" "hosted" "$(view)"
check "…and closed by its own Esc: never hidden" "no" "$(never_hidden harness dismiss)"
check "…the resting notch is back" "compact" "$(settle compact state)"
hosted_open
check "…closed by hide (the summons that toggles it): never hidden" "no" "$(never_hidden harness close)"
notch quiet on keepshown:a >/dev/null
check "quiet puts it away" "hidden" "$(settle hidden state)"
notch quiet off keepshown:a >/dev/null
check "…and quiet off puts it back" "compact" "$(settle compact state)"
notch settings >/dev/null; settle "expanded settings" shape >/dev/null
notch quiet on keepshown:a >/dev/null; settle hidden state >/dev/null
notch quiet off keepshown:a >/dev/null
check "quiet over an open panel: the panel is back" "expanded settings" "$(settle "expanded settings" shape)"
notch back >/dev/null
check "…and closing it, the resting notch" "compact" "$(settle compact state)"
stop

# ===================================================================================
echo; echo "${BOLD}B. Opened with the open key, auto-hide on${RESET}"
# ===================================================================================
start "$CFG_ON,\"autoHide\":true}"
check "at rest it is in the edge" "hidden" "$(state)"
notch toggle >/dev/null
check "the open key opens it, and the key is what holds it" "expanded widgets true false false" "$(settle "expanded widgets" shape) $(flags)"
notch settings >/dev/null; settle "expanded settings" shape >/dev/null
check "a panel opened from it and closed with Back: the notch is still open on its view" "expanded widgets" "$(notch back >/dev/null; settle "expanded widgets" shape)"
check "…held by the key still" "true" "$(flags | cut -d' ' -f1)"
notch menu root >/dev/null; settle "expanded menu" shape >/dev/null
check "the menu opened from it and closed (an app launched from it): still open, never hidden" "no" "$(never_hidden notch back)"
check "…on its view" "expanded widgets" "$(shape)"
hosted_open
check "a picker hosted in it, closed by its own Esc: still open on its view" "expanded widgets" "$(harness dismiss >/dev/null; settle "expanded widgets" shape)"
hosted_open
check "…closed by hide: the same" "expanded widgets" "$(harness close >/dev/null; settle "expanded widgets" shape)"
hosted_open
check "…closed by Back: the same, one step back to where it was opened from" "expanded widgets" "$(notch back >/dev/null; settle "expanded widgets" shape)"
notch settings >/dev/null; settle "expanded settings" shape >/dev/null
notch quiet on keepshown:b >/dev/null; settle hidden state >/dev/null
notch quiet off keepshown:b >/dev/null
check "quiet over a panel opened from it: put back" "expanded settings" "$(settle "expanded settings" shape)"
notch back >/dev/null
check "…and closing that, it is still open" "expanded widgets" "$(settle "expanded widgets" shape)"
notch toggle >/dev/null
check "the open key closes it, and it goes into the edge: the key is the way out" "hidden" "$(settle hidden state)"
notch toggle >/dev/null; settle "expanded widgets" shape >/dev/null
notch collapse >/dev/null
check "collapse closes it too" "hidden" "$(settle hidden state)"
stop

# The open key with the open action set to a panel: pressing it over that panel closes the lot.
start "$CFG_ON,\"autoHide\":true,\"openAction\":\"settings\"}"
notch toggle >/dev/null; settle "expanded settings" shape >/dev/null
notch toggle >/dev/null
check "the open key over the panel it opens closes the notch, not back to a row" "hidden" "$(settle hidden state)"
stop

# ===================================================================================
echo; echo "${BOLD}C. Kept open (stayOpen)${RESET}"
# ===================================================================================
start "$CFG_ON,\"stayOpen\":true,\"autoHide\":true}"
check "it is open" "expanded widgets" "$(shape)"
notch settings >/dev/null; settle "expanded settings" shape >/dev/null
check "a panel closed: still open, never hidden" "no" "$(never_hidden notch back)"
check "…on its view" "expanded widgets" "$(shape)"
hosted_open
check "a hosted picker closed by its Esc: the same" "expanded widgets" "$(harness dismiss >/dev/null; settle "expanded widgets" shape)"
notch quiet on keepshown:c >/dev/null; settle hidden state >/dev/null
notch quiet off keepshown:c >/dev/null
check "quiet on and off: open again" "expanded widgets" "$(settle "expanded widgets" shape)"
stop

# ===================================================================================
echo; echo "${BOLD}D. The ordinary auto-hide notch is unchanged${RESET}"
# ===================================================================================
start "$CFG_ON,\"autoHide\":true}"
check "at rest it is in the edge" "hidden" "$(state)"
notch settings >/dev/null; settle "expanded settings" shape >/dev/null
check "a panel opened from rest and closed: back into the edge" "hidden" "$(notch back >/dev/null; settle hidden state)"
check "…nothing left open" "false false false" "$(flags)"
hosted_open
check "a picker hosted from rest, closed: back into the edge" "hidden" "$(harness dismiss >/dev/null; settle hidden state)"
notch view widgets >/dev/null
check "the pointer's hover view opens it" "expanded true" "$(settle expanded state >/dev/null; echo "expanded $(notch geometry | jq -r '.open.hover')")"
notch settings >/dev/null; settle "expanded settings" shape >/dev/null
notch back >/dev/null
check "a panel opened from the hover view and closed: the hover view goes with it (the pointer's, as before)" "false false false" "$(settle "false false false" flags)"
stop
start "$CFG_ON,\"autoHide\":false}"
check "auto-hide off, at rest: shown, as ever" "compact widgets" "$(shape)"
notch expand >/dev/null; settle "expanded widgets" shape >/dev/null
notch collapse >/dev/null
check "…collapse still collapses it to the resting notch" "compact" "$(settle compact state)"
stop

check "no QML errors in any of it" "0" \
  "$(grep -ci 'TypeError\|ReferenceError\|binding loop' "$sb/qs.log" || true)"

echo
if (( failures )); then echo "${RED}${failures} of ${checks} checks failed${RESET}"; exit 1; fi
echo "${GREEN}All ${checks} checks pass${RESET}"
