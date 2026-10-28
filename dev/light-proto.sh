#!/bin/bash

# The notification light's prototype (plan-glow.md Phase 1), as images and numbers.
#
#   ./dev/light-proto.sh            everything below, into research/light-proto/
#   ./dev/light-proto.sh tests      only the checks
#   ./dev/light-proto.sh sheets     only the contact sheet, crop, strip and GIF
#   ./dev/light-proto.sh g4         only the frame-time numbers
#
# 1. Checks: every .qsb rebuilds byte for byte from its .frag; the flow,
#    Jacobian and speed tests of notiflight.js (node); and pixel checks on the
#    cloud from shaders/notiflight.frag rendered offscreen (OpenGL RHI): a
#    second render is byte identical, added light stays in its band and is only
#    ever additive, and over four cycles at 1/60 s steps (the wrap included) it
#    does not pop and does not turn to static sparkle.
# 2. Images: shaders/notiflight.frag over a black scene with the real
#    Island.qml, by dev/harness/light-proto.qml. Contact sheet, 3x crop, a
#    12-frame strip at 1/30 s and a 3 s GIF.
# 3. G4: per-frame cost of the effect, at DPR 1.6 like this machine's screen.
#    Each run grabs the scene 400 times (render plus readback); the effect's
#    cost is that mean minus the mean with the effect hidden, three pairs.
#
# Nothing here is wired into the shell; the user judges the images.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUT=${OUT:-$REPO/research/light-proto}
WHAT=${1:-all}
failures=0; checks=0
export PATH="$PATH:/usr/lib/qt6/bin"

check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

for tool in qml6 magick python3 node qsb jq; do
  command -v "$tool" >/dev/null || { echo "light-proto: $tool is not installed" >&2; exit 1; }
done

work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-light.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$OUT"

# render <png> <scale> <args...>: one offscreen render, prints the harness's log
render() {
  local png=$1 scale=$2; shift 2
  QT_SCALE_FACTOR=$scale QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 300 qml6 "$REPO/dev/harness/light-proto.qml" -- "out=$png" "$@" 2>&1
}
SCALE=1.6   # this machine: 1800 x 1125 at scale 1.6

# ---------------------------------------------------------------------------
tests() {
  echo "${BOLD}Shaders${RESET}  ${DIM}every .qsb rebuilds byte for byte from its .frag${RESET}"
  for f in glow bottomglow mono notiflight; do
    qsb --qt6 -o "$work/$f.qsb" "$REPO/shaders/$f.frag" 2>/dev/null
    check "shaders/$f.frag.qsb is what qsb --qt6 builds" "same" "$(cmp -s "$work/$f.qsb" "$REPO/shaders/$f.frag.qsb" && echo same || echo different)"
  done

  echo; echo "${BOLD}Maths${RESET}  ${DIM}notiflight.js under node${RESET}"
  while IFS= read -r line; do
    echo "$line"
    [[ $line == *FAIL* ]] && { checks=$((checks + 1)); failures=$((failures + 1)); continue; }
    [[ $line == *"  pass  "* ]] && checks=$((checks + 1))
  done < <(node "$REPO/dev/harness/light-proto-tests.js" "$REPO")

  echo; echo "${BOLD}Pixels${RESET}  ${DIM}the cloud of the 180 x 32 notch, 4 cycles at 1/60 s, presence 1, scale 1${RESET}"
  local frames=530 cols=12 common=(style=notch w=180 h=32 palette=aurora presence=1)
  local g1 g2
  render "$work/grid.png" 1 "${common[@]}" view=1 t0=0.3 t1=$(awk -v n=$frames 'BEGIN { printf "%.5f", 0.3 + (n - 1) / 60 }') dt=0.0166666667 cols=$cols | grep -E "LIGHT (saved|size)" | sed 's/^qml: /    /'
  render "$work/grid2.png" 1 "${common[@]}" view=1 t0=0.3 t1=$(awk -v n=$frames 'BEGIN { printf "%.5f", 0.3 + (n - 1) / 60 }') dt=0.0166666667 cols=$cols >/dev/null
  check "the same render twice is byte identical (530 frames)" "same" "$(cmp -s "$work/grid.png" "$work/grid2.png" && echo same || echo different)"
  render "$work/off.png" 1 "${common[@]}" particles=0 t=2.5 >/dev/null
  render "$work/on.png" 1 "${common[@]}" particles=1 t=2.5 >/dev/null
  local tw th
  read -r tw th < <(render "$work/probe.png" 1 "${common[@]}" t=0 | sed -n 's/.*tile \([0-9.]*\)x\([0-9.]*\) dpr.*/\1 \2/p')
  local m
  m=$(python3 "$REPO/dev/harness/light_proto_pixels.py" nopop "$work/grid.png" "$work/off.png" "$work/on.png" "$tw" "$th" $cols $frames 1 180 32 10 72 2)
  echo "  ${DIM}$(jq -c 'del(.failures)' <<<"$m")${RESET}"
  check "added light is zero outside the band, and never negative" "0" "$(jq -r '.addedOutsideBand' <<<"$m")"
  check "cloud on is never darker than cloud off" "true" "$(jq -r '.additiveMinDelta >= -1' <<<"$m")"
  check "no pop: total light changes by <= 3% per frame ($(jq -r .maxFrameChange <<<"$m")), a 45 px stretch by <= 8% ($(jq -r .maxStretchChange <<<"$m"))" "true" \
    "$(jq -r '.maxFrameChange <= 0.03 and .maxStretchChange <= 0.08' <<<"$m")"
  check "no static sparkle: frame-to-frame correlation >= 0.6 (min $(jq -r .minCorrelation <<<"$m"), mean $(jq -r .meanCorrelation <<<"$m"))" "true" "$(jq -r '.minCorrelation >= 0.6' <<<"$m")"
  jq -r '.failures[]' <<<"$m" | sed 's/^/        /'
}

# ---------------------------------------------------------------------------
sheets() {
  echo "${BOLD}Images${RESET}  ${DIM}DPR $SCALE, into $OUT${RESET}"
  local ts=0.4,1.0,2.5,4.0 row=0 rows=()
  rowshot() { # rowshot <caption> <args...>
    local caption=$1; shift
    row=$((row + 1))
    render "$work/row$row.png" "$SCALE" "$@" ts=$ts cols=4 tw=800 | grep -q "saved true" || { echo "  ${RED}FAIL${RESET}  row $row did not render"; failures=$((failures + 1)); return; }
    magick "$work/row$row.png" -background black -fill '#bbbbbb' -font Adwaita-Sans -pointsize 26 -gravity northwest -splice 0x44 -annotate +10+6 "$caption    t = 0.4 / 1.0 / 2.5 / 4.0 s" "$work/row$row.png"
    rows+=("$work/row$row.png")
  }
  rowshot "Aurora, notch, toast notch 360x110, cloud on"  style=notch w=360 h=110 palette=aurora
  rowshot "Aurora, notch, toast notch 360x110, cloud off" style=notch w=360 h=110 palette=aurora particles=0
  rowshot "Aurora, notch, resting 180x32, cloud on"       style=notch w=180 h=32 palette=aurora
  rowshot "Aurora, notch, resting 180x32, cloud off"      style=notch w=180 h=32 palette=aurora particles=0
  rowshot "Aurora, top, cloud on (800 px wide screen)"    style=top w=180 h=32 palette=aurora sw=800
  rowshot "Aurora, top, cloud off"                        style=top w=180 h=32 palette=aurora sw=800 particles=0
  rowshot "Blue, notch, 360x110, cloud on"                style=notch w=360 h=110 palette=blue
  rowshot "Blue, notch, 360x110, cloud off"               style=notch w=360 h=110 palette=blue particles=0
  rowshot "White, notch, 360x110 (no cloud)"              style=notch w=360 h=110 palette=white
  magick "${rows[@]}" -append "$OUT/contact-sheet.png"
  echo "  contact-sheet.png $(magick identify -format '%wx%h' "$OUT/contact-sheet.png")"

  # a 3x look at what the pixels do: the toast notch's lower-right corner at t = 2.5 s
  render "$work/crop.png" "$SCALE" style=notch w=360 h=110 palette=aurora t=2.5 tw=692 >/dev/null
  magick "$work/crop.png" -crop 480x240+700+240 +repage -filter point -resize 300% "$OUT/crop-3x-aurora-notch-2.5s.png"
  render "$work/crop2.png" "$SCALE" style=notch w=360 h=110 palette=aurora particles=0 t=2.5 tw=692 >/dev/null
  magick "$work/crop2.png" -crop 480x240+700+240 +repage -filter point -resize 300% "$OUT/crop-3x-aurora-notch-2.5s-cloud-off.png"
  echo "  crop-3x-aurora-notch-2.5s.png (+ cloud off)"

  # 12 frames at 1/30 s from t = 2.0 s
  render "$work/strip.png" "$SCALE" style=notch w=360 h=110 palette=aurora t0=2.0 t1=2.3667 dt=0.0333333333 cols=4 tw=692 | grep -q "saved true" || { echo "  ${RED}FAIL${RESET}  strip"; failures=$((failures + 1)); }
  magick "$work/strip.png" -background black -fill '#bbbbbb' -font Adwaita-Sans -pointsize 26 -gravity northwest -splice 0x44 -annotate +10+6 "Aurora notch 360x110, 12 frames at 1/30 s from t = 2.0 s (row by row)" "$OUT/strip-12-frames.png"
  echo "  strip-12-frames.png"

  # 3 s at 30 fps, as a GIF
  local n=90
  render "$work/gif.png" "$SCALE" style=notch w=360 h=110 palette=aurora t0=0 t1=2.9667 dt=0.0333333333 cols=10 tw=692 | grep -q "saved true" || { echo "  ${RED}FAIL${RESET}  gif"; failures=$((failures + 1)); }
  local fw fh
  read -r fw fh < <(magick identify -format '%w %h' "$work/gif.png" | awk '{ printf "%d %d\n", $1 / 10, $2 / 9 }')
  magick "$work/gif.png" -crop "${fw}x${fh}" +repage "$work/gif-%02d.png"
  magick -delay 3 -loop 0 "$work/gif-"??.png -layers Optimize "$OUT/aurora-notch-3s.gif"
  echo "  aurora-notch-3s.gif $(du -h "$OUT/aurora-notch-3s.gif" | cut -f1), $n frames at 30 fps (the GIF palette is 256 colours: banding in the glow is the format's)"
}

# ---------------------------------------------------------------------------
g4() {
  echo "${BOLD}G4${RESET}  ${DIM}effect cost per frame at DPR $SCALE: mean of 400 grabs, minus the same with the effect hidden; 3 pairs${RESET}"
  local out="$OUT/g4.txt" sizes=(
    "notch 180x32 (resting)|style=notch w=180 h=32"
    "notch 360x110 (toast)|style=notch w=360 h=110"
    "top 1800 wide|style=top w=180 h=32 sw=1800"
    "full 1800x1125 (four strips)|style=full w=180 h=32 sw=1800 sh=1125"
  )
  : >"$out"
  for spec in "${sizes[@]}"; do
    local name=${spec%%|*} args=${spec#*|}
    for palette in aurora white; do
      local pa=() ha=() p
      for i in 1 2 3; do
        for hidden in 1 0; do
          p=$(render /dev/null "$SCALE" mode=gpu frames=410 hidden=$hidden palette=$palette $args | sed -n 's/.*LIGHT gpuMs mean \([0-9.]*\).*/\1/p')
          if (( hidden )); then ha+=("$p"); else pa+=("$p"); fi
        done
      done
      local line
      line=$(awk -v n="$name" -v pal="$palette" -v a="${pa[*]}" -v b="${ha[*]}" 'BEGIN {
        na = split(a, A, " "); split(b, B, " "); m = 0
        for (i = 1; i <= na; i++) { d[i] = A[i] - B[i]; m += d[i] }
        m /= na; mn = d[1]; mx = d[1]
        for (i = 1; i <= na; i++) { if (d[i] < mn) mn = d[i]; if (d[i] > mx) mx = d[i] }
        printf "%-28s %-7s %6.2f ms  (pairs %.2f .. %.2f; hidden baseline %.2f ms)", n, pal, m, mn, mx, B[1] }')
      echo "  $line"; echo "$line" >>"$out"
    done
  done
  echo "  ${DIM}written to $out${RESET}"
}

case $WHAT in
  tests) tests ;;
  sheets) sheets ;;
  g4) g4 ;;
  all) tests; echo; sheets; echo; g4 ;;
  *) echo "usage: $0 [all|tests|sheets|g4]" >&2; exit 2 ;;
esac

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
