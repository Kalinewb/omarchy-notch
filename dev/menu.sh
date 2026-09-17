#!/bin/bash

# The Omarchy menu inside the notch, as numbers.
#
#   ./dev/menu.sh
#
# menu/NotchMenu.qml is Omarchy's menu forked to draw inside the notch. This
# runs the real Bar.qml in a throwaway notch (with the shell's services linked
# in, so the Apps menu has an app library), opens the menu over IPC, and checks
# that the notch -- not a window of its own -- becomes the menu: the notch's
# target and drawn size equal the menu card's measured size, its top edge stays
# on the screen edge with square top corners and the configured bottom radius,
# the surface is the notch's colour, the keyboard comes to the notch, and it
# all goes back to rest on close. Also: routes and aliases, precedence between
# the trigger lists, settings and menu never open together, the "menu" open
# action, the Apps provider, and the menu keybind in the running Hyprland.
#
# The menu holds the keyboard while it is open, so the test notch runs with
# NOTCH_MENU_DRY_RUN=1: a row picked by a stray key press is recorded, never run.

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
KEY="SUPER + ALT + CTRL + F8"
TAG=" [menu.sh]"

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-menu.XXXXXX")
qs_pid=""
cleanup() {
  [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null
  hyprctl eval "hl.unbind(\"$KEY\")" >/dev/null 2>&1
  rm -rf "$root"
}
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
start() { # start <notch config json> [extra env...]
  local config=$1; shift
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_HARNESS_CONFIG="$config" "$@" \
    quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  # The menu JSONC loads asynchronously; wait for its rows.
  for _ in $(seq 1 30); do sleep 0.1; [[ $(ipc geometry | jq -r .menu.rowsLoaded) == true ]] && break; done
  sleep 0.8
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }
g() { ipc geometry; }
# The IPC call toggles. Anything outside the test that clears the notch's focus
# grab (a click elsewhere) closes the menu like a real click outside would, so
# these set the state they need rather than trusting the last toggle.
is_open() { [[ $(g | jq -r .menu.open) == true ]]; }
menu_close() { is_open && ipc menu root >/dev/null && sleep 1.2; return 0; }
menu_open() { # menu_open <route> [settle seconds]
  menu_close
  ipc menu "$1" >/dev/null
  sleep "${2:-1.4}"
}
near() { # near <a> <b> [tolerance] -> true|false
  awk -v a="$1" -v b="$2" -v t="${3:-0.5}" 'BEGIN { d = a - b; if (d < 0) d = -d; print (d <= t) ? "true" : "false" }'
}

echo "${BOLD}Menu inside the notch${RESET}  ${DIM}plugin: $REPO${RESET}"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}Registered and at rest${RESET}"
start '{"batteryPeek":false}'
ct=$(ipc contract)
check "notch.menu is a built-in plugin: expandedView \"menu\", persistent, not groupable, not hideable" "builtin menu persistent false false" \
  "$(jq -r '.plugins[] | select(.id == "notch.menu") | "\(.kind) \(.expandedView) \(.priority) \(.groupable) \(.hideable)"' <<<"$ct")"
rest=$(g)
check "the menu is loaded in its host but closed, invisible and not taking input" "true false 0 false" \
  "$(jq -r '.menu | "\(.loaded) \(.open) \(.host.opacity) \(.host.enabled)"' <<<"$rest")"
check "the notch is at rest (180 × 32), keyboard not taken" "compact 180 32 none" \
  "$(jq -r '"\(.state) \(.bar.width) \(.bar.height) \(.menu.focus.keyboard)"' <<<"$rest")"
check "the menu's own app library is not loaded until the menu first opens" "false" "$(jq -r '.menu.appLibrary.present' <<<"$rest")"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}Open at the root menu${RESET}"
ipc menu root >/dev/null
sleep 1.4
o=$(g)
echo "  ${DIM}$(jq -c '{state, target, bar, card: .menu.card, rows: .menu.rows, labels: .menu.rowLabels}' <<<"$o")${RESET}"
check "opens: the notch is expanded into the menu view, the menu is open at root" "expanded menu true true root" \
  "$(jq -r '"\(.state) \(.view) \(.menu.open) \(.menu.opened) \(.menu.activeMenu)"' <<<"$o")"
check "the root menu's rows are Omarchy's (first row Apps, last System)" "true Apps System" \
  "$(jq -r '"\(.menu.rows > 5) \(.menu.rowLabels[0]) \(.menu.rowLabels[-1])"' <<<"$o")"
# Rows: n × row height + (n − 1) × spacing when they fit under the ceiling.
check "rows height = n × row + (n − 1) × spacing (all rows fit)" "true" \
  "$(jq -r '.menu | .card as $c | (.rows * $c.baseRowHeight + (.rows - 1) * $c.rowSpacing) as $h | ($h == $c.rowsHeight)' <<<"$o")"
check "card height = 2 × margin + header + spacing + rows height" "true" \
  "$(jq -r '.menu.card | (2 * .contentMargin + .headerHeight + .contentSpacing + .rowsHeight) == .height' <<<"$o")"
check "the notch's target is the card: width = max(rest width, card width), height = card height" "true" \
  "$(jq -r '.target.width == ([180, .menu.card.width] | max) and .target.height == .menu.card.height' <<<"$o")"
check "…and the drawn notch has arrived there (±0.5 px)" "true true" \
  "$(near "$(jq -r .bar.width <<<"$o")" "$(jq -r .target.width <<<"$o")") $(near "$(jq -r .bar.height <<<"$o")" "$(jq -r .target.height <<<"$o")")"
check "the menu host is shown at the card's size" "1 true true" \
  "$(jq -r '"\(.menu.host.opacity) \(.menu.host.enabled) \(.menu.host.width == .menu.card.width and .menu.host.height == .menu.card.height)"' <<<"$o")"
check "top edge on the screen edge, centred on the screen" "0 true" \
  "$(jq -r .bar.y <<<"$o") $(near "$(jq -r '.bar.x + .bar.width / 2' <<<"$o")" "$(jq -r '.screen.width / 2' <<<"$o")")"
check "square top corners; bottom corners at the configured radius (10); fillets 10" "0 0 10 10 10" \
  "$(jq -r '.radii | "\(.topLeft) \(.topRight) \(.bottomLeft) \(.bottomRight) \(.fillet)"' <<<"$o")"
check "one surface: the menu's background is the notch colour (#000000)" "#000000 #000000" \
  "$(jq -r '.menu | "\(.background) \(.notchColor)"' <<<"$o")"
check "windows are not pushed: the reserved zone stays the resting height" "32" "$(jq -r .window.exclusiveZone <<<"$o")"
check "the window is tall enough for the card" "true" "$(jq -r '.window.height >= .menu.card.height' <<<"$o")"
check "the keyboard comes to the notch: layer on demand, compositor focus, menu keys focused" "onDemand true true" \
  "$(jq -r '.menu.focus | "\(.keyboard) \(.windowActive) \(.keys)"' <<<"$o")"
layers=$(hyprctl layers -j | jq -c --argjson pid "$qs_pid" '[.. | objects | select(has("namespace") and .pid == $pid) | .namespace] | unique')
check "no window of its own: the test notch's only layers are the bar and its glow" '["omarchy-bar","omarchy-notch-glow"]' "$layers"
check "the menu's own app library is loaded once it has opened" "true true" "$(jq -r '.menu.appLibrary | "\(.present) \(.own)"' <<<"$o")"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}Close${RESET}"
ipc menu root >/dev/null
sleep 1.4
c=$(g)
check "the same call closes it: menu closed, notch back at rest" "false false compact" \
  "$(jq -r '"\(.menu.open) \(.menu.opened) \(.state)"' <<<"$c")"
check "…at the resting size and window height, keyboard released, host hidden" "180 32 36 none 0" \
  "$(jq -r '"\(.bar.width) \(.bar.height) \(.window.height) \(.menu.focus.keyboard) \(.menu.host.opacity)"' <<<"$c")"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}Routes${RESET}"
menu_open system
s=$(g)
check "a menu id opens that submenu" "true system" "$(jq -r '"\(.menu.open) \(.menu.activeMenu)"' <<<"$s")"
check "…with its rows (Lock and Shutdown among them)" "true" "$(jq -r '.menu.rowLabels | (index("Lock") != null and index("Shutdown") != null)' <<<"$s")"
check "…and the notch follows the smaller card (height = card height)" "true" \
  "$(near "$(jq -r .bar.height <<<"$s")" "$(jq -r .menu.card.height <<<"$s")")"
menu_open power-menu
check "an alias resolves to its menu (power-menu → system)" "true system" "$(g | jq -r '"\(.menu.open) \(.menu.activeMenu)"')"
menu_open emoji 1
e=$(g)
check "an alias naming an action runs it (dry run) and the notch never opens" "omarchy-menu-emoji false false compact" \
  "$(jq -r '"\(.menu.lastAction) \(.menu.open) \(.menu.opened) \(.state)"' <<<"$e")"
menu_open style.font
f=$(g)
check "a wide menu (style.font) widens the notch to its card width" "true true" \
  "$(jq -r '.menu.card.width > 300' <<<"$f") $(near "$(jq -r .bar.width <<<"$f")" "$(jq -r .menu.card.width <<<"$f")")"
menu_open apps 0
for _ in $(seq 1 30); do sleep 0.1; (( $(g | jq -r .menu.rows) > 0 )) && break; done
sleep 0.5
a=$(g)
echo "  ${DIM}apps: $(jq -r '.menu.rows' <<<"$a") rows, first: $(jq -c '.menu.rowLabels[0:3]' <<<"$a")${RESET}"
check "Apps lists desktop applications from the app library, alphabetically" "true true" \
  "$(jq -r '.menu | "\(.rows > 0) \(.rowLabels == (.rowLabels | sort_by(ascii_downcase)))"' <<<"$a")"
check "…and folds: the rows stop under the notch's height limit" "true" \
  "$(jq -r '.menu.card | .height <= .maxHeight' <<<"$a")"
menu_close

# ---------------------------------------------------------------------------
echo; echo "${BOLD}Settings and the menu${RESET}"
ipc settings >/dev/null; sleep 0.8
check "(the settings are open first)" "true" "$(g | jq -r .settingsOpen)"
ipc menu root >/dev/null; sleep 1.2
sm=$(g)
check "opening the menu over the settings closes the settings" "false true menu" \
  "$(jq -r '"\(.settingsOpen) \(.menu.open) \(.view)"' <<<"$sm")"
ipc settings >/dev/null; sleep 1.2
ms=$(g)
check "opening the settings over the menu closes the menu" "true false false settings" \
  "$(jq -r '"\(.settingsOpen) \(.menu.open) \(.menu.opened) \(.view)"' <<<"$ms")"
ipc settings >/dev/null; sleep 1
stop

# ---------------------------------------------------------------------------
echo; echo "${BOLD}Triggers and the open action${RESET}"
start '{"menuWith":["middleClick","hover","scroll"],"openWith":["click","middleClick","rightClick"],"settingsWith":["rightClick"]}'
t=$(g)
check "menuWith drops hover and scroll, and a trigger settings claim" '["middleClick"]' "$(jq -c .menu.menuWith <<<"$t")"
check "openWith loses the triggers the menu or the settings claim" '["click"]' "$(jq -c .openWith <<<"$t")"
stop
start '{"openAction":"menu","batteryPeek":false}'
ipc expand >/dev/null; sleep 1.3
check "openAction \"menu\": opening the notch opens the menu" "menu true root expanded" \
  "$(g | jq -r '"\(.openAction) \(.menu.open) \(.menu.activeMenu) \(.state)"')"
ipc menu root >/dev/null; sleep 0.8
stop

# ---------------------------------------------------------------------------
echo; echo "${BOLD}Menu keybind in the running Hyprland${RESET}"
binds() { hyprctl binds -j | jq -c --arg d "Notch menu$TAG" '[.[] | select(.description == $d) | {key, modmask}]'; }
check "no test menu bind before the test notch starts" "[]" "$(binds)"
start "{\"menuKey\":\"$KEY\"}" NOTCH_NO_KEYBINDS=0 NOTCH_FORCE_KEYBINDS=1 NOTCH_KEYBIND_TAG="$TAG"
sleep 0.7
kr=$(g | jq -c .keys)
check "the menu keybind is bound once, to F8 with SUPER+ALT+CTRL (modmask 76)" "1 F8 76" \
  "$(binds | jq -r 'if length == 1 then "1 \(.[0].key) \(.[0].modmask)" else "\(length)" end')"
check "…running omarchy-shell -q notch menu root" "true" \
  "$(jq -r --arg k "$KEY" '.lastLua | contains("hl.bind(\"" + $k + "\", hl.dsp.exec_cmd(\"omarchy-shell -q notch menu root\")")' <<<"$kr")"
stop
hyprctl eval "hl.unbind(\"$KEY\")" >/dev/null 2>&1
check "after cleanup no test menu bind is left" "[]" "$(binds)"

if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
