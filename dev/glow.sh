#!/bin/bash

# The charging glow, as numbers.
#
#   ./dev/glow.sh
#
# 1. Motion, from the real Bar.qml in a throwaway Quickshell instance (about
#    eight seconds on screen): simulates plugging in, a full battery, a low
#    battery and unplugging over IPC, and samples the glow with timestamps.
#    The fade-in must follow 800 ms OutCubic, then hold perfectly still; the
#    change to green must crossfade over 600 ms without the glow fading.
# 2. Pixels, from Glow.qml behind Island.qml rendered offscreen (OpenGL RHI).
#    dev/glow_pixels.py traces the notch's outline -- fillet arcs included --
#    as a dense polyline, measures every pixel's distance to it by brute force
#    (independently of the shader), and compares each pixel's alpha with the
#    curve at that distance. Plus: the exact values at 6/20/50/80 px, nothing
#    past 80 px, nothing cut off at the drawn area's edge, no step, the colour.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0

check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}
py() { python3 -c "$@"; }

for tool in quickshell qml6 magick python3 jq; do
  command -v "$tool" >/dev/null || { echo "glow: $tool is not installed" >&2; exit 1; }
done

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-glow.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
cp "$REPO/dev/harness/glow-pixels.qml" "$root/glow-pixels.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
now() { date +%s%3N; }
# sample <since-ms> -> {"t": ms since, "presence", "color", "mode", "layers"}
sample() {
  local a b g
  a=$(now); g=$(ipc geometry); b=$(now)
  jq -c --argjson t $(( (a + b) / 2 - $1 )) '{t: $t, room: .glow.roomBelowBar, state} + (.glow | {mode, color, presence, layers: [.curve.alphaAt[] | .shown]})' <<<"$g"
}

echo "${BOLD}Charging glow${RESET}  ${DIM}plugin: $REPO${RESET}"

# ---------------------------------------------------------------------------
# Motion
# ---------------------------------------------------------------------------

NOTCH_HARNESS_CONFIG=${NOTCH_HARNESS_CONFIG:-"{}"} quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 1

config=$(ipc geometry | jq -c .glow)
ipc simulateBattery discharging 50 >/dev/null; sleep 1.2
off=$(sample 0)

t0=$(now); ipc simulateBattery charging 64 >/dev/null
fade=()
for delay in 0.05 0.1 0.1 0.15 0.2 0.3; do sleep "$delay"; fade+=("$(sample "$t0")"); done
sleep 0.4
still=()
for _ in 1 2 3 4 5 6; do still+=("$(sample 0)"); sleep 0.25; done

t1=$(now); ipc simulateBattery full 100 >/dev/null
sleep 0.25; mid=$(sample "$t1")
sleep 0.75; full=$(sample "$t1")
ipc simulateBattery discharging 18 >/dev/null; sleep 1
low=$(sample 0)
t2=$(now); ipc simulateBattery discharging 50 >/dev/null
state_unplugged=$(ipc geometry | jq -r .state)
sleep 0.4; fading_out=$(sample "$t2")
sleep 0.8; gone=$(sample "$t2")
ipc expand >/dev/null; sleep 0.9
room_open=$(ipc geometry | jq -r '[.glow.roomBelowBar, .glow.window.height, .window.height] | join(" ")')
ipc simulateBattery charging 40 >/dev/null; sleep 1
room_charging=$(ipc geometry | jq -r '[.glow.roomBelowBar, .glow.window.height, .window.height] | join(" ")')
glow_open=$(ipc geometry | jq -c '{notch: .bar, glow: .glow.shape, size: .glow.curve.size}')
ipc collapse >/dev/null; sleep 0.8
glow_rest=$(ipc geometry | jq -c '{notch: .bar, glow: .glow.shape, size: .glow.curve.size}')
ipc settings >/dev/null; sleep 1.2
glow_panel=$(ipc geometry | jq -c '{notch: .bar, glow: .glow.shape, size: .glow.curve.size}')
ipc settings >/dev/null; sleep 0.8
ipc simulateBattery auto 0 >/dev/null
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""

echo
jq -r '"  curve        " + ([.curve.alphaAt[] | "α(\(.d) px) = \(.alpha)"] | join(",  ")) + "   (monotone cubic Hermite through \([.curve.knots[] | "(\(.d), \(.a))"] | join(" ")))"' <<<"$config"
jq -r '"  colours      charging \(.colours.charging), full \(.colours.full), low battery \(.colours.low)"' <<<"$config"
jq -r '"  motion       fade in \(.fadeInMs) ms \(.fadeEasing), fade out \(.fadeOutMs) ms \(.fadeEasing), colour crossfade \(.crossfadeMs) ms \(.crossfadeEasing); nothing else moves"' <<<"$config"
echo
echo "  ${DIM}fade-in samples (t ms, presence, expected 1-(1-t/800)^3):${RESET}"
for s in "${fade[@]}"; do
  jq -r '"    t=\(.t)  presence=\(.presence)  expected=\(((if .t > 800 then 0 else (1 - .t/800) end) as $u | 1 - $u*$u*$u) * 10000 | round / 10000)  colour=\(.color)"' <<<"$s"
done
echo "  ${DIM}held samples, 250 ms apart (presence / α at the knots and 10 px past the reach):${RESET} $(for s in "${still[@]}"; do jq -r '"\(.presence)/\(.layers|join(","))"' <<<"$s"; done | tr '\n' ' ')"
echo "  ${DIM}charging → full:${RESET} $(jq -r '"t=\(.t) \(.color) presence \(.presence)"' <<<"$mid"),  $(jq -r '"t=\(.t) \(.color) presence \(.presence)"' <<<"$full")"
echo

check "on battery above the threshold there is no glow" "none 0" "$(jq -r '"\(.mode) \(.presence)"' <<<"$off")"
check "plugging in turns on the amber glow (#FFB340)" "charging #FFB340" "$(jq -r '"\(.mode) \(.color)"' <<<"${fade[-1]}")"
check "the fade-in follows 800 ms OutCubic (every sample within 0.08)" "true" \
  "$(printf '%s\n' "${fade[@]}" | jq -s 'all(.[]; ((if .t > 800 then 0 else (1 - .t/800) end) as $u | (1 - $u*$u*$u) - .presence | fabs) <= 0.08)')"
check "…rising at every sample, never past 1" "true" \
  "$(printf '%s\n' "${fade[@]}" | jq -s '[.[].presence] as $p | all(range(1; $p|length); $p[.] >= $p[.-1]) and all($p[]; . <= 1)')"
check "then it is completely still: six samples over 1.5 s identical" "true" \
  "$(printf '%s\n' "${still[@]}" | jq -s '[.[] | [.presence, .layers]] | unique | length == 1')"
check "…at full presence, at the knots of the default glow (1.0 × 32 px): α 0.35, 0.18, 0.07, 0, and 0 past the reach" "[1,[0.35,0.18,0.07,0,0]]" \
  "$(jq -c '[.presence, .layers]' <<<"${still[0]}")"
check "at full charge the colour is mid-crossfade at ~250 ms" "true" \
  "$(jq -r '.color != "#FFB340" and .color != "#30D158"' <<<"$mid")"
check "…the glow does not dim during the crossfade" "1" "$(jq -r .presence <<<"$mid")"
check "…and is green (#30D158) by 1 s" "full #30D158" "$(jq -r '"\(.mode) \(.color)"' <<<"$full")"
check "a low battery glows red (#FF453A)" "low #FF453A 1" "$(jq -r '"\(.mode) \(.color) \(.presence)"' <<<"$low")"
check "unplugging above the threshold fades out, keeping its colour" "true" \
  "$(jq -r '.presence > 0 and .presence < 1 and .color == "#FF453A"' <<<"$fading_out")"
check "…and is gone by 1.2 s" "0" "$(jq -r .presence <<<"$gone")"
check "the glow's window leaves room for the largest glow (80 px) below the resting notch ${DIM}($(jq -r .room <<<"${still[0]}") px)${RESET}" "true" "$(jq -r '.room >= 88' <<<"${still[0]}")"
read -r room_o glow_h_o notch_h_o <<<"$room_open"
read -r room_c glow_h_c notch_h_c <<<"$room_charging"
check "…and below the open notch ${DIM}($room_o px)${RESET}" "true" "$(awk -v r="$room_o" 'BEGIN { print (r >= 88) ? "true" : "false" }')"
check "neither window changes height when the glow turns on ${DIM}(glow window $glow_h_o → $glow_h_c, notch window $notch_h_o → $notch_h_c)${RESET}" "$glow_h_o $notch_h_o" "$glow_h_c $notch_h_c"
check "unplugging peeks the battery (the stopped-charging animation)" "peek" "$state_unplugged"
echo "  ${DIM}glow shape at rest: $glow_rest${RESET}"
echo "  ${DIM}glow shape open:    $glow_open${RESET}"
echo "  ${DIM}glow shape, settings panel: $glow_panel${RESET}"
check "the glow keeps the resting notch's shape and size while the notch is open" "true" \
  "$(jq -n --argjson r "$glow_rest" --argjson o "$glow_open" '$r.glow == $o.glow and $r.size == $o.size')"
if jq -e '.notch.height > 40' <<<"$glow_panel" >/dev/null; then
  check "…and while it is grown into the settings panel ${DIM}(notch $(jq -r '"\(.notch.width)×\(.notch.height)"' <<<"$glow_panel"))${RESET}" "true" \
    "$(jq -n --argjson r "$glow_rest" --argjson p "$glow_panel" '$r.glow == $p.glow and $r.size == $p.size')"
else
  # A second Quickshell instance loses its focus grab at once, which closes the
  # panel; the live shell keeps it. Not a pass or a fail here.
  echo "  ${DIM}note  the settings panel did not stay open in this throwaway instance; checked live instead${RESET}"
fi
check "…whose reach is glowScale 1.0 × √(width × height) × 32/√(180×32) ${DIM}($(jq -r '"\(.glow.width)×\(.glow.height) → \(.size) px"' <<<"$glow_rest"))${RESET}" "true" \
  "$(jq -n --argjson r "$glow_rest" '(($r.glow.width * $r.glow.height | sqrt) * 32 / (180 * 32 | sqrt) - $r.size | fabs) < 0.01')"
if grep -qE '\.qml:[0-9]+|ReferenceError|TypeError|Cannot assign|Unable to assign' "$root/qs.log"; then
  check "no QML errors while running" "none" "$(grep -E '\.qml:[0-9]+|ReferenceError|TypeError' "$root/qs.log" | head -1)"
fi

# ---------------------------------------------------------------------------
# Pixels
# ---------------------------------------------------------------------------

render() { # render <png> <colour> <presence> <w> <h> <r> <size>
  QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qml6 "$root/glow-pixels.qml" -- "w=$4" "h=$5" "r=$6" fillet=10 offset=0.5 "color=$2" "presence=$3" "size=$7" "out=$1" 2>&1 \
    | sed -n 's/^.*GLOW barX //p'
}

# Heights end in .5 and the bar is offset half a pixel, so pixel centres sit at
# whole-pixel distances from the bottom edge and the probes read exactly 6, 20,
# 50 and 80 px.
for spec in "charging #FFB340 180 31.5 10 30" "full #30D158 180 31.5 10 30" "low #FF453A 180 31.5 10 30" "open #FFB340 600 31.5 10 30" "largest #FFB340 180 31.5 10 80" "smallest #FFB340 180 31.5 10 10"; do
  read -r name colour W H R SIZE <<<"$spec"
  png="$root/glow-$name.png"
  bx=$(render "$png" "$colour" 1 "$W" "$H" "$R" "$SIZE")
  echo; echo "${BOLD}Pixels, $name ($colour)${RESET} ${DIM}${W}×${H} notch, bottom r=$R, fillet r=10, glow size $SIZE px, presence 1${RESET}"
  [[ -f $png && -n $bx ]] || { check "rendered" "true" "false"; continue; }
  m=$(python3 "$REPO/dev/glow_pixels.py" "$png" "$bx" "$W" "$H" "$R" 10 "$colour" "$SIZE")

  for probe in belowBottom cornerDiagonal screenEdgeBeyondFillet; do
    echo "  ${DIM}$probe:${RESET} $(jq -r --arg p "$probe" '[.[$p][] | "knot \(.d) px (curve \(.curveAtKnot)) → pixel at \(.measuredDistance) px: α \(.alpha), curve there \(.curve)"] | join(";  ")' <<<"$m")"
  done
  echo "  ${DIM}down the middle, 1 px steps from the edge: $(jq -r '.profile[1:] | map(tostring) | join(" ")' <<<"$m" | cut -c1-400)…${RESET}"

  check "every pixel outside the notch matches the curve at its exact distance to the outline, to within 1/255 ${DIM}($(jq -r '.pixelsCompared' <<<"$m") pixels, max error $(jq -r '.maxError*10000|round/10000' <<<"$m"), mean $(jq -r '.meanError*100000|round/100000' <<<"$m"))${RESET}" \
    "true" "$(jq -r '.maxError <= (1/255 + 0.0005)' <<<"$m")"
check "below the edge at the knots ($(jq -r '[.belowBottom[].d] | join(" / ")' <<<"$m") px) α matches 0.35 / 0.18 / 0.07 / 0 at the exact distance (±1/255)" "true" \
    "$(jq -r '[.belowBottom[] | ((.alpha - .curve) | fabs) <= (1/255 + 0.0005)] | all' <<<"$m")"
  check "the same around the rounded bottom corner" "true" \
    "$(jq -r '[.cornerDiagonal[] | ((.alpha - .curve) | fabs) <= 0.01] | all' <<<"$m")"
  check "no pixel further than $SIZE px from the outline has any glow" "0" "$(jq -r .nonZeroBeyondReach <<<"$m")"
  check "the glow is zero at every edge of the drawn area (nothing is cut off)" "true" "$(jq -r '.imageEdgeMaxAlpha == 0' <<<"$m")"
  # A smaller glow is the same curve over fewer pixels, so its steps are
  # proportionally larger; the limit scales with 80 / size.
  check "no step or kink: neighbouring pixels differ by at most $(awk -v s="$SIZE" 'BEGIN { printf "%.3f", (5/255) * 80 / s }'), and that difference changes by at most $(awk -v s="$SIZE" 'BEGIN { printf "%.3f", (2/255) * (80 / s) ^ 2 + 2/255 }') ${DIM}(measured $(jq -r '.maxStep*1000|round/1000' <<<"$m") / $(jq -r '.maxStepChange*1000|round/1000' <<<"$m"))${RESET}" "true" \
    "$(jq -r --argjson s "$SIZE" '.maxStep <= ((5/255) * 80 / $s + 0.0001) and .maxStepChange <= ((2/255) * (80 / $s) * (80 / $s) + 2/255 + 0.0001)' <<<"$m")"
  check "every glow pixel with α ≥ 0.3 is $colour to within 8-bit rounding ${DIM}(max channel error $(jq -r '.colourMaxError*1000|round/1000' <<<"$m"))${RESET}" "true" \
    "$(jq -r '.colourMaxError <= 0.015' <<<"$m")"
  check "inside the notch: pure black, fully opaque" "true" "$(jq -r '.insideNotch == [0,0,0,1]' <<<"$m")"
done

png="$root/glow-off.png"
bx=$(render "$png" "#FFB340" 0 180 31.5 10 30)
echo; echo "${BOLD}Pixels, glow off${RESET} ${DIM}(presence 0)${RESET}"
if [[ -f $png ]]; then
  m=$(python3 "$REPO/dev/glow_pixels.py" "$png" "$bx" 180 31.5 10 10 "#FFB340" 30)
  check "nothing outside the notch" "true" "$(jq -r '(.profile[1:] | max) == 0' <<<"$m")"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
