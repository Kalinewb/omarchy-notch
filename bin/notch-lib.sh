# shellcheck shell=bash
# The plumbing bin/notch-setup and bin/notch-config share: where things are,
# the commands they run, the guard, and the few reads of shell.json both need.
# Sourced, never run. It defines no flags and runs nothing at load.
#
# The caller sets PROG (its own name, for the guard's message) before sourcing,
# and NOTCH_DIR (the notch's folder) before it calls catalogue_ids.

ID="kalinewb.notch"

# --- where things are ---------------------------------------------------------------

SANDBOX="${NOTCH_SETUP_SANDBOX:-}"
if [[ -n $SANDBOX ]]; then
  : "${NOTCH_SETUP_HOME:=$SANDBOX/home}"
  : "${NOTCH_SETUP_CONFIG_DIR:=$SANDBOX/home/.config}"
  : "${NOTCH_SETUP_TOGGLES_DIR:=$SANDBOX/home/.local/state/omarchy/toggles}"
  : "${NOTCH_SETUP_STATE_DIR:=$SANDBOX/home/.local/state/$ID/setup}"
  : "${NOTCH_SETUP_STATUS:=$SANDBOX/run/$ID/setup.json}"
fi

HOME_DIR="${NOTCH_SETUP_HOME:-$HOME}"
CONFIG="${NOTCH_SETUP_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME_DIR/.config}}"
TOGGLES="${NOTCH_SETUP_TOGGLES_DIR:-$HOME_DIR/.local/state/omarchy/toggles}"
STATE="${NOTCH_SETUP_STATE_DIR:-${XDG_STATE_HOME:-$HOME_DIR/.local/state}/$ID/setup}"
STATUS_DEFAULT="${NOTCH_SETUP_STATUS:-${XDG_RUNTIME_DIR:-/tmp}/$ID/setup.json}"
OMARCHY_DIR="${NOTCH_SETUP_OMARCHY_PATH:-${OMARCHY_PATH:-/usr/share/omarchy}}"
PLUGINS="${NOTCH_SETUP_PLUGINS_DIR:-$CONFIG/omarchy/plugins}"
SHELL_JSON="$CONFIG/omarchy/shell.json"
HYPR="$CONFIG/hypr"

# --- the commands it runs, each replaceable by a stub -------------------------------

split() { local -n _out=$1; read -ra _out <<<"$2"; }
split HYPRCTL "${NOTCH_SETUP_HYPRCTL:-hyprctl}"
split OMARCHY_SHELL "${NOTCH_SETUP_OMARCHY_SHELL:-omarchy-shell}"
split OMARCHY "${NOTCH_SETUP_OMARCHY:-omarchy}"
split OMARCHY_VERSION "${NOTCH_SETUP_OMARCHY_VERSION:-omarchy-version}"
split TOGGLE_BAR "${NOTCH_SETUP_TOGGLE_BAR:-omarchy-toggle-bar}"
split QS "${NOTCH_SETUP_QS:-qs}"
split KILL_CMD "${NOTCH_SETUP_KILL:-kill}"
split LUA "${NOTCH_SETUP_LUA:-lua}"
split SESSION_LOCKED "${NOTCH_SETUP_SESSION_LOCKED:-omarchy-hyprland-session-locked}"
split RESTART_SHELL "${NOTCH_SETUP_RESTART_SHELL:-omarchy restart shell}"
PLUGINS_STATE="${NOTCH_SETUP_PLUGINS_STATE:-}"

PROC="${NOTCH_SETUP_PROC:-/proc}"
RETENTION_DAYS="${NOTCH_SETUP_RETENTION_DAYS:-30}"
RETENTION_CAP="${NOTCH_SETUP_RETENTION_CAP:-50}"

now_ms() { if [[ -n ${NOTCH_SETUP_NOW_MS:-} ]]; then echo "$NOTCH_SETUP_NOW_MS"; else date +%s%3N; fi; }
now_s() { echo $(( $(now_ms) / 1000 )); }
stamp() { date -u -d "@$(now_s)" +%Y%m%dT%H%M%SZ 2>/dev/null || date -u +%Y%m%dT%H%M%SZ; }
sha() { sha256sum "$1" 2>/dev/null | cut -d' ' -f1; }
canonical_sha() { jq -S -c . "$1" 2>/dev/null | sha256sum | cut -d' ' -f1; }
have() { command -v "$1" >/dev/null 2>&1; }
runnable() { local -n _c=$1; have "${_c[0]}" || [[ -x ${_c[0]} ]]; }

# --- the guard ----------------------------------------------------------------------
#
# Triggered by anything that says "this is a test": NOTCH_HARNESS, or any path or
# command override. Once triggered, a writing verb runs only when the paths are
# sandboxed away from the real ones -- so stubbed commands with real paths, which
# would append to the real bindings.lua, refuse instead.

OVERRIDE_NAMES=(NOTCH_SETUP_SANDBOX NOTCH_SETUP_HOME NOTCH_SETUP_CONFIG_DIR NOTCH_SETUP_TOGGLES_DIR
  NOTCH_SETUP_STATE_DIR NOTCH_SETUP_STATUS NOTCH_SETUP_OMARCHY_PATH NOTCH_SETUP_PLUGINS_DIR
  NOTCH_SETUP_NOTCH_DIR NOTCH_SETUP_HYPRCTL NOTCH_SETUP_OMARCHY_SHELL NOTCH_SETUP_OMARCHY
  NOTCH_SETUP_OMARCHY_VERSION NOTCH_SETUP_TOGGLE_BAR NOTCH_SETUP_QS NOTCH_SETUP_KILL
  NOTCH_SETUP_LUA NOTCH_SETUP_PLUGINS_STATE NOTCH_SETUP_SESSION_LOCKED NOTCH_SETUP_RESTART_SHELL)

guard_triggered() {
  [[ ${NOTCH_HARNESS:-} == 1 ]] && return 0
  local name
  for name in "${OVERRIDE_NAMES[@]}"; do [[ -n ${!name:-} ]] && return 0; done
  return 1
}

# The default a path override replaces, computed from the process's real HOME.
default_for() {
  case $1 in
    config) echo "${XDG_CONFIG_HOME:-$HOME/.config}" ;;
    toggles) echo "$HOME/.local/state/omarchy/toggles" ;;
    state) echo "${XDG_STATE_HOME:-$HOME/.local/state}/$ID/setup" ;;
    status) echo "${XDG_RUNTIME_DIR:-/tmp}/$ID/setup.json" ;;
  esac
}

paths_sandboxed() {
  [[ -n $SANDBOX ]] || { local n; for n in NOTCH_SETUP_CONFIG_DIR NOTCH_SETUP_TOGGLES_DIR NOTCH_SETUP_STATE_DIR NOTCH_SETUP_STATUS; do
    [[ -n ${!n:-} ]] || return 1; done; }
  local pair
  for pair in "config:$CONFIG" "toggles:$TOGGLES" "state:$STATE" "status:$STATUS_DEFAULT"; do
    local kind=${pair%%:*} live=${pair#*:}
    [[ $(realpath -m "$live" 2>/dev/null) == $(realpath -m "$(default_for "$kind")" 2>/dev/null) ]] && return 1
  done
  return 0
}

commands_stubbed() {
  local name
  for name in NOTCH_SETUP_HYPRCTL NOTCH_SETUP_OMARCHY_SHELL NOTCH_SETUP_OMARCHY NOTCH_SETUP_TOGGLE_BAR \
              NOTCH_SETUP_KILL NOTCH_SETUP_SESSION_LOCKED NOTCH_SETUP_RESTART_SHELL; do
    [[ -n ${!name:-} ]] || return 1
  done
  return 0
}

# check_guard <verb kind: write|run>
check_guard() {
  guard_triggered || return 0
  if ! paths_sandboxed; then
    echo "${PROG:-notch-setup}: refusing to write: this looks like a test run, but the paths are the real ones" >&2
    return 2
  fi
  if [[ $1 == run ]] && ! commands_stubbed; then
    echo "${PROG:-notch-setup}: refusing to run: this looks like a test run, but the commands are the real ones" >&2
    return 2
  fi
  return 0
}

# --- shell.json ---------------------------------------------------------------------

json_or() { local text=$1 fallback=$2; jq -e . >/dev/null 2>&1 <<<"$text" && printf '%s' "$text" || printf '%s' "$fallback"; }

shell_config() { cat "$SHELL_JSON" 2>/dev/null; }

# commit_shell <jq program> [jq options...]: what Omarchy's own
# `omarchy-shell-config commit` does -- one jq over shell.json, keys sorted,
# written atomically, then the shell told to read it again -- for the keys the
# shell has no IPC for (cloneSourceRestores). Here, so the paths and the shell
# it tells can be the sandbox's.
commit_shell() {
  local program=$1; shift
  local tmp; tmp=$(mktemp "$SHELL_JSON.XXXXXX") || return 1
  if ! jq -S -e "$@" "$program" "$SHELL_JSON" >"$tmp" 2>/dev/null; then rm -f "$tmp"; return 1; fi
  chmod --reference="$SHELL_JSON" "$tmp" 2>/dev/null
  mv -f "$tmp" "$SHELL_JSON" || { rm -f "$tmp"; return 1; }
  "${OMARCHY_SHELL[@]}" shell reloadConfig >/dev/null 2>&1
  return 0
}

PLUGIN_LIST_CACHE=""
plugin_list() {
  [[ -n $PLUGIN_LIST_CACHE ]] && { printf '%s' "$PLUGIN_LIST_CACHE"; return; }
  local out=""
  runnable OMARCHY && out=$(timeout 15 "${OMARCHY[@]}" plugin list --json 2>/dev/null)
  PLUGIN_LIST_CACHE=$(json_or "$out" "[]")
  printf '%s' "$PLUGIN_LIST_CACHE"
}

# The layout holds objects ({"id": …} plus that widget's own settings), so the
# id is a field, not the entry.
layout_ids() {
  jq -r '[.bar.layout.left // [], .bar.layout.center // [], .bar.layout.right // []]
         | flatten | .[] | if type == "object" then (.id // empty) else . end' "$SHELL_JSON" 2>/dev/null
}

# The ids the notch's plugin catalogue knows, and the names they had before
# (plugins/catalogue.json's `was`), as one compact JSON array.
catalogue_ids() { jq -c '[.plugins[]? | .id, (.was // empty)]' "$NOTCH_DIR/plugins/catalogue.json" 2>/dev/null; }
