#!/usr/bin/env bash
# Render every marketing/src/*.html to marketing/<name>.png with headless
# Chromium at device scale factor 2. Each page declares its CSS canvas as
# `--w: <n>px; --h: <n>px;` on :root; the PNG comes out at twice that.
#
#   ./render.sh               # all pages
#   ./render.sh notch-hero    # just the named pages
#
# Needs: chromium, and ImageMagick's `magick` for the size check. No network.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="$here/src"
out="$here"
scale=2

chromium_bin="${CHROMIUM:-$(command -v chromium || command -v chromium-browser || command -v google-chrome || true)}"
if [[ -z "$chromium_bin" ]]; then
  echo "render.sh: chromium not found (set CHROMIUM=/path/to/chromium)" >&2
  exit 1
fi

pages=()
if (($#)); then
  for name in "$@"; do pages+=("$src/${name%.html}.html"); done
else
  pages=("$src"/*.html)
fi

# A throwaway profile, so rendering never touches a real browser profile.
profile="$(mktemp -d)"
trap 'rm -rf "$profile"' EXIT

status=0
for page in "${pages[@]}"; do
  name="$(basename "$page" .html)"
  w="$(grep -oP -- '--w:\s*\K[0-9]+' "$page" | head -1)"
  h="$(grep -oP -- '--h:\s*\K[0-9]+' "$page" | head -1)"
  if [[ -z "$w" || -z "$h" ]]; then
    echo "render.sh: $name: no --w/--h canvas size" >&2
    status=1
    continue
  fi
  png="$out/$name.png"
  "$chromium_bin" \
    --headless=new \
    --disable-gpu \
    --hide-scrollbars \
    --no-first-run \
    --no-default-browser-check \
    --user-data-dir="$profile" \
    --force-device-scale-factor="$scale" \
    --window-size="$w,$h" \
    --virtual-time-budget=3000 \
    --screenshot="$png" \
    "file://$page" >/dev/null 2>&1
  expect="$((w * scale))x$((h * scale))"
  got="$(magick identify -format '%wx%h' "$png")"
  if [[ "$got" == "$expect" ]]; then
    echo "$name.png  $got"
  else
    echo "$name.png  $got (expected $expect)" >&2
    status=1
  fi
done
exit "$status"
