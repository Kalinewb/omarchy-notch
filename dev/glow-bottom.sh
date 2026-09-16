#!/bin/bash

# The subtle "bottom" charging glow, and a glow size of 0, as numbers.
#
#   ./dev/glow-bottom.sh
#
# 1. From the real Bar.qml in throwaway Quickshell instances (a few seconds on
#    screen each), with a simulated charger: the default style draws only the
#    outline glow; glowStyle "bottom" draws only the bottom glow, faded in the
#    same way; glowScale 0 draws neither. Plus the bottom glow's reported
#    alpha at the edge in the middle, halfway out, and near the side.
# 2. BottomGlow.qml behind Island.qml rendered offscreen (OpenGL RHI), checked
#    pixel by pixel by dev/bottomglow_pixels.py against
#        strength / 0.35 × curve(d) × cos²(π u / 2)
#    with each pixel's distance to the bar's outline measured by brute force.
#
# dev/glow.sh covers the outline glow and is not touched by this.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0

check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

for tool in quickshell qml6 magick python3 jq; do
  command -v "$tool" >/dev/null || { echo "glow-bottom: $tool is not installed" >&2; exit 1; }
done

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-glow-bottom.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
cp "$REPO/dev/harness/bottomglow-pixels.qml" "$root/bottomglow-pixels.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }

# run_with <config json> -> the glow report after a simulated charger has been
# in for 1.5 s
run_with() {
  NOTCH_HARNESS_CONFIG="$1" quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  sleep 0.8
  ipc simulateBattery discharging 50 >/dev/null; sleep 1
  ipc simulateBattery charging 64 >/dev/null; sleep 1.5
  ipc geometry | jq -c '.glow | {mode, presence, style: .curve.style, scale: .curve.scale, size: .curve.size, outlineDrawn: .curve.outlineDrawn, bottomDrawn: .curve.bottomDrawn, bottom: .curve.bottom}'
  kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
  if grep -qE '\.qml:[0-9]+|ReferenceError|TypeError|Cannot assign|Unable to assign' "$root/qs.log"; then
    echo "QML: $(grep -E '\.qml:[0-9]+|ReferenceError|TypeError' "$root/qs.log" | head -1)" >&2
  fi
}

echo "${BOLD}Bottom glow and glow size 0${RESET}  ${DIM}plugin: $REPO${RESET}"
echo

outline=$(run_with '{}')
bottom=$(run_with '{"glowStyle":"bottom"}')
zero_outline=$(run_with '{"glowScale":0}')
zero_bottom=$(run_with '{"glowStyle":"bottom","glowScale":0}')

echo "  ${DIM}default:            $(jq -c '{style, scale, presence, outlineDrawn, bottomDrawn}' <<<"$outline")${RESET}"
echo "  ${DIM}glowStyle bottom:   $(jq -c '{style, scale, presence, outlineDrawn, bottomDrawn}' <<<"$bottom")${RESET}"
echo "  ${DIM}glowScale 0:        $(jq -c '{style, scale, presence, outlineDrawn, bottomDrawn}' <<<"$zero_outline")${RESET}"
echo "  ${DIM}bottom, glowScale 0: $(jq -c '{style, scale, presence, outlineDrawn, bottomDrawn}' <<<"$zero_bottom")${RESET}"
echo "  ${DIM}bottom glow, reported: strength $(jq -r .bottom.strength <<<"$bottom"), reach $(jq -r .bottom.reach <<<"$bottom") px; $(jq -r '[.bottom.alphaAt[] | "α(d \(.d), u \(.u)) = \(.alpha)"] | join(",  ")' <<<"$bottom")${RESET}"
echo

check "by default only the outline glow is drawn" "outline true false" "$(jq -r '"\(.style) \(.outlineDrawn) \(.bottomDrawn)"' <<<"$outline")"
check "with glowStyle bottom only the bottom glow is drawn" "bottom false true" "$(jq -r '"\(.style) \(.outlineDrawn) \(.bottomDrawn)"' <<<"$bottom")"
check "…faded in fully, charging, the same as the outline glow" "charging 1" "$(jq -r '"\(.mode) \(.presence)"' <<<"$bottom")"
check "…with the same reach as the outline glow would have" "$(jq -r .size <<<"$outline")" "$(jq -r .bottom.reach <<<"$bottom")"
check "the slider's range goes down to 0, and glowScale 0 is kept as 0" "0" "$(jq -r .scale <<<"$zero_outline")"
check "at glowScale 0 no glow is drawn (outline style)" "false false" "$(jq -r '"\(.outlineDrawn) \(.bottomDrawn)"' <<<"$zero_outline")"
check "at glowScale 0 no glow is drawn (bottom style)" "false false" "$(jq -r '"\(.outlineDrawn) \(.bottomDrawn)"' <<<"$zero_bottom")"
check "bottom glow at the edge, in the middle: α 0.24" "0.24" "$(jq -r '.bottom.alphaAt[] | select(.d == 0 and .u == 0) | .alpha' <<<"$bottom")"
check "…halfway to the side: α 0.12 (cos² 45° = ½)" "0.12" "$(jq -r '.bottom.alphaAt[] | select(.d == 0 and .u == 0.5) | .alpha' <<<"$bottom")"
check "…near the side (u 0.9): under 0.01" "true" "$(jq -r '[.bottom.alphaAt[] | select(.d == 0 and .u == 0.9) | .alpha < 0.01] | .[0]' <<<"$bottom")"
check "…and 0 at its reach" "0" "$(jq -r '[.bottom.alphaAt[] | select(.u == 0)] | last | .alpha' <<<"$bottom")"
check "the bottom glow is subtler than the outline glow (0.24 vs 0.35 at its brightest)" "true" "$(jq -r '.bottom.strength < 0.35' <<<"$bottom")"

# ---------------------------------------------------------------------------
# Green above a charge level (greenAbove)
# ---------------------------------------------------------------------------

echo
NOTCH_HARNESS_CONFIG='{"greenAbove":75}' quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 0.8
ipc simulateBattery charging 70 >/dev/null; sleep 1.5
g70=$(ipc geometry | jq -c '{percent: .battery.percent, mode: .battery.mode, looksFull: .battery.looksFull, color: .glow.color}')
ipc simulateBattery charging 75 >/dev/null; sleep 1
g75=$(ipc geometry | jq -c '{percent: .battery.percent, mode: .battery.mode, looksFull: .battery.looksFull, color: .glow.color}')
ipc simulateBattery charging 93 >/dev/null; sleep 1
g93=$(ipc geometry | jq -c '{percent: .battery.percent, mode: .battery.mode, looksFull: .battery.looksFull, color: .glow.color}')
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
echo "  ${DIM}greenAbove 75 — 70 %: $g70  75 %: $g75  93 %: $g93${RESET}"
check "greenAbove 75: charging at 70 % is still amber" "charging false #FFB340" "$(jq -r '"\(.mode) \(.looksFull) \(.color)"' <<<"$g70")"
check "…at 75 % it is green, still charging" "charging true #30D158" "$(jq -r '"\(.mode) \(.looksFull) \(.color)"' <<<"$g75")"
check "…and at 93 % green" "charging true #30D158" "$(jq -r '"\(.mode) \(.looksFull) \(.color)"' <<<"$g93")"
NOTCH_HARNESS_CONFIG='{}' quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 0.8
ipc simulateBattery charging 93 >/dev/null; sleep 1.5
gdef=$(ipc geometry | jq -c '{mode: .battery.mode, greenAbove: .battery.greenAbove, looksFull: .battery.looksFull, color: .glow.color}')
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
check "by default (greenAbove 100) charging at 93 % is amber, as before ${DIM}($gdef)${RESET}" "charging 100 false #FFB340" "$(jq -r '"\(.mode) \(.greenAbove) \(.looksFull) \(.color)"' <<<"$gdef")"

# ---------------------------------------------------------------------------
# The glow moves to the bottom of the notch when it widens
# ---------------------------------------------------------------------------

echo
# A narrow resting notch (100 px) so opening it -- to the width of the
# clock, date and battery -- always widens it well past the 24 px handover,
# whatever is or isn't playing on this machine.
NOTCH_HARNESS_CONFIG='{"openWith":["click"],"compactWidth":100,"expanded":["clock","date","media","battery"]}' quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 0.8
ipc simulateBattery charging 60 >/dev/null; sleep 1.5
snap() { ipc geometry | jq -c '{notch: {w: .bar.width, h: .bar.height, r: .radii.bottomLeft}, widen: .glow.curve.widen, outline: .glow.curve.outlineDrawn, bottom: .glow.curve.bottomDrawn, open: .glow.curve.openDrawn, openShape: .glow.curve.open, window: .glow.window.height}'; }
w_rest=$(snap)
# `view widgets` opens it without the click-outside focus grab, which a second
# Quickshell instance can lose at once (closing the notch before it is sampled).
ipc view widgets >/dev/null; sleep 1
w_open=$(snap)
ipc collapse >/dev/null; sleep 1
w_back=$(snap)
ipc settings >/dev/null; sleep 1.3
w_panel=$(snap)
ipc settings >/dev/null
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
echo "  ${DIM}at rest:        $w_rest${RESET}"
echo "  ${DIM}open (wider):   $w_open${RESET}"
echo "  ${DIM}back at rest:   $w_back${RESET}"
echo "  ${DIM}settings panel: $w_panel${RESET}"
check "at rest the resting glow is drawn, not the open-notch glow" "0 true false" "$(jq -r '"\(.widen) \(.outline) \(.open)"' <<<"$w_rest")"
check "when the notch widens the glow moves to its bottom: only the open-notch glow is drawn" "1 false false true" "$(jq -r '"\(.widen) \(.outline) \(.bottom) \(.open)"' <<<"$w_open")"
check "…following the widened notch's width and bottom radius ${DIM}($(jq -r '"\(.openShape.width)×\(.openShape.height)"' <<<"$w_open"))${RESET}" "true" \
  "$(jq -r '.openShape.width == .notch.w and .openShape.height == .notch.h and .openShape.bottomRadius == .notch.r and .notch.w >= 124' <<<"$w_open")"
check "…at full strength" "1" "$(jq -r .openShape.presence <<<"$w_open")"
check "back at rest the resting glow returns" "0 true false" "$(jq -r '"\(.widen) \(.outline) \(.open)"' <<<"$w_back")"
if jq -e '.notch.h > 100' <<<"$w_panel" >/dev/null; then
  check "grown into the settings panel, the glow follows the panel's bottom ${DIM}($(jq -r '"\(.openShape.width)×\(.openShape.height), r \(.openShape.bottomRadius)"' <<<"$w_panel"))${RESET}" "true" \
    "$(jq -r '.open and (.outline | not) and .openShape.height == .notch.h and .openShape.bottomRadius == .notch.r' <<<"$w_panel")"
else
  # A second Quickshell instance loses its focus grab at once, which closes the
  # settings panel; the live shell keeps it. Not a pass or a fail here.
  echo "  ${DIM}note  the settings panel did not stay open in this throwaway instance${RESET}"
fi
check "the glow window never resizes for any of it" "1" "$(printf '%s\n' "$w_rest" "$w_open" "$w_back" "$w_panel" | jq -s '[.[].window] | unique | length')"
check "…and leaves room for an 80 px glow below the tallest notch the settings panel can reach" "true" "$(jq -r '.window >= 548 + 88' <<<"$w_panel")"

# ---------------------------------------------------------------------------
# Pixels
# ---------------------------------------------------------------------------

render() { # render <png> <colour> <w> <h> <r> <size>
  QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qml6 "$root/bottomglow-pixels.qml" -- "w=$3" "h=$4" "r=$5" fillet=10 offset=0.5 "color=$2" presence=1 "size=$6" strength=0.24 "out=$1" 2>&1 \
    | sed -n 's/^.*GLOW barX //p'
}

for spec in "charging #FFB340 180 31.5 10 32" "full #30D158 180 31.5 10 32" "wide #FFB340 600 31.5 10 32" "largest #FFB340 180 31.5 10 80"; do
  read -r name colour W H R SIZE <<<"$spec"
  png="$root/bottom-$name.png"
  bx=$(render "$png" "$colour" "$W" "$H" "$R" "$SIZE")
  echo; echo "${BOLD}Pixels, $name ($colour)${RESET} ${DIM}${W}×${H} notch, bottom r=$R, reach $SIZE px, strength 0.24${RESET}"
  [[ -f $png && -n $bx ]] || { check "rendered" "true" "false"; continue; }
  m=$(python3 "$REPO/dev/bottomglow_pixels.py" "$png" "$bx" "$W" "$H" "$R" "$colour" "$SIZE" 0.24)
  echo "  ${DIM}across, $(jq -r .acrossRow.d <<<"$m") px below the edge (u: α): $(jq -r '.acrossRow.values | to_entries | map("\(.key): \(.value)") | join("  ")' <<<"$m")${RESET}"
  echo "  ${DIM}down the middle (px below: α): $(jq -r '.downMiddle | to_entries | map("\(.key): \(.value)") | join("  ")' <<<"$m")${RESET}"

  check "every pixel outside the notch matches the formula to within 1/255 ${DIM}($(jq -r .pixelsCompared <<<"$m") pixels, max error $(jq -r '.maxError*10000|round/10000' <<<"$m"))${RESET}" \
    "true" "$(jq -r '.maxError <= (1/255 + 0.0005)' <<<"$m")"
  check "its brightest pixel is at most 0.24 ${DIM}($(jq -r '.maxAlpha*1000|round/1000' <<<"$m"))${RESET}" "true" "$(jq -r '.maxAlpha <= (0.24 + 1/255)' <<<"$m")"
  check "only under the bottom edge: nothing beside the notch's sides" "true" "$(jq -r '.besideSidesMaxAlpha == 0 and .outsideBarWidthMaxAlpha == 0' <<<"$m")"
  check "strongest in the middle, weaker toward both edges" "true" "$(jq -r .fallsTowardEdges <<<"$m")"
  check "left and right match" "true" "$(jq -r 'if .symmetry == null then true else .symmetry <= (1/255 + 0.0005) end' <<<"$m")"
  check "nothing past its $SIZE px reach, and nothing at the drawn area's edge" "true" "$(jq -r '.beyondReachNonZero == 0 and .imageEdgeMaxAlpha == 0' <<<"$m")"
  check "pixels at α ≥ 0.15 are $colour within 8-bit rounding ${DIM}($(jq -r .colourPixels <<<"$m") px, max error $(jq -r '.colourMaxError*10000|round/10000' <<<"$m"), bound 1/(255·0.15) = $(jq -r '.colourBound*10000|round/10000' <<<"$m"))${RESET}" "true" \
    "$(jq -r 'if .colourMaxError == null then false else .colourMaxError <= .colourBound end' <<<"$m")"
  check "inside the notch: pure black" "true" "$(jq -r '.insideNotch == [0,0,0,1]' <<<"$m")"
done

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
