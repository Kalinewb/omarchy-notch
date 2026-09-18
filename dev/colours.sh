#!/bin/bash

# Text on the notch reads, whatever the theme, as numbers.
#
#   ./dev/colours.sh
#
# The notch is black whatever the theme, so its text doesn't take theme colours:
# Apple white on a dark notch, Apple black on a light one. Runs the real Bar.qml
# in throwaway notches of several colours against the installed theme and
# checks, from the notch's own report:
#   - the contrast function against known WCAG values (21:1 black/white)
#   - text = #FFFFFF or #000000, whichever reads better on the notch colour
#     (recomputed here in Python), secondary text Apple's #EBEBF5 / #3C3C43 at 60 %
#   - a `foreground` setting still wins
#   - the accent reaches 3:1
#   - widgets, the resting glance, the settings panel and the menu all use it;
#     menu selected text reaches 4.5:1 and its selection fill is visible

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
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-colours.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
start() {
  NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_HARNESS_CONFIG="$1" quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  sleep 1
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

# The same WCAG arithmetic, independently: expected text for reported candidates.
expected_text() { # <colours json>
  python3 - "$1" <<'PY'
import json, sys
c = json.loads(sys.argv[1])
def lum(h):
    h = h.lstrip("#")
    def ch(v):
        v = int(v, 16) / 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(h[i:i + 2]) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b
def contrast(a, b):
    la, lb = lum(a), lum(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
bg = c["notch"]
print("#FFFFFF" if contrast("#FFFFFF", bg) >= contrast("#000000", bg) else "#000000")
PY
}

echo "${BOLD}Colours on the notch${RESET}  ${DIM}theme: $(readlink -f "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy/current/theme" 2>/dev/null)${RESET}"

for notch in "#000000" "#FDF6E3" "#268BD2" "#1A1B26"; do
  echo; echo "${BOLD}Notch colour $notch${RESET}"
  start "{\"color\":\"$notch\",\"batteryPeek\":false}"
  ipc settings >/dev/null; sleep 0.8
  ipc settings >/dev/null
  ipc menu root >/dev/null; sleep 0.9
  r=$(ipc geometry)
  ipc menu root >/dev/null
  c=$(jq -c .colours <<<"$r")
  echo "  ${DIM}$(jq -c '{notch, dark, text, secondary, accent, textContrast, accentContrast}' <<<"$c")${RESET}"
  if [[ $notch == "#000000" ]]; then
    check "contrast() matches WCAG: black/white 21, a colour with itself 1, #586e75 on black 3.9" "21 1 3.9" \
      "$(jq -r '.selfTest | "\(.blackWhite) \(.same) \(.slateOnBlack * 10 | round / 10)"' <<<"$c")"
    check "…and with no candidate readable, white on black and black on white" "#FFFFFF #000000" \
      "$(jq -r '.selfTest | "\(.readableFallbackOnBlack) \(.readableFallbackOnWhite)"' <<<"$c")"
  fi
  check "text is Apple white on a dark notch, black on a light one" "$(expected_text "$c")" "$(jq -r .text <<<"$c")"
  check "secondary text is Apple's secondary label at 60 %" "$([[ $(expected_text "$c") == "#FFFFFF" ]] && echo "#99EBEBF5" || echo "#993C3C43")" "$(jq -r .secondary <<<"$c")"
  check "text contrast ≥ 7 (or the best white/black can do on this colour) and accent ≥ 3" "true true" \
    "$(jq -r '"\(.textContrast >= ([7, .selfTest.bestOnNotch] | min)) \(.accentContrast >= 3)"' <<<"$c")"
  check "widgets paint in the notch with it, and so do the glance and the settings" "true" \
    "$(jq -r '.text as $t | (.widgets.barForeground == $t and .glance == $t and .settings.foreground == $t and .settings.accent == .accent and .settings.surface == .notch)' <<<"$c")"
  # A widget's own pop-out panel sits on the theme's background, not the notch's.
  check "…while the colours widgets use in their own panels stay the theme's" "true" \
    "$(jq -r '.widgets.foreground == .themeText and .widgets.background == .themeBarBackground' <<<"$c")"
  check "menu: text ≥ 7 (or best possible), selected text ≥ 4.5, selection fill visible (≥ 1.1)" "true true true" \
    "$(jq -r '.colours.selfTest.bestOnNotch as $best | .menu.colours | "\(.textContrast >= ([7, $best] | min)) \(.selectedTextContrast >= ([4.5, $best] | min)) \(.selectionContrast >= 1.1)"' <<<"$r")"
  check "menu: the cursor row is the text colour at an alpha, not a theme colour" "true" \
    "$(jq -r '.colours.text as $t | .menu.colours | (.selectedText | ascii_upcase) == $t and (.selectedBackground | ascii_upcase | .[-6:]) == ($t | .[-6:]) and (.selectedBorder | ascii_upcase | .[-6:]) == ($t | .[-6:])' <<<"$r")"
  check "tooltips are the notch's bubble: its surface, its text" "true" \
    "$(jq -r '.tooltip.background == .notch and .tooltip.text == .text' <<<"$c")"
  # The rule itself: nothing the notch paints with has a hue. Every entry is
  # #AARRGGBB; grey means the three channels agree. The one exception is
  # Apple's secondary label, #EBEBF5 / #3C3C43, which carries a whisper of blue
  # by Apple's design -- the notch's own value, not the theme's.
  check "nothing the notch paints with has a hue ($(jq -r '.palette | length' <<<"$c") colours checked; Apple's secondary label excepted)" "true" \
    "$(jq -r '[.palette[] | .[-6:] | ((.[0:2] == .[2:4] and .[2:4] == .[4:6]) or . == "EBEBF5" or . == "3C3C43")] | all' <<<"$c")"
  stop
done

echo; echo "${BOLD}A foreground setting wins${RESET}"
start '{"color":"#000000","foreground":"#FF8800","batteryPeek":false}'
c=$(ipc geometry | jq -c .colours)
check "foreground \"#FF8800\" is what the notch, its widgets and the glance paint with" "#FF8800 #FF8800 #FF8800" "$(jq -r '"\(.foreground) \(.widgets.barForeground) \(.glance)"' <<<"$c")"
stop

if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
