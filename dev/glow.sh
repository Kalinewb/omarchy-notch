#!/bin/bash

# The battery glow, as numbers.
#
#   ./dev/glow.sh
#
# 1. Runs the real Bar.qml in a throwaway Quickshell instance (about ten seconds
#    on screen), simulates each battery state over IPC and reads back the glow's
#    mode, colour, intensity, spread and timing -- including the surge sampled
#    while it plays after a simulated plug-in.
# 2. Renders Glow.qml behind Island.qml offscreen (OpenGL RHI; the software
#    renderer cannot blur) in each colour, and samples the halo: the bar stays
#    pitch black, the mist has the right hue, fades with distance, is
#    symmetric, follows the fillets along the screen edge, and is gone at
#    intensity 0.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0

check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}
yes_no() { if eval "$1"; then echo true; else echo false; fi; }

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
glow() { ipc geometry | jq -c '.glow + {battery: .battery.mode, percent: .battery.percent}'; }

echo "${BOLD}Battery glow${RESET}  ${DIM}plugin: $REPO${RESET}"

# ---------------------------------------------------------------------------
# The numbers, from the running bar
# ---------------------------------------------------------------------------

NOTCH_HARNESS_CONFIG=${NOTCH_HARNESS_CONFIG:-"{}"} quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 1

ipc simulateBattery discharging 50 >/dev/null; sleep 1.2
idle=$(glow)
ipc simulateBattery charging 64 >/dev/null
sleep 0.28; surge_peak=$(glow)
sleep 2.2;  charging=$(glow)
charging_samples=()
for _ in $(seq 1 8); do sleep 0.2; charging_samples+=("$(ipc geometry | jq '.glow.intensity')"); done
ipc simulateBattery full 100 >/dev/null; sleep 1.2
full=$(glow)
ipc simulateBattery discharging 18 >/dev/null; sleep 1.2
low=$(glow)
ipc simulateBattery discharging 6 >/dev/null; sleep 1.2
critical=$(glow)
state_after_low=$(ipc geometry | jq -r .state)
ipc simulateBattery auto 0 >/dev/null
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""

show() { # show <label> <json>
  jq -r --arg l "$1" '"  \($l|.+"              "|.[0:14]) mode=\(.mode) colour=\(.color) intensity=\(.intensity) presence=\(.presence) surge=\(.surge) spread=\(.spread)px"' <<<"$2"
}
echo
show "on battery" "$idle"
show "surge peak" "$surge_peak"
show "charging" "$charging"
echo "  ${DIM}charging intensity every 200 ms: ${charging_samples[*]}${RESET}"
show "full" "$full"
show "low (18%)" "$low"
show "critical (6%)" "$critical"
python3 - "$charging" "$low" "$critical" <<'PY'
import json, sys
for label, raw in zip(("charging", "low", "critical"), sys.argv[1:]):
    g = json.loads(raw); s = g["style"]
    print(f'  {label:<12} intensity {s["base"]}–{s["base"] + s["amplitude"]:.2f}, breath period {s["period"]} ms (InOutSine)')
g = json.loads(sys.argv[1])
print(f'  surge        +{g["surgeIntensity"]} intensity, +{g["surgeSpread"]} px spread; up {g["surgeUpMs"]} ms OutCubic, down {g["surgeDownMs"]} ms InOutSine')
print(f'  halo         spread {6} px at rest, blurMax {g["blurMax"]} px, reach {g["reach"]} px past the bar; fade in/out {g["fadeMs"]} ms')
PY
echo

check "on battery above the thresholds there is no glow" "none 0" "$(jq -r '"\(.mode) \(.intensity)"' <<<"$idle")"
check "plugging in: the surge is playing within 280 ms" "true" "$(jq -r '.surge > 0.8' <<<"$surge_peak")"
check "…and the halo is spread past its resting size" "true" "$(jq -r '.spread > 12' <<<"$surge_peak")"
check "charging glows green (#30d158)" "charging #30d158" "$(jq -r '"\(.mode) \(.color)"' <<<"$charging")"
check "…fully faded in" "1" "$(jq -r '.presence' <<<"$charging")"
check "…breathing between 0.45 and 0.70" "true" \
  "$(python3 -c 'import sys; v=[float(x) for x in sys.argv[1:]]; print("true" if min(v) >= 0.449 and max(v) <= 0.701 and max(v) - min(v) > 0.05 else "false")' "${charging_samples[@]}")"
check "a full battery has no glow" "none 0" "$(jq -r '"\(.mode) \(.intensity)"' <<<"$full")"
check "18% on battery glows amber (#ff9f0a)" "low #ff9f0a" "$(jq -r '"\(.mode) \(.color)"' <<<"$low")"
check "6% on battery glows red (#ff453a)" "critical #ff453a" "$(jq -r '"\(.mode) \(.color)"' <<<"$critical")"
check "critical breathes faster than low" "true" \
  "$(jq -n --argjson l "$low" --argjson c "$critical" '$c.style.period < $l.style.period')"
check "running low opens a peek" "peek" "$state_after_low"

if grep -qE '\.qml:[0-9]+|ReferenceError|TypeError|Cannot assign|Unable to assign' "$root/qs.log"; then
  check "no QML errors while running" "none" "$(grep -E '\.qml:[0-9]+|ReferenceError|TypeError' "$root/qs.log" | head -1)"
fi

# ---------------------------------------------------------------------------
# The pixels
# ---------------------------------------------------------------------------

render() { # render <png> <colour> <intensity>
  QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qml6 "$root/glow-pixels.qml" -- w=180 h=32 r=10 fillet=10 "color=$2" "intensity=$3" "out=$1" 2>&1 \
    | sed -n 's/^.*GLOW \([a-zA-Z]*\) \(.*\)$/\1=\2/p'
}

sample() { # sample <png> <x> <y>  -> "alpha r g b" (0..1)
  magick "$1" -format "%[fx:p{$2,$3}.a] %[fx:p{$2,$3}.r] %[fx:p{$2,$3}.g] %[fx:p{$2,$3}.b]" info: 2>/dev/null
}

for spec in "charging #30d158 g" "low #ff9f0a r" "critical #ff453a r"; do
  read -r name colour channel <<<"$spec"
  png="$root/glow-$name.png"
  out=$(render "$png" "$colour" 1)
  echo; echo "${BOLD}Pixels, $name glow${RESET} ${DIM}($colour, intensity 1, 180×32 notch)${RESET}"
  check "rendered" "true" "$(sed -n 's/^saved=//p' <<<"$out")"
  [[ -f $png ]] || continue
  bx=$(sed -n 's/^barX=//p' <<<"$out" | cut -d. -f1); bxr=$((bx + 179)); mid=$((bx + 90))

  read -r a r g b <<<"$(sample "$png" "$mid" 15)"
  check "inside the notch stays pitch black ${DIM}α=$a rgb=$r,$g,$b${RESET}" "true" "$(yes_no "awk 'BEGIN{exit !($a==1 && $r==0 && $g==0 && $b==0)}'")"
  read -r a r g b <<<"$(sample "$png" "$bx" 0)"
  check "the bar's top-left corner is still square and black ${DIM}α=$a${RESET}" "true" "$(yes_no "awk 'BEGIN{exit !($a==1 && $r+$g+$b==0)}'")"

  prev=2; mono=true; profile=""
  for d in 1 4 8 16 32 48; do
    read -r a r g b <<<"$(sample "$png" "$mid" $((31 + d)))"
    profile+=" ${d}px:$(printf '%.2f' "$a")"
    awk -v a="$a" -v p="$prev" 'BEGIN{exit !(a < p)}' || mono=false
    prev=$a
  done
  echo "  ${DIM}halo alpha below the notch:$profile${RESET}"
  read -r a r g b <<<"$(sample "$png" "$mid" 35)"
  check "4 px below the notch the mist is visible (α ≥ 0.3) ${DIM}α=$a${RESET}" "true" "$(yes_no "awk 'BEGIN{exit !($a >= 0.3)}'")"
  dominant=$(awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN{ if (g>=r && g>=b) print "g"; else if (r>=g && r>=b) print "r"; else print "b" }')
  check "…in the glow's colour (strongest channel $channel) ${DIM}rgb=$r,$g,$b${RESET}" "$channel" "$dominant"
  check "…fading steadily with distance" "true" "$mono"
  read -r a _ <<<"$(sample "$png" "$mid" $((31 + 70)))"
  check "70 px below, past its reach, it is gone (α < 0.02) ${DIM}α=$a${RESET}" "true" "$(yes_no "awk 'BEGIN{exit !($a < 0.02)}'")"
  read -r al _ <<<"$(sample "$png" $((bx - 8)) 22)"
  read -r ar _ <<<"$(sample "$png" $((bxr + 8)) 22)"
  check "left and right halos match ${DIM}α=$al / $ar${RESET}" "true" "$(yes_no "awk 'BEGIN{d=$al-$ar; exit !(d < 0.02 && d > -0.02)}'")"
  read -r a _ <<<"$(sample "$png" $((bx - 14)) 0)"
  check "along the screen edge past the fillet, the mist follows the outline ${DIM}α=$a${RESET}" "true" "$(yes_no "awk 'BEGIN{exit !($a >= 0.1)}'")"
done

png="$root/glow-off.png"
out=$(render "$png" "#30d158" 0)
echo; echo "${BOLD}Pixels, glow off${RESET} ${DIM}(intensity 0)${RESET}"
if [[ -f $png ]]; then
  bx=$(sed -n 's/^barX=//p' <<<"$out" | cut -d. -f1)
  read -r a _ <<<"$(sample "$png" $((bx + 90)) 35)"
  check "no halo at all ${DIM}α=$a${RESET}" "0" "$a"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
