#!/bin/bash

# The outline glow's soft strength and its fade along the screen's top edge.
#
#   ./dev/glow-fade.sh
#
# Glow.qml behind Island.qml, rendered offscreen (OpenGL RHI) by
# dev/harness/glow-fade-pixels.qml, once as the plain glow (edgeTail 1) and
# once tapering (edgeTail 3), at the soft strength the bar uses (0.24) and at
# the curve's own 0.35. The frozen glow.sh and glow-bottom.sh never set
# either, so they keep drawing the plain glow at 0.35.
#
#   - strength only scales the curve: 0.24 is the 0.35 render times 0.24/0.35
#   - row 0, going out from the fillet tip: never rises, runs 2.4 to 3.0 times
#     the reach, the tip is as bright as the plain glow's, and well past the
#     plain glow's circle it is at least twice as bright
#   - no clip: rows 0 to 8 never rise downward and the profile has no kink at the top row
#   - no step or kink along the row
#   - below the bar's bottom edge, and over its width (to a pixel inside the fillet tips), nothing changes
#   - the bar reports the strength and tail it draws with (a live instance)

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
  command -v "$tool" >/dev/null || { echo "glow-fade: $tool is not installed" >&2; exit 1; }
done

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-glow-fade.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
cp "$REPO/dev/harness/glow-fade-pixels.qml" "$root/glow-fade-pixels.qml"

render() { # render <png> <tail> <strength> [presence] -> the bar's x in the image
  QT_QUICK_BACKEND=rhi QSG_RHI_BACKEND=opengl QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
    timeout 30 qml6 "$root/glow-fade-pixels.qml" -- w=180 h=31.5 r=10 fillet=10 offset=0.5 color=#FFB340 "presence=${4:-1}" size=32 "tail=$2" "strength=$3" "out=$1" 2>&1 \
    | sed -n 's/^.*GLOW barX //p'
}

echo "${BOLD}Outline glow: soft strength and top-edge fade${RESET}  ${DIM}plugin: $REPO${RESET}"
bx=$(render "$root/t1-35.png" 1 0.35)
render "$root/t1-24.png" 1 0.24 >/dev/null
render "$root/t3-35.png" 3 0.35 >/dev/null
render "$root/t3-24.png" 3 0.24 >/dev/null
render "$root/island.png" 1 0.35 0 >/dev/null     # the notch alone, to leave its antialiased edge out
echo "  ${DIM}180 × 31.5 notch, bottom r=10, fillet r=10, reach 32 px, amber; bar at x=$bx${RESET}"

m=$(python3 -I - "$root" "$bx" <<'PY'
import json, subprocess, sys
import numpy as np
root, bx = sys.argv[1], float(sys.argv[2])
W, H, F, REACH = 180.0, 31.5, 10.0, 32.0

def load(name):
    png = f"{root}/{name}.png"
    raw = subprocess.run(["magick", png, "-depth", "8", "rgba:-"], capture_output=True, check=True).stdout
    w, h = map(int, subprocess.run(["magick", "identify", "-format", "%w %h", png], capture_output=True, text=True).stdout.split())
    return np.frombuffer(raw, dtype=np.uint8).reshape(h, w, 4)[:, :, 3].astype(float) / 255

a = {k: load(k) for k in ("t1-35", "t1-24", "t3-35", "t3-24", "island")}
own = a["island"] > 0                          # pixels the notch itself touches: not glow
tip = bx - F                                  # fillet tip, image x
cols = np.arange(int(tip - 0.5), -1, -1)       # pixel columns going out to the left, nearest first
out = tip - (cols + 0.5)                       # px from the tip to each pixel centre
def row(img, y): return img[y, cols]
def at(img, y, d): return float(img[y, cols[int(np.argmin(abs(out - d)))]])
res = {}
for k, strength in (("35", 0.35), ("24", 0.24)):
    t3, t1 = a["t3-" + k], a["t1-" + k]
    r0 = row(t3, 0)
    lit = np.nonzero(r0 > 1 / 255)[0]
    keep = out >= 3                                # past the notch's own antialiased edge
    d = np.diff(r0[keep])
    res[k] = {
        "monotone": bool((d <= 1e-9).all()),
        "lastLit": float(out[lit[-1]] + 0.5) if len(lit) else 0.0,
        "tip": at(t3, 0, 2.5), "strength": strength,
        "a12": at(t3, 0, 12), "a24": at(t3, 0, 24), "a24plain": at(t1, 0, 24),
        "noClip": all(abs((at(t3, 0, x) - at(t3, 1, x)) - (at(t3, 1, x) - at(t3, 2, x))) <= 3 / 255 * strength / 0.35 + 1e-9 for x in (12, 24, 48)),
        "clipDiff": [round((at(t3, 0, x) - at(t3, 1, x)) - (at(t3, 1, x) - at(t3, 2, x)), 4) for x in (12, 24, 48)],
        "rowsDown": all(all(np.diff([at(t3, y, x) for y in range(0, 9)]) <= 1e-9) for x in (12, 24, 48)),
        "maxStep": float(np.abs(d).max()), "maxKink": float(np.abs(np.diff(d)).max()),
        "row": [round(float(v), 3) for v in r0[::6]],
    }
# strength only scales the curve
res["scales"] = float(np.abs(a["t1-24"] - a["t1-35"] * 0.24 / 0.35)[~own].max())
res["scalesTail"] = float(np.abs(a["t3-24"] - a["t3-35"] * 0.24 / 0.35)[~own].max())
# nothing changes below the bar's bottom edge or over it
h, w = a["t1-35"].shape
yy, xx = np.mgrid[0:h, 0:w]
far = (yy + 0.5 > H) | ((xx + 0.5 >= bx - F + 1) & (xx + 0.5 <= bx + W + F - 1))
res["unchangedElsewhere"] = float(np.abs(a["t3-35"] - a["t1-35"])[far & ~own].max())
res["changedPixels"] = int((np.abs(a["t3-35"] - a["t1-35"]) > 1.5 / 255).sum())
ys, xs = np.nonzero((np.abs(a["t3-35"] - a["t1-35"]) > 1.5 / 255) & far & ~own)
res["where"] = {"xMin": int(xs.min() - bx) if len(xs) else None, "xMax": int(xs.max() - bx) if len(xs) else None, "yMin": int(ys.min()) if len(ys) else None, "yMax": int(ys.max()) if len(ys) else None}
res["changedOutsideTop"] = int(((np.abs(a["t3-35"] - a["t1-35"]) > 1.5 / 255) & far & ~own).sum())
# the soft glow stays a glow under the notch: still pure black inside
res["insideNotch"] = [float(v) for v in subprocess.run(["magick", f"{root}/t3-24.png", "-depth", "8", "-format", "%[fx:p{%d,12}.r],%[fx:p{%d,12}.a]".replace("%d", str(int(bx + W / 2))), "info:"], capture_output=True, text=True).stdout.split(",")]
print(json.dumps(res))
PY
)
[[ -n $m ]] || { check "analysed" "true" "false"; exit 1; }

for k in 35 24; do
  s=$(jq -r ".\"$k\".strength" <<<"$m")
  echo; echo "${BOLD}strength $s, edgeTail 3${RESET}"
  echo "  ${DIM}row 0 out from the tip, every 6 px: $(jq -r ".\"$k\".row | map(tostring) | join(\" \")" <<<"$m")${RESET}"
  check "row 0 from the tip never rises" "true" "$(jq -r ".\"$k\".monotone" <<<"$m")"
  check "…and its last visible pixel is 2.4 to 3.0 × the reach out (77 to 96 px) ${DIM}($(jq -r ".\"$k\".lastLit" <<<"$m") px)${RESET}" "true" \
    "$(jq -r ".\"$k\".lastLit >= 76.8 and .\"$k\".lastLit <= 96.5" <<<"$m")"
  check "the tip is as bright as the plain glow's: $s ±1/255 ${DIM}($(jq -r ".\"$k\".tip*1000|round/1000" <<<"$m"))${RESET}" "true" \
    "$(jq -r ".\"$k\" | (.tip - .strength | fabs) <= 1/255 + 0.0005" <<<"$m")"
  check "12 px out it is still at least 0.25 × strength/0.35 ${DIM}($(jq -r ".\"$k\".a12*1000|round/1000" <<<"$m"))${RESET}" "true" \
    "$(jq -r ".\"$k\" | .a12 >= 0.25 * .strength / 0.35" <<<"$m")"
  check "24 px out it is at least twice the plain glow's ${DIM}($(jq -r ".\"$k\".a24*1000|round/1000" <<<"$m") against $(jq -r ".\"$k\".a24plain*1000|round/1000" <<<"$m"))${RESET}" "true" \
    "$(jq -r ".\"$k\" | .a24 >= 2 * .a24plain" <<<"$m")"
  check "no clipped top row: the drop from row 0 to row 1 is within 3/255 of the drop from row 1 to row 2 at 12, 24, 48 px out, and rows 0 to 8 never rise downward ${DIM}(second difference down the rows: $(jq -r ".\"$k\".clipDiff | map(tostring) | join(\" \")" <<<"$m"))${RESET}" "true true" \
    "$(jq -r ".\"$k\" | \"\(.noClip) \(.rowsDown)\"" <<<"$m")"
  check "no step or kink along row 0: neighbours differ by at most 0.035, and that changes by at most 0.035 ${DIM}($(jq -r ".\"$k\".maxStep*1000|round/1000" <<<"$m") / $(jq -r ".\"$k\".maxKink*1000|round/1000" <<<"$m"))${RESET}" "true" \
    "$(jq -r ".\"$k\" | .maxStep <= 0.035 and .maxKink <= 0.035" <<<"$m")"
done

echo
echo "${BOLD}Against the plain glow${RESET}"
check "strength 0.24 is the 0.35 glow scaled by 0.24/0.35, to within 1/255 (plain, and with the tail) ${DIM}($(jq -r '.scales*1000|round/1000' <<<"$m") / $(jq -r '.scalesTail*1000|round/1000' <<<"$m"))${RESET}" "true" \
  "$(jq -r '.scales <= 1/255 + 0.0005 and .scalesTail <= 1/255 + 0.0005' <<<"$m")"
check "below the bar's bottom edge, and over the notch's width up to a pixel inside its fillet tips, edgeTail 3 changes nothing (±1/255) ${DIM}(max $(jq -r '.unchangedElsewhere*1000|round/1000' <<<"$m"); $(jq -r .changedPixels <<<"$m") pixels differ, $(jq -r .changedOutsideTop <<<"$m") of them there)${RESET}" "true" \
  "$(jq -r '.unchangedElsewhere <= 1/255 + 0.0005' <<<"$m")"

# ---------------------------------------------------------------------------
# The bar draws the outline glow with them
# ---------------------------------------------------------------------------

echo
echo "${BOLD}The bar${RESET}"
ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
NOTCH_HARNESS_CONFIG='{}' quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 0.8
ipc simulateBattery charging 64 >/dev/null; sleep 1.5
live=$(ipc geometry | jq -c '.glow.curve | {style, outlineDrawn, outlineStrength, tail}')
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
echo "  ${DIM}reported: $live${RESET}"
check "the default outline glow is drawn at strength 0.24 with edgeTail 3" '{"style":"outline","outlineDrawn":true,"outlineStrength":0.24,"tail":3}' "$live"
if grep -qE '\.qml:[0-9]+|ReferenceError|TypeError|Cannot assign|Unable to assign' "$root/qs.log"; then
  check "no QML errors while running" "none" "$(grep -E '\.qml:[0-9]+|ReferenceError|TypeError' "$root/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
