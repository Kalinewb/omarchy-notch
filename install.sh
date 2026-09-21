#!/bin/bash

# Put this repo's committed HEAD into the live plugin.
#
# The live plugin is a git checkout of GitHub's omarchy-notch, the way
# `omarchy plugin add` installs it, so `omarchy plugin update` works on it and
# the notch can tell when an update is out. This script fast-forwards that
# checkout to this repo's HEAD without touching its origin: commit here, run
# this to try it, push when it's ready. Uncommitted changes are never
# installed, so it refuses while there are any.
#
#   ./install.sh               fast-forward the live checkout to HEAD, restart the shell,
#                              make the notch the bar
#   ./install.sh --no-enable   the same, but leave the active bar alone
#   ./install.sh --swap-to-git replace an old copied (rsync) install with a git checkout
#                              from GitHub; the copy is moved to
#                              ~/.local/state/kalinewb.notch/backups/ first
#
# To go back to another bar:  omarchy plugin enable <bar id>   (e.g. omarchy.bar)

set -euo pipefail

ID="kalinewb.notch"
URL="https://github.com/Kalinewb/omarchy-notch.git"
PLUGINS="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/plugins"
DEST="$PLUGINS/$ID"
BACKUPS="${XDG_STATE_HOME:-$HOME/.local/state}/$ID/backups"
SRC="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ENABLE=1
SWAP=0
for arg in "$@"; do
  case "$arg" in
    --no-enable) ENABLE=0 ;;
    --swap-to-git) SWAP=1 ;;
    *) echo "install.sh: unknown option $arg" >&2; exit 2 ;;
  esac
done

say() { echo "install.sh: $*"; }
die() { echo "install.sh: $*" >&2; exit 1; }
export GIT_TERMINAL_PROMPT=0

# Omarchy watches the plugins folder, and a fast-forward rewrites most of the
# notch's files. The watcher reloads the plugin once per change -- 47 times for
# one install -- tearing down and rebuilding every QML object in it while the
# next change is still landing, and every quickshell crash this repo has seen
# happened inside that window. The shell is restarted at the end anyway, so it
# is stopped first and the files change with nobody watching.
#
# `restart` is set once it is known a restart is wanted and allowed; the EXIT
# trap then brings the shell back however this script ends.
restart=0
SHELL_DIR=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_DIR:=${OMARCHY_PATH:-/usr/share/omarchy}}"

stop_shell() {
  (( restart )) || return 0
  while timeout 5 quickshell kill -p "$SHELL_DIR/shell" --any-display >/dev/null 2>&1; do :; done
  say "stopped the shell while the files change"
}

relaunch_shell() {
  (( restart )) || return 0
  restart=0
  omarchy restart shell >/dev/null 2>&1 && say "restarted the shell" || say "could not restart the shell; run: omarchy restart shell"
  return 0
}

# --- this repo: committed, lint-clean, valid ---------------------------------------
[[ -z $(git -C "$SRC" status --porcelain --untracked-files=no) ]] \
  || die "uncommitted changes in $SRC would not be installed; commit them first"
HEAD=$(git -C "$SRC" rev-parse HEAD)

"$SRC/dev/lint.sh" || die "QML lint failed; nothing installed"

stage=$(mktemp -d "${TMPDIR:-/tmp}/$ID.stage.XXXXXX")
cleanup() { rm -rf "$stage"; relaunch_shell; }
trap cleanup EXIT
git -C "$SRC" archive "$HEAD" | tar -x -C "$stage"
if command -v omarchy >/dev/null; then
  omarchy plugin validate "$stage" >/dev/null || die "HEAD fails plugin validation"
fi

# --- an old copied install: swap it for a git checkout -----------------------------
if [[ -d $DEST && ! -d $DEST/.git ]]; then
  (( SWAP )) || die "$DEST is a copied install, not a git checkout; run ./install.sh --swap-to-git once"
  mkdir -p "$BACKUPS"
  backup="$BACKUPS/$(date -u +%Y%m%dT%H%M%SZ)-copy"
  mv "$DEST" "$backup"
  say "moved the copied install to $backup"
  # `plugin add` refuses an id the running shell still knows: let it forget.
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    omarchy plugin list --json 2>/dev/null | jq -e --arg id "$ID" 'any(.[]; .id == $id)' >/dev/null || break
    sleep 0.25
  done
fi

if [[ ! -d $DEST ]]; then
  if ! omarchy plugin add "$URL" --yes; then
    [[ -n ${backup:-} && ! -e $DEST ]] && mv "$backup" "$DEST" && say "restored the copied install"
    die "omarchy plugin add failed"
  fi
  [[ -d $DEST/.git ]] || die "omarchy plugin add did not create $DEST"
  say "installed $ID from $URL"
fi

# --- the checkout: fast-forward to this repo's HEAD --------------------------------
[[ -d $DEST/.git ]] || die "$DEST is not a git checkout"
[[ -z $(git -C "$DEST" status --porcelain --untracked-files=no) ]] \
  || die "the live checkout has local edits; not touching it ($DEST)"
current=$(git -C "$DEST" rev-parse HEAD)

if command -v omarchy >/dev/null \
   && ! { command -v omarchy-hyprland-session-locked >/dev/null && omarchy-hyprland-session-locked; }; then
  restart=1
  # Nothing is rewritten when it is already at HEAD, so nothing to be quiet for.
  if [[ $current != "$HEAD" ]]; then stop_shell; fi
fi

if [[ $current != "$HEAD" ]]; then
  git -C "$DEST" fetch --quiet "$SRC" "$HEAD"
  git -C "$DEST" merge-base --is-ancestor "$current" "$HEAD" \
    || die "the live checkout ($current) is not an ancestor of HEAD ($HEAD); resolve by hand"
  git -C "$DEST" merge --quiet --ff-only "$HEAD"
  say "fast-forwarded the live checkout ${current:0:7} → ${HEAD:0:7}"
else
  say "the live checkout is already at ${HEAD:0:7}"
fi
origin_head=$(git -C "$DEST" ls-remote origin HEAD 2>/dev/null | cut -f1 || true)
if [[ -n $origin_head && $origin_head != "$HEAD" ]]; then
  say "note: GitHub is at ${origin_head:0:7}; push to publish ${HEAD:0:7}"
fi

if (( ! restart )); then
  command -v omarchy >/dev/null || exit 0
  say "the session is locked; not restarting the shell"
  exit 0
fi

# An installed menu companion is a copy of the notch's companion/ folder, so it
# follows the notch. Run the installed copy's own script, which syncs from the
# checkout that was just fast-forwarded. Nothing happens when it isn't installed.
if [[ -d "$PLUGINS/kalinewb.notch-menu" && -x "$DEST/bin/notch-companion" ]]; then
  "$DEST/bin/notch-companion" sync >/dev/null 2>&1 && say "synced the menu companion"
fi

# A rescan reloads the entry point but not the other QML files, so restart the
# shell: the honest way to see every file's change.
relaunch_shell

if (( ENABLE )); then
  for _ in $(seq 1 40); do
    omarchy-shell shell ping >/dev/null 2>&1 && break
    sleep 0.25
  done
  omarchy plugin enable "$ID" >/dev/null && say "$ID is the active bar"
fi
