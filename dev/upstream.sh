#!/bin/bash

# The Omarchy files this plugin was ported from.
#
#   ./dev/upstream.sh            what changed upstream since the last port
#   ./dev/upstream.sh --record   copy the current files in and record their hashes
#
# The notch forks a few of Omarchy's own QML files (the menu, the confirm
# dialog) and reads others closely (the bar, the notification service). When
# Omarchy updates, those forks quietly fall behind. `dev/upstream/` keeps a
# verbatim copy of each file as it was when the port was made, and
# `upstream.json` records Omarchy's version and each file's sha256 -- so this
# script, and the notch's own Setup page, can say exactly which ones moved.
#
# --record is a deliberate act: run it when a port is done, then commit the
# result. Nothing generates it at install time.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
OUT="$REPO/dev/upstream"
RECORD="$OUT/upstream.json"
SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
SRC="$SHELL_PATH/shell"

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'

# Upstream path (under $OMARCHY_PATH/shell) -> where the copy lives in dev/upstream.
FILES=(
  "plugins/menu/Menu.qml:menu/Menu.qml"
  "plugins/menu/MenuModel.js:menu/MenuModel.js"
  "Ui/ConfirmDialog.qml:ui/ConfirmDialog.qml"
  "plugins/bar/Bar.qml:bar/Bar.qml"
  "plugins/bar/BarModel.js:bar/BarModel.js"
  "plugins/notifications/Service.qml:notifications/Service.qml"
  "plugins/notifications/NotificationLogic.js:notifications/NotificationLogic.js"
)

version() { omarchy-version 2>/dev/null | tr -d '\n'; }
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }

if [[ ${1:-} == --record ]]; then
  entries=""
  for pair in "${FILES[@]}"; do
    up=${pair%%:*}; local_path=${pair#*:}
    if [[ ! -f $SRC/$up ]]; then echo "upstream.sh: missing $SRC/$up" >&2; exit 1; fi
    mkdir -p "$(dirname "$OUT/$local_path")"
    cp "$SRC/$up" "$OUT/$local_path"
    entries+=$(jq -nc --arg k "$up" --arg v "$(sha "$SRC/$up")" '{key: $k, value: $v}')$'\n'
  done
  jq -s --arg version "$(version)" --arg at "$(date -u +%Y-%m-%d)" \
    '{omarchyVersion: $version, recordedAt: $at, files: from_entries}' <<<"$entries" >"$RECORD"
  echo "recorded ${#FILES[@]} files against Omarchy $(version)"
  exit 0
fi

[[ -f $RECORD ]] || { echo "upstream.sh: nothing recorded yet; run ./dev/upstream.sh --record" >&2; exit 1; }
recorded=$(jq -r '.omarchyVersion // ""' "$RECORD")
live=$(version)
echo "${BOLD}Upstream${RESET}  ${DIM}recorded against Omarchy $recorded, this machine runs $live${RESET}"
[[ $recorded == "$live" ]] || echo "  ${RED}Omarchy changed version${RESET}"

changed=0
while read -r up want; do
  got=$(sha "$SRC/$up")
  if [[ $got == "$want" ]]; then
    echo "  ${GREEN}same${RESET}  $up"
  else
    changed=$((changed + 1))
    echo "  ${RED}MOVED${RESET} $up"
    echo "        ${DIM}diff -u $SRC/$up $OUT/$(grep -m1 "^$up:" <<<"$(printf '%s\n' "${FILES[@]}")" | cut -d: -f2)${RESET}"
  fi
done < <(jq -r '.files | to_entries[] | "\(.key) \(.value)"' "$RECORD")

echo
if (( changed )); then echo "$changed file(s) moved upstream; port them, then ./dev/upstream.sh --record"; exit 1; fi
echo "nothing moved upstream"
