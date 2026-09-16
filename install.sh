#!/bin/bash

# Sync this working tree into the live plugin directory.
#
# Development does not happen in ~/.config/omarchy/plugins: that tree is watched
# recursively, and every write there reloads plugins. The repo lives outside it
# and this pushes one validated copy in.
#
#   ./install.sh              install, make the notch the active bar, restart the shell
#   ./install.sh --no-enable  install only; the current bar stays active
#
# To go back to another bar:  omarchy plugin enable <bar id>   (e.g. omarchy.bar)

set -euo pipefail

ID="graveklar.notch"
PLUGINS="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
DEST="$PLUGINS/$ID"
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODE=${1:-}

# Validate a staging copy before anything lands in the watched folder. A dot
# name is ignored by the plugin watcher, so staging costs no reload.
STAGE=$(mktemp -d "$PLUGINS/.$ID.stage.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT

EXCLUDES=(--exclude '.git' --exclude 'install.sh' --exclude 'dev' --exclude '*.bak')
rsync -a "${EXCLUDES[@]}" "$SRC/" "$STAGE/"

if command -v omarchy >/dev/null; then
  omarchy plugin validate "$STAGE" || { echo "install.sh: plugin failed validation" >&2; exit 1; }
fi

mkdir -p "$DEST"
rsync -a --delete --delete-excluded "${EXCLUDES[@]}" "$STAGE/" "$DEST/"
rm -rf "$STAGE"
trap - EXIT
echo "installed $ID -> $DEST"

command -v omarchy >/dev/null || exit 0

if command -v omarchy-hyprland-session-locked >/dev/null && omarchy-hyprland-session-locked; then
  echo "install.sh: the session is locked; not touching the running shell" >&2
  exit 0
fi

# A rescan reloads the entry point but not the other QML types in the folder,
# so restart the shell: the honest way to see every file's change.
omarchy restart shell >/dev/null 2>&1 && echo "restarted the shell"

if [[ $MODE != --no-enable ]]; then
  for _ in $(seq 1 40); do
    omarchy-shell shell ping >/dev/null 2>&1 && break
    sleep 0.25
  done
  omarchy plugin enable "$ID" >/dev/null && echo "$ID is the active bar"
fi
