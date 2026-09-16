#!/bin/bash

# The notch's shape, as numbers.
#
#   ./dev/geometry.sh            default settings
#   NOTCH_HARNESS_CONFIG='{"compactWidth":220}' ./dev/geometry.sh
#
# Starts the real Bar.qml in a throwaway Quickshell instance (it draws on the
# screen for about three seconds, over the live bar), reads back every radius
# and arc centre over IPC -- once at rest and once expanded -- and checks them
# arithmetically. Then renders Island.qml offscreen at exactly those sizes and
# samples the pixels that tell a fused bar from a floating pill and from a
# notch cut into the bar.
#
# Nothing here judges a screenshot. Set NOTCH_KEEP_PNG=dir to keep the PNGs.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0

check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

for tool in quickshell qml6 magick python3; do
  command -v "$tool" >/dev/null || { echo "geometry: $tool is not installed" >&2; exit 1; }
done

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
[[ -d $SHELL_PATH/shell/Commons ]] || { echo "geometry: no Omarchy shell at $SHELL_PATH/shell" >&2; exit 1; }

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-geometry.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
cp "$REPO/dev/harness/island-pixels.qml" "$root/island-pixels.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }

echo "${BOLD}Notch geometry${RESET}  ${DIM}shell: $SHELL_PATH/shell  plugin: $REPO${RESET}"

NOTCH_HARNESS_CONFIG=${NOTCH_HARNESS_CONFIG:-"{}"} quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
qs_pid=$!

compact=""
for _ in $(seq 1 40); do
  sleep 0.1
  compact=$(ipc geometry) && [[ $compact == \{* ]] && break
done
[[ $compact == \{* ]] || { echo "${RED}the harness never answered${RESET}"; tail -20 "$root/qs.log"; exit 1; }
sleep 0.9                       # the entrance is 350 ms; let it settle
compact=$(ipc geometry)
ipc expand >/dev/null
sleep 0.9
expanded=$(ipc geometry)
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""

qml_errors='\.qml:[0-9]+|ReferenceError|TypeError|is not a type|Cannot assign|Unable to assign'
if grep -qE "$qml_errors" "$root/qs.log"; then
  echo "${RED}QML errors or warnings while running:${RESET}"; grep -E "$qml_errors" "$root/qs.log" | head
  failures=$((failures + 1))
fi

# ---------------------------------------------------------------------------
# The numbers
# ---------------------------------------------------------------------------

report() { # report <json> <label>
  python3 - "$1" "$2" <<'PY'
import json, sys
g = json.loads(sys.argv[1]); label = sys.argv[2]
b, r, cb, cs = g["bar"], g["radii"], g["centresBar"], g["centresScreen"]
p = lambda c: f'({c["x"]:g}, {c["y"]:g})'
print(f'\n\033[1m{label}\033[0m  state={g["state"]}  screen {g["screen"]["name"]} {g["screen"]["width"]}x{g["screen"]["height"]} (logical px)')
print(f'  bar rectangle          x={b["x"]:g} y={b["y"]:g} w={b["width"]:g} h={b["height"]:g}')
print(f'  top corner radii       left={r["topLeft"]:g} right={r["topRight"]:g}')
print(f'  bottom corner radius   left={r["bottomLeft"]:g} right={r["bottomRight"]:g}  (convex; requested {r["bottomRequested"]:g})')
print(f'  fillet radius          {r["fillet"]:g}  (concave, both sides; requested {r["filletRequested"]:g})')
print(f'  arc centres, bar coordinates (origin = bar top-left, y down)')
for k, name in (("leftFillet","left fillet"),("rightFillet","right fillet"),("bottomLeft","bottom-left"),("bottomRight","bottom-right")):
    print(f'    {name:<14} {p(cb[k]):<22} screen {p(cs[k])}')
print(f'  window                 height={g["window"]["height"]:g}, exclusive zone={g["window"]["exclusiveZone"]:g}')
PY
}

# verify <json> -> prints tab-separated "name expected actual" lines for check()
verify() {
  python3 - "$1" <<'PY'
import json, sys
g = json.loads(sys.argv[1])
b, r, cb, cs = g["bar"], g["radii"], g["centresBar"], g["centresScreen"]
W, H, R, F = b["width"], b["height"], r["bottomLeft"], r["fillet"]
close = lambda a, e: abs(a - e) < 0.01
out = []
def c(name, ok): out.append(f"{name}\ttrue\t{'true' if ok else 'false'}")
c("the bar has settled on its target size", close(W, g["target"]["width"]) and close(H, g["target"]["height"]))
c("the bar's top edge is on the screen's top edge (y = 0)", b["y"] == 0)
c("the top corners have no radius (not a pill)", r["topLeft"] == 0 and r["topRight"] == 0)
c("both bottom corners share one convex radius", r["bottomLeft"] == r["bottomRight"] and R > 0)
c("…which is under half the height (a rounded rectangle, not a pill)", R < H / 2)
c("the fillet radius is positive and leaves a straight side above the bottom corner", 0 < F <= H - R)
c(f"left fillet centre is ({-F:g}, {F:g}): one radius outside the left side, one radius down", close(cb["leftFillet"]["x"], -F) and close(cb["leftFillet"]["y"], F))
c(f"right fillet centre is ({W + F:g}, {F:g}): one radius outside the right side, one radius down", close(cb["rightFillet"]["x"], W + F) and close(cb["rightFillet"]["y"], F))
c("neither fillet centre lies inside the bar (arcs belong to the background)", cb["leftFillet"]["x"] < 0 and cb["rightFillet"]["x"] > W)
c("each fillet arc is tangent to the screen edge: centre.y − r = 0", close(cb["leftFillet"]["y"] - F, 0) and close(cb["rightFillet"]["y"] - F, 0))
c("…and tangent to the bar's side: |centre.x − side| = r", close(0 - cb["leftFillet"]["x"], F) and close(cb["rightFillet"]["x"] - W, F))
c("bottom centres are one radius in from the sides and bottom", close(cb["bottomLeft"]["x"], R) and close(cb["bottomLeft"]["y"], H - R) and close(cb["bottomRight"]["x"], W - R))
sw = g["screen"]["width"]
c("the bar is centred on the screen", abs(b["x"] + W / 2 - sw / 2) < 0.5)
c("screen centres = bar centres + bar origin", close(cs["leftFillet"]["x"], b["x"] - F) and close(cs["rightFillet"]["x"], b["x"] + W + F))
print("\n".join(out))
PY
}

run_checks() {
  while IFS=$'\t' read -r name expected actual; do
    check "$name" "$expected" "$actual"
  done < <(verify "$1")
}

report "$compact" "At rest"
run_checks "$compact"
report "$expanded" "Expanded"
run_checks "$expanded"

check "expanded is taller than at rest" "true" \
  "$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); b=json.loads(sys.argv[2]); print("true" if b["bar"]["height"] > a["bar"]["height"] else "false")' "$compact" "$expanded")"
check "windows are kept below the resting notch (windowsToTop off)" "true" \
  "$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); print("true" if abs(a["window"]["exclusiveZone"] - __import__("math").ceil(a["bar"]["height"])) < 0.01 else "false")' "$compact")"

python3 - "$compact" <<'PY'
import json, sys
m = json.loads(sys.argv[1])["motion"]
print(f'\n\033[1mMotion\033[0m')
print(f'  grow      height {m["growHeightMs"]} ms; width after {m["growWidthDelayMs"]} ms over {m["growWidthMs"]} ms')
print(f'  spring    damping ratio {m["springDamping"]}, overshoot {m["springOvershoot"]*100:.2f} %, peak at {m["springPeakAt"]} of the duration')
print(f'  shrink    {m["shrinkMs"]} ms OutCubic, no overshoot')
print(f'  entrance  from {m["seedWidthFraction"]} × width, zero height, top edge on the screen edge')
PY

# ---------------------------------------------------------------------------
# The pixels
# ---------------------------------------------------------------------------

alpha_at() { magick "$1" -format "%[fx:p{$2,$3}.a]" info: 2>/dev/null; }
check_alpha() { # check_alpha <png> <description> <opaque|clear> <x> <y>
  local a got
  a=$(alpha_at "$1" "$4" "$5")
  if awk -v a="$a" 'BEGIN { exit !(a >= 0.9) }'; then got=opaque
  elif awk -v a="$a" 'BEGIN { exit !(a <= 0.1) }'; then got=clear
  else got="edge($a)"; fi
  check "$2 ${DIM}@($4,$5) α=$a${RESET}" "$3" "$got"
}

pixels() { # pixels <json> <label>
  local json=$1 label=$2 png="$root/island-$2.png"
  read -r W H R F < <(python3 -c 'import json,sys; g=json.loads(sys.argv[1]); print(g["bar"]["width"], g["bar"]["height"], g["radii"]["bottomLeft"], g["radii"]["fillet"])' "$json")
  echo; echo "${BOLD}Pixels, $label${RESET}  ${DIM}Island.qml offscreen at ${W}×${H}, bottom r=$R, fillet r=$F${RESET}"
  geom=$(QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 timeout 30 qml6 "$root/island-pixels.qml" -- \
    "w=$W" "h=$H" "r=$R" "fillet=$F" "out=$png" 2>&1 | sed -n 's/^.*GEOM \([a-zA-Z]*\) \(.*\)$/\1=\2/p')
  check "rendered to a PNG" "true" "$(sed -n 's/^saved=//p' <<<"$geom")"
  [[ -f $png ]] || return
  local bx bw bh f r bxr
  bx=$(sed -n 's/^barX=//p' <<<"$geom" | cut -d. -f1)
  bw=$(printf '%.0f' "$W"); bh=$(printf '%.0f' "$H"); f=$(printf '%.0f' "$F"); r=$(printf '%.0f' "$R")
  bxr=$((bx + bw - 1))

  check_alpha "$png" "bar's top-left corner pixel is solid (square top corner)" opaque "$bx" 0
  check_alpha "$png" "bar's top-right corner pixel is solid (square top corner)" opaque "$bxr" 0
  check "every pixel of the bar's top row is solid" "1" \
    "$(magick "$png" -crop "${bw}x1+${bx}+0" +repage -channel A -separate -format '%[fx:minima]' info:)"
  check_alpha "$png" "bottom-left corner pixel is empty (convex round)" clear "$bx" "$((bh - 1))"
  check_alpha "$png" "bottom-right corner pixel is empty (convex round)" clear "$bxr" "$((bh - 1))"
  check_alpha "$png" "bottom edge is solid one radius in" opaque "$((bx + r + 2))" "$((bh - 1))"
  # Fillet material is thickest on the diagonal from the bar's corner towards
  # the arc centre: r(√2−1). Two px in is fillet, past that it is open.
  local open=$(( $(printf '%.0f' "$(awk -v f="$F" 'BEGIN { print f * (sqrt(2) - 1) }')") + 2 ))
  check_alpha "$png" "left: screen edge just outside the bar is solid (fillet)" opaque "$((bx - 1))" 0
  check_alpha "$png" "left: 2 px down the diagonal is fillet" opaque "$((bx - 2))" 2
  check_alpha "$png" "left: ${open} px down the diagonal is past the arc" clear "$((bx - open))" "$open"
  check_alpha "$png" "left: the arc centre is open background" clear "$((bx - f))" "$f"
  check_alpha "$png" "right: screen edge just outside the bar is solid (fillet)" opaque "$((bxr + 1))" 0
  check_alpha "$png" "right: 2 px down the diagonal is fillet" opaque "$((bxr + 2))" 2
  check_alpha "$png" "right: ${open} px down the diagonal is past the arc" clear "$((bxr + open))" "$open"
  check_alpha "$png" "right: the arc centre is open background" clear "$((bxr + f))" "$f"
  check_alpha "$png" "left: below the fillet the bar's side is bare" clear "$((bx - 1))" "$((f + 2))"
  check_alpha "$png" "right: below the fillet the bar's side is bare" clear "$((bxr + 1))" "$((f + 2))"
  check "no seam: the bar's first column is solid down the fillet" "1" \
    "$(magick "$png" -crop "1x${f}+${bx}+0" +repage -channel A -separate -format '%[fx:minima]' info:)"
  check "no seam: the bar's last column is solid down the fillet" "1" \
    "$(magick "$png" -crop "1x${f}+${bxr}+0" +repage -channel A -separate -format '%[fx:minima]' info:)"
  [[ -n ${NOTCH_KEEP_PNG:-} ]] && mkdir -p "$NOTCH_KEEP_PNG" && cp "$png" "$NOTCH_KEEP_PNG/"
}

pixels "$compact" rest
pixels "$expanded" expanded

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
