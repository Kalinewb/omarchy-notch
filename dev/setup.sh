#!/bin/bash

# The Setup page, as numbers.
#
#   ./dev/setup.sh
#
# Part A drives bin/notch-setup against a sandbox: a fake home with its own
# Hyprland config, shell.json, toggles and plugin list, and a stub for every
# command it can run. Nothing here touches the live session, and the guard is
# tested from the other side too: a half-set-up run must refuse rather than
# write the real config.
#
# Part B opens the page in a throwaway notch pointed at the same sandbox.
#
# The one check that reads the real config (the bind scan) is opt-in with
# NOTCH_CHECK_REAL_SCAN=1, because it executes the user's own Lua. It is
# read-only and asserts that no mtime moved.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0; skipped=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}
skip() { skipped=$((skipped + 1)); echo "  ${DIM}skip  $1${RESET}"; }

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
SCRIPT="$REPO/bin/notch-setup"
sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-setup.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

# --- the sandbox ---------------------------------------------------------------------

HOME_SB="$sb/home"
CONFIG_SB="$HOME_SB/.config"
HYPR_SB="$CONFIG_SB/hypr"
TOGGLES_SB="$HOME_SB/.local/state/omarchy/toggles"
STATE_SB="$HOME_SB/.local/state/kalinewb.notch/setup"
STATUS_SB="$sb/run/kalinewb.notch/setup.json"
OMARCHY_SB="$sb/omarchy"
NOTCH_SB="$sb/notch"
BIN="$sb/bin"
CALLS="$sb/calls"

mkdir -p "$HYPR_SB" "$CONFIG_SB/omarchy/plugins" "$TOGGLES_SB/hypr" "$STATE_SB" "$(dirname "$STATUS_SB")" \
         "$OMARCHY_SB/shell" "$NOTCH_SB/bin" "$NOTCH_SB/dev/upstream" "$BIN" "$sb/fixtures"
cp -r "$SHELL_PATH/default" "$OMARCHY_SB/default"
cp "$REPO/manifest.json" "$NOTCH_SB/manifest.json"
jq '.version = "9.9.9-fixture"' "$NOTCH_SB/manifest.json" >"$NOTCH_SB/manifest.new" && mv "$NOTCH_SB/manifest.new" "$NOTCH_SB/manifest.json"
cp "$REPO/bin/notch-setup" "$NOTCH_SB/bin/notch-setup"
cp "$REPO/bin/notch-setup-binds.lua" "$NOTCH_SB/bin/notch-setup-binds.lua"

# The user's Hyprland config, shaped like the real one.
cat >"$HYPR_SB/hyprland.lua" <<'LUA'
dofile((os.getenv("OMARCHY_PATH") or "/usr/share/omarchy") .. "/default/hypr/bootstrap.lua")
require("default.hypr.omarchy")
require("hypr.bindings")
require("default.hypr.toggles")
LUA
cat >"$HYPR_SB/bindings.lua" <<'LUA'
-- The user's own overrides.
hl.unbind("SUPER + TAB")
o.bind("SUPER + TAB", "Cycle windows", "omarchy-cycle-windows")
LUA
chmod 644 "$HYPR_SB/bindings.lua"

cat >"$CONFIG_SB/omarchy/shell.json" <<'JSON'
{
  "bar": {
    "id": "kalinewb.notch",
    "layout": { "left": [{ "id": "omarchy.menu" }], "center": [], "right": [{ "id": "omarchy.clock" }] },
    "notch": { "openKey": "SUPER + N", "menuKey": "", "replaceMenu": false,
               "hoverPlugins": [], "hiddenPlugins": [], "windowsToTop": false }
  }
}
JSON

# Fixture answers the stubs read.
echo '[]' >"$sb/fixtures/configerrors.json"
echo '[]' >"$sb/fixtures/binds.json"
cat >"$sb/fixtures/plugins.json" <<'JSON'
[{"id": "kalinewb.notch", "enabled": true, "active": true, "kinds": ["bar"]},
 {"id": "omarchy.menu", "enabled": true, "active": true, "kinds": ["bar-widget", "menu"]},
 {"id": "omarchy.clock", "enabled": true, "active": true, "kinds": ["bar-widget"]}]
JSON
echo '' >"$sb/fixtures/qs-list.txt"
echo '{"entries": []}' >"$sb/fixtures/plugins-state.json"

# Every command the script can run, recorded rather than run.
recorder() { # recorder <name> <body>
  cat >"$BIN/$1" <<EOF
#!/bin/bash
printf '%s\n' "$1 \$*" >>"$CALLS"
$2
EOF
  chmod +x "$BIN/$1"
}
recorder hyprctl 'case "$1" in
  binds) cat "'"$sb"'/fixtures/binds.json" ;;
  configerrors) cat "'"$sb"'/fixtures/configerrors.json" ;;
  reload) echo "[]" > "'"$sb"'/fixtures/binds.json" ;;
esac
exit 0'
recorder omarchy-shell '[[ -n ${SB_SLOW:-} && $* == *$SB_SLOW* ]] && sleep 3
[[ $* == *reloadConfig* ]] && { [[ ${SB_RELOAD_FAILS:-} == 1 ]] || echo ok; }
exit 0'
recorder omarchy 'case "$*" in
  "plugin list --json") cat "'"$sb"'/fixtures/plugins.json" ;;
esac
exit 0'
recorder omarchy-version 'echo 4.0.3-fixture'
recorder omarchy-toggle-bar '[[ $1 == off ]] && rm -f "'"$TOGGLES_SB"'/bar-off"
[[ $1 == on ]] && : > "'"$TOGGLES_SB"'/bar-off"
exit 0'
recorder qs 'cat "'"$sb"'/fixtures/qs-list.txt"'
recorder fakekill 'exit 0'
recorder session-locked 'exit ${SB_LOCKED:-1}'
recorder restart-shell 'exit 0'
recorder plugins-state 'cat "'"$sb"'/fixtures/plugins-state.json"'

env_common=(
  NOTCH_SETUP_HOME="$HOME_SB" NOTCH_SETUP_CONFIG_DIR="$CONFIG_SB" NOTCH_SETUP_TOGGLES_DIR="$TOGGLES_SB"
  NOTCH_SETUP_STATE_DIR="$STATE_SB" NOTCH_SETUP_STATUS="$STATUS_SB" NOTCH_SETUP_OMARCHY_PATH="$OMARCHY_SB"
  NOTCH_SETUP_PLUGINS_DIR="$CONFIG_SB/omarchy/plugins" NOTCH_SETUP_NOTCH_DIR="$NOTCH_SB"
  NOTCH_SETUP_HYPRCTL="$BIN/hyprctl" NOTCH_SETUP_OMARCHY_SHELL="$BIN/omarchy-shell"
  NOTCH_SETUP_OMARCHY="$BIN/omarchy" NOTCH_SETUP_OMARCHY_VERSION="$BIN/omarchy-version"
  NOTCH_SETUP_TOGGLE_BAR="$BIN/omarchy-toggle-bar" NOTCH_SETUP_QS="$BIN/qs"
  NOTCH_SETUP_KILL="$BIN/fakekill" NOTCH_SETUP_SESSION_LOCKED="$BIN/session-locked"
  NOTCH_SETUP_RESTART_SHELL="$BIN/restart-shell" NOTCH_SETUP_PLUGINS_STATE="$BIN/plugins-state"
)
setup() { env "${env_common[@]}" "$@"; }
run_setup() { setup "$SCRIPT" "$@"; }
calls() { cat "$CALLS" 2>/dev/null; }
reset_calls() { : >"$CALLS"; }
tree_hash() { find "$1" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | cut -d' ' -f1; }

echo "${BOLD}bin/notch-setup${RESET}  ${DIM}sandbox $sb${RESET}"

# --- detection -----------------------------------------------------------------------

reset_calls
report=$(run_setup detect --json)
ids=$(jq -r '[.points[].id] | join(" ")' <<<"$report")
expected_ids="bar-off notch-not-bar notch-failed hypr-config-errors menu-replace-companion menu-keys-bypass notch-key-collision stale-notch-binds layout-missing-plugin layout-empty-widget settings-stale-ids plugin-face plugin-profiles profiles-binds-path stray-instances stray-backups upstream-drift layer-rules notch-not-git"
check "1. detect reports the 20 points in order, schema 1" "1 $expected_ids" "$(jq -r .schema <<<"$report") $ids"
check "1b. a healthy fixture needs no attention" "0" "$(jq '.counts.fix + .counts.action + .counts.warn' <<<"$report")"

before=$(tree_hash "$HOME_SB"); before_count=$(find "$HOME_SB" -type f | wc -l)
run_setup detect --json >/dev/null
check "2. detect changes nothing" "$before $before_count" "$(tree_hash "$HOME_SB") $(find "$HOME_SB" -type f | wc -l)"

# A bind that reaches the notch's menu directly.
bypass_block() {
  cat >>"$HYPR_SB/bindings.lua" <<'LUA'
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-shell -q notch menu root")
hl.unbind("SUPER + SHIFT + code:201")
o.bind("SUPER + SHIFT + code:201", "Omarchy menu", "omarchy-shell -q notch menu root")
LUA
}
bypass_block
jq '.bar.notch.replaceMenu = true' "$CONFIG_SB/omarchy/shell.json" >"$sb/t" && mv "$sb/t" "$CONFIG_SB/omarchy/shell.json"
jq '. + [{"id": "kalinewb.notch-menu", "enabled": true, "active": true, "kinds": ["menu"]}]' \
  "$sb/fixtures/plugins.json" >"$sb/t" && mv "$sb/t" "$sb/fixtures/plugins.json"
p=$(run_setup detect --json --only menu-keys-bypass | jq -c '.points[0]')
check "3. a bypass bind is a fix, named by key and source" "fix SUPER + SPACE bindings.lua" \
  "$(jq -r '.severity' <<<"$p") $(jq -r '.items[0].arg' <<<"$p") $(jq -r '.items[0].source' <<<"$p" | xargs basename)"
check "4. the keycode bind is found too" "2" "$(jq '.items | length' <<<"$p")"
check "5. the menu family is read out of Omarchy's own utilities.lua" "12" \
  "$(grep -cP '^o\.bind\("\K[^"]+(?=".*"omarchy-menu toggle)' "$OMARCHY_SB/default/hypr/bindings/utilities.lua")"

# --- the fix pipeline ------------------------------------------------------------------

pre_hash=$(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1)
pre_mode=$(stat -c %a "$HYPR_SB/bindings.lua")
cp "$HYPR_SB/bindings.lua" "$sb/bindings.pre"
reset_calls
rc=0; run_setup fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
snap=$(run_setup snapshots --json | jq -r '.[0].name')
snapdir="$STATE_SB/snapshots/$snap"
check "6. fix succeeds, and the snapshot holds the file as it was" \
  "0 700 true $pre_hash $pre_mode 0" \
  "$rc $(stat -c %a "$snapdir" 2>/dev/null) $(jq -r '.files[0].existed' "$snapdir/meta.json" 2>/dev/null) $(jq -r '.files[0].sha256' "$snapdir/meta.json" 2>/dev/null) $(jq -r '.files[0].mode' "$snapdir/meta.json" 2>/dev/null) $(cmp -s "$snapdir/files/0" "$sb/bindings.pre"; echo $?)"
check "7. the block is written once, the file still parses, and the point is clear" "1 1 0 ok" \
  "$(grep -c -- '-- >>> kalinewb.notch setup: menu-keys-bypass' "$HYPR_SB/bindings.lua") $(grep -c -- '-- <<< kalinewb.notch setup' "$HYPR_SB/bindings.lua") $(F="$HYPR_SB/bindings.lua" lua -e 'assert(loadfile(os.getenv("F")))' >/dev/null 2>&1; echo $?) $(run_setup detect --json --only menu-keys-bypass | jq -r '.points[0].severity')"
check "8. the restored binds are Omarchy's own, with its description" "1 1" \
  "$(grep -c 'o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-menu toggle")' "$HYPR_SB/bindings.lua") $(grep -c 'o.bind("SUPER + SHIFT + code:201", "Omarchy menu", "omarchy-menu toggle root")' "$HYPR_SB/bindings.lua")"
check "9. errors are checked before the write, then Hyprland is reloaded and checked again" "configerrors reload configerrors" \
  "$(calls | grep '^hyprctl' | awk '{print $2}' | uniq | paste -sd' ')"
check "10. the recorded after-hash matches the live file, and no temp file is left behind" "$(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1) 0" \
  "$(jq -r '.files[0].after.sha256' "$snapdir/meta.json") $(find "$HYPR_SB" -name '.notch-setup.*' | wc -l)"
check "10b. the snapshot is verified" "verified" "$(jq -r .state "$snapdir/meta.json")"

# --- restore ---------------------------------------------------------------------------

rc=0; run_setup restore "$snap" >/dev/null 2>&1 || rc=$?
check "13. restore puts the file back byte for byte, with its mode" "0 $pre_hash $pre_mode restored" \
  "$rc $(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1) $(stat -c %a "$HYPR_SB/bindings.lua") $(jq -r .state "$snapdir/meta.json")"

# Conflict: the user edited the file after the fix.
run_setup fix menu-keys-bypass >/dev/null 2>&1
snap=$(run_setup snapshots --json | jq -r '.[0].name')
echo '-- a line the user added' >>"$HYPR_SB/bindings.lua"
after_edit=$(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1)
rc=0; run_setup restore "$snap" >/dev/null 2>&1 || rc=$?
check "14. a file changed after the fix is a conflict, and nothing is written" "3 $after_edit 1" \
  "$rc $(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1) $(jq -r '.conflicts | length' "$STATUS_SB")"

rc=0; run_setup restore "$snap" --block-only >/dev/null 2>&1 || rc=$?
check "15. --block-only removes the notch's block and keeps the user's line" "0 0 1" \
  "$rc $(grep -c -- '-- >>> kalinewb.notch setup' "$HYPR_SB/bindings.lua") $(grep -c -- '-- a line the user added' "$HYPR_SB/bindings.lua")"

# --force, over a conflict.
sed -i '/a line the user added/d' "$HYPR_SB/bindings.lua"
run_setup fix menu-keys-bypass >/dev/null 2>&1
snap=$(run_setup snapshots --json | jq -r '.[0].name')
echo '-- another user line' >>"$HYPR_SB/bindings.lua"
before_snaps=$(run_setup snapshots --json | jq 'length')
rc=0; run_setup restore "$snap" --force >/dev/null 2>&1 || rc=$?
check "16. --force snapshots the current state first, then restores" "0 1 $((before_snaps + 1))" \
  "$rc $(run_setup snapshots --json | jq '[.[] | select(.point == "restore")] | length') $(run_setup snapshots --json | jq 'length')"

# A fix whose file didn't exist before.
: >"$TOGGLES_SB/bar-off"
rc=0; run_setup fix bar-off >/dev/null 2>&1 || rc=$?
snap_bar=$(run_setup snapshots --json | jq -r '[.[] | select(.point == "bar-off")][0].name')
check "18. bar-off: the flag is removed, and the snapshot remembers it was there" "0 false true 0 false" \
  "$rc $([[ -f $TOGGLES_SB/bar-off ]] && echo true || echo false) $(jq -r '.files[0].existed' "$STATE_SB/snapshots/$snap_bar/meta.json") $(jq -r '.files[0].size' "$STATE_SB/snapshots/$snap_bar/meta.json") $(jq -r '.files[0].after.existed' "$STATE_SB/snapshots/$snap_bar/meta.json")"
reset_calls
run_setup restore "$snap_bar" >/dev/null 2>&1
check "18b. restore brings the flag back, empty" "true 0" \
  "$([[ -f $TOGGLES_SB/bar-off ]] && echo true || echo false) $(stat -c %s "$TOGGLES_SB/bar-off" 2>/dev/null)"
rm -f "$TOGGLES_SB/bar-off"

# --- fault injection ---------------------------------------------------------------------

pre_hash=$(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1)
echo '["a config error"]' >"$sb/fixtures/configerrors.json"
rc=0; NOTCH_SETUP_FAIL_AT=verify run_setup fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
check "11b. a fix refuses while Hyprland already reports errors" "2 $pre_hash" \
  "$rc $(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1)"
echo '[]' >"$sb/fixtures/configerrors.json"

rc=0; NOTCH_SETUP_FAIL_AT=verify run_setup fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
snap_rb=$(run_setup snapshots --json | jq -r '.[0].name')
check "11. verification fails: rolled back, the file is as it was" "1 $pre_hash rolled-back rolled-back" \
  "$rc $(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1) $(jq -r .state "$STATE_SB/snapshots/$snap_rb/meta.json") $(jq -r .phase "$STATUS_SB")"

rc=0; NOTCH_SETUP_FAIL_AT=write run_setup fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
check "12. a write that fails leaves the file untouched and no applied snapshot" "1 $pre_hash 0" \
  "$rc $(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1) $(run_setup snapshots --json | jq '[.[] | select(.state == "applied")] | length')"

# --- other points ------------------------------------------------------------------------

cat >"$sb/fixtures/binds.json" <<'JSON'
[{"description": "Notch: open [keys.sh]", "key": "N", "modmask": 64},
 {"description": "Notch: settings [keys.sh]", "key": "S", "modmask": 64}]
JSON
p=$(run_setup detect --json --only stale-notch-binds | jq -c '.points[0]')
reset_calls
rc=0; run_setup fix stale-notch-binds >/dev/null 2>&1 || rc=$?
check "23. tagged leftover binds are found, and the fix reloads without a snapshot" "fix 2 0 1" \
  "$(jq -r .severity <<<"$p") $(jq '.items | length' <<<"$p") $rc $(calls | grep -c '^hyprctl reload')"
echo '[]' >"$sb/fixtures/binds.json"

# notch-key-collision
jq '.bar.notch.menuKey = "SUPER + SPACE"' "$CONFIG_SB/omarchy/shell.json" >"$sb/t" && mv "$sb/t" "$CONFIG_SB/omarchy/shell.json"
p=$(run_setup detect --json --only notch-key-collision | jq -c '.points[0]')
reset_calls
rc=0; run_setup fix notch-key-collision --arg menuKey >/dev/null 2>&1 || rc=$?
snap_key=$(run_setup snapshots --json | jq -r '[.[] | select(.point == "notch-key-collision")][0].name')
check "19. a notch key on a menu key is found; the fix clears it and remembers the old one" \
  "fix 1 omarchy-shell notch set menuKey \"\" \"SUPER + SPACE\"" \
  "$(jq -r .severity <<<"$p") $(jq -r 'if .severity == "fix" then 1 else 0 end' <<<"$p") $(calls | grep '^omarchy-shell notch set' | head -1) $(jq -r '.undo[0][4]' "$STATE_SB/snapshots/$snap_key/meta.json" 2>/dev/null)"
jq '.bar.notch.menuKey = ""' "$CONFIG_SB/omarchy/shell.json" >"$sb/t" && mv "$sb/t" "$CONFIG_SB/omarchy/shell.json"

# layout-missing-plugin
jq '.bar.layout.right += [{"id": "ghost.widget"}]' "$CONFIG_SB/omarchy/shell.json" >"$sb/t" && mv "$sb/t" "$CONFIG_SB/omarchy/shell.json"
reset_calls
rc=0; run_setup fix layout-missing-plugin --arg ghost.widget >/dev/null 2>&1 || rc=$?
snap_layout=$(run_setup snapshots --json | jq -r '[.[] | select(.point == "layout-missing-plugin")][0].name')
check "20. a widget that isn't installed is disabled, and where it sat is recorded" \
  "omarchy plugin disable ghost.widget right 1" \
  "$(calls | grep '^omarchy plugin disable' | head -1) $(jq -r '.context.layoutPlacement.section' "$STATE_SB/snapshots/$snap_layout/meta.json" 2>/dev/null) $(jq -r '.context.layoutPlacement.index' "$STATE_SB/snapshots/$snap_layout/meta.json" 2>/dev/null)"
jq 'del(.bar.layout.right[] | select(.id == "ghost.widget"))' "$CONFIG_SB/omarchy/shell.json" >"$sb/t" && mv "$sb/t" "$CONFIG_SB/omarchy/shell.json"

# notch-not-bar
jq '.bar.id = "omarchy.bar"' "$CONFIG_SB/omarchy/shell.json" >"$sb/t" && mv "$sb/t" "$CONFIG_SB/omarchy/shell.json"
mkdir -p "$CONFIG_SB/omarchy/plugins/kalinewb.notch"
p=$(run_setup detect --json --only notch-not-bar | jq -r '.points[0].severity')
reset_calls
run_setup fix notch-not-bar >/dev/null 2>&1
snap_bar_id=$(run_setup snapshots --json | jq -r '[.[] | select(.point == "notch-not-bar")][0].name')
check "21. another active bar is found; the fix enables the notch and undo names the old bar" \
  "fix omarchy plugin enable kalinewb.notch omarchy.bar" \
  "$p $(calls | grep '^omarchy plugin enable' | head -1) $(jq -r '.undo[0][3]' "$STATE_SB/snapshots/$snap_bar_id/meta.json" 2>/dev/null)"
jq '.bar.id = "kalinewb.notch"' "$CONFIG_SB/omarchy/shell.json" >"$sb/t" && mv "$sb/t" "$CONFIG_SB/omarchy/shell.json"

# stray-instances
printf '  1234  %s/harness/shell.qml\n  5678  %s/shell/shell.qml\n' "/tmp/fake" "$OMARCHY_SB" >"$sb/fixtures/qs-list.txt"
mkdir -p "$sb/proc/1234"
printf 'NOTCH_HARNESS=1\0OTHER=2\0' >"$sb/proc/1234/environ"
reset_calls
p=$(NOTCH_SETUP_PROC="$sb/proc" run_setup detect --json --only stray-instances | jq -c '.points[0]')
NOTCH_SETUP_PROC="$sb/proc" run_setup fix stray-instances >/dev/null 2>&1
check "24. only the test shell under /tmp with NOTCH_HARNESS=1 is killed" "fix 1 fakekill 1234" \
  "$(jq -r .severity <<<"$p") $(jq '.items | length' <<<"$p") $(calls | grep '^fakekill' | head -1)"
echo '' >"$sb/fixtures/qs-list.txt"

# stray-backups
: >"$HYPR_SB/bindings.lua.bak.1700000001"
: >"$HYPR_SB/looknfeel.lua.bak.1700000002"
echo '{}' >"$CONFIG_SB/omarchy/shell.json.bak.1700000003"
chmod 600 "$HYPR_SB/bindings.lua.bak.1700000001"
rc=0; run_setup fix stray-backups >/dev/null 2>&1 || rc=$?
snap_bak=$(run_setup snapshots --json | jq -r '[.[] | select(.point == "stray-backups")][0].name')
check "25. backups are moved into the snapshot, not deleted" "0 3 0" \
  "$rc $(jq '.files | length' "$STATE_SB/snapshots/$snap_bak/meta.json") $(find "$HYPR_SB" "$CONFIG_SB/omarchy" -maxdepth 1 -name '*.bak.*' | wc -l)"
run_setup restore "$snap_bak" >/dev/null 2>&1
check "25b. restore puts all three back, with their modes" "3 600" \
  "$(find "$HYPR_SB" "$CONFIG_SB/omarchy" -maxdepth 1 -name '*.bak.*' | wc -l) $(stat -c %a "$HYPR_SB/bindings.lua.bak.1700000001" 2>/dev/null)"
rm -f "$HYPR_SB"/*.bak.* "$CONFIG_SB/omarchy"/*.bak.*

# upstream-drift: the sandbox gets the real files, then one of them moves.
cp -r "$REPO/dev/upstream" "$NOTCH_SB/dev/"
while read -r up; do
  mkdir -p "$OMARCHY_SB/shell/$(dirname "$up")"
  cp "$SHELL_PATH/shell/$up" "$OMARCHY_SB/shell/$up" 2>/dev/null
done < <(jq -r '.files | keys[]' "$NOTCH_SB/dev/upstream/upstream.json")
first_file=$(jq -r '.files | to_entries[0].key' "$NOTCH_SB/dev/upstream/upstream.json")
echo "changed upstream" >"$OMARCHY_SB/shell/$first_file"
p=$(run_setup detect --json --only upstream-drift | jq -c '.points[0]')
check "26. a changed upstream file is listed, and the version mismatch is in the detail" "info $first_file 1" \
  "$(jq -r .severity <<<"$p") $(jq -r '.items[0].arg' <<<"$p") $(jq -r '[.detail[] | select(test("this machine runs"))] | length' <<<"$p")"

# --- safety ------------------------------------------------------------------------------

mkdir -p "$STATE_SB/lock" && echo $$ >"$STATE_SB/lock/pid"
before_snaps=$(run_setup snapshots --json | jq 'length')
rc=0; run_setup fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
check "27. a second job while one holds the lock is refused, and takes no snapshot" "5 $before_snaps" \
  "$rc $(run_setup snapshots --json | jq 'length')"
rm -rf "$STATE_SB/lock"

reset_calls
rc=0; NOTCH_HARNESS=1 NOTCH_SETUP_HOME="$HOME_SB" "$SCRIPT" fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
check "28. a test run without a path sandbox refuses and runs nothing" "2 0" "$rc $(calls | wc -l)"

mkdir -p "$STATE_SB/snapshots/.20260101T000000Z-test.partial"
echo '{"createdAt": 1}' >"$STATE_SB/snapshots/.20260101T000000Z-test.partial/meta.json"
check "29. a partial snapshot is never listed" "0" \
  "$(run_setup snapshots --json | jq '[.[] | select(.name | test("test"))] | length')"

# Retention.
gen="$STATE_SB/snapshots"
now_ms=$(date +%s%3N)
old=$(( now_ms - 40 * 86400000 ))
for i in $(seq 1 12); do
  for point in alpha beta; do
    dir="$gen/2026010${i}T00000${i}Z-$point-$i"
    mkdir -p "$dir/files"
    jq -nc --arg name "$(basename "$dir")" --arg point "$point" --argjson at "$((old + i))" \
      '{schema: 1, name: $name, point: $point, arg: "", kind: "block", title: "t", createdAt: $at,
        state: "restored", history: [], reload: [], undo: [], block: null, context: {}, files: []}' >"$dir/meta.json"
  done
done
before_prune=$(run_setup snapshots --json | jq 'length')
run_setup prune >/dev/null 2>&1
kept=$(run_setup snapshots --json | jq 'length')
check "30. prune drops old restored snapshots, keeps the newest of each point, and stays under the cap" \
  "true true true" \
  "$([[ $kept -lt $before_prune ]] && echo true || echo false) $([[ $kept -le 50 ]] && echo true || echo false) $(run_setup snapshots --json | jq '([.[] | select(.point == "alpha")] | length) >= 1')"
check "30b. no partial directory survives an hour" "0" "$(find "$gen" -maxdepth 1 -name '.*.partial' | wc -l)"

one=$(run_setup snapshots --json | jq -r '.[0].name')
run_setup forget "$one" >/dev/null 2>&1
check "31. forget removes exactly that one" "false" "$([[ -d $gen/$one ]] && echo true || echo false)"

# The self-copy, and where it looks for the notch afterwards.
check "35. the job runs from its own copy, and still reads the real notch folder" "true 9.9.9-fixture" \
  "$([[ -f $STATE_SB/run/notch-setup ]] && echo true || echo false) $(jq -r '.notchVersion' <<<"$(run_setup detect --json --only bar-off)")"

# The guard, from the other side: a fake home that must survive a botched test run.
fake="$sb/fakehome"
mkdir -p "$fake/.config/hypr"
cp "$HYPR_SB/hyprland.lua" "$fake/.config/hypr/"
cat "$sb/bindings.pre" >"$fake/.config/hypr/bindings.lua"
fake_hash=$(tree_hash "$fake"); fake_count=$(find "$fake" -type f | wc -l)
reset_calls
rc=0
env HOME="$fake" XDG_CONFIG_HOME="$fake/.config" XDG_STATE_HOME="$fake/.local/state" XDG_RUNTIME_DIR="$fake/run" \
  NOTCH_HARNESS=1 NOTCH_SETUP_HYPRCTL="$BIN/hyprctl" NOTCH_SETUP_OMARCHY_SHELL="$BIN/omarchy-shell" \
  NOTCH_SETUP_OMARCHY="$BIN/omarchy" NOTCH_SETUP_TOGGLE_BAR="$BIN/omarchy-toggle-bar" \
  NOTCH_SETUP_KILL="$BIN/fakekill" NOTCH_SETUP_SESSION_LOCKED="$BIN/session-locked" \
  NOTCH_SETUP_RESTART_SHELL="$BIN/restart-shell" \
  "$SCRIPT" fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
check "37. stubbed commands with real paths: refused, nothing run, nothing touched" "2 0 $fake_hash $fake_count" \
  "$rc $(calls | wc -l) $(tree_hash "$fake") $(find "$fake" -type f | wc -l)"

mkdir -p "$fake/run/kalinewb.notch" "$fake/.local/state/kalinewb.notch/setup/snapshots/keepme"
echo '{"seen": false}' >"$fake/run/kalinewb.notch/setup.json"
rc_ack=0; env HOME="$fake" XDG_RUNTIME_DIR="$fake/run" NOTCH_HARNESS=1 "$SCRIPT" ack "$fake/run/kalinewb.notch/setup.json" >/dev/null 2>&1 || rc_ack=$?
rc_forget=0; env HOME="$fake" XDG_STATE_HOME="$fake/.local/state" NOTCH_HARNESS=1 "$SCRIPT" forget keepme >/dev/null 2>&1 || rc_forget=$?
rc_prune=0; env HOME="$fake" XDG_STATE_HOME="$fake/.local/state" NOTCH_HARNESS=1 "$SCRIPT" prune >/dev/null 2>&1 || rc_prune=$?
check "38. ack, forget and prune refuse the same way" "2 2 2 false true" \
  "$rc_ack $rc_forget $rc_prune $(jq -r .seen "$fake/run/kalinewb.notch/setup.json") $([[ -d $fake/.local/state/kalinewb.notch/setup/snapshots/keepme ]] && echo true || echo false)"

# --reopen: the flag only survives when the job really did destroy the notch.
reset_calls
rc=0; run_setup fix layout-empty-widget --reopen >/dev/null 2>&1 || rc=$?
check "36. a restart job asks for the page to come back, and says so from the first write" "0 true restart-shell" \
  "$rc $(jq -r .reopen "$STATUS_SB") $(calls | grep -c '^restart-shell' >/dev/null && echo restart-shell)"
run_setup fix layout-empty-widget >/dev/null 2>&1
check "36b. without --reopen it doesn't" "false" "$(jq -r .reopen "$STATUS_SB")"
rc=0; SB_LOCKED=0 run_setup fix layout-empty-widget --reopen >/dev/null 2>&1 || rc=$?
check "36c. a locked session refuses, and nothing will reopen" "2 false" "$rc $(jq -r .reopen "$STATUS_SB")"

# The menu points, against the companion's state.
jq 'map(select(.id != "kalinewb.notch-menu"))' "$sb/fixtures/plugins.json" >"$sb/t" && mv "$sb/t" "$sb/fixtures/plugins.json"
p=$(run_setup detect --json --only menu-replace-companion | jq -r '.points[0].severity')
q=$(run_setup detect --json --only menu-keys-bypass | jq -c '.points[0]')
rc=0; run_setup fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
check "33. with the companion missing, the keys are information, not a fix" "action info null 4" \
  "$p $(jq -r .severity <<<"$q") $(jq -r '.fix' <<<"$q") $rc"

jq '. + [{"id": "kalinewb.notch-menu", "enabled": false, "active": false, "kinds": ["menu"]}]' \
  "$sb/fixtures/plugins.json" >"$sb/t" && mv "$sb/t" "$sb/fixtures/plugins.json"
reset_calls
p=$(run_setup detect --json --only menu-replace-companion | jq -r '.points[0].severity')
run_setup fix menu-replace-companion >/dev/null 2>&1
check "58. an installed but disabled companion is enabled by the fix" "fix omarchy plugin enable kalinewb.notch-menu" \
  "$p $(calls | grep '^omarchy plugin enable' | head -1)"

# A bypass bind that loads after bindings.lua can't be fixed from bindings.lua.
jq 'map(select(.id != "kalinewb.notch-menu")) + [{"id": "kalinewb.notch-menu", "enabled": true, "active": true, "kinds": ["menu"]}]' \
  "$sb/fixtures/plugins.json" >"$sb/t" && mv "$sb/t" "$sb/fixtures/plugins.json"
cat "$sb/bindings.pre" >"$HYPR_SB/bindings.lua"
cat >"$TOGGLES_SB/hypr/zz-menu.lua" <<'LUA'
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "Omarchy menu", "omarchy-shell -q notch menu root")
LUA
late_hash=$(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1)
reset_calls
p=$(run_setup detect --json --only menu-keys-bypass | jq -c '.points[0]')
rc=0; run_setup fix menu-keys-bypass >/dev/null 2>&1 || rc=$?
check "34. a bind made after bindings.lua is named, refused, and nothing is written" "zz-menu.lua true 2 0 $late_hash" \
  "$(jq -r '.items[0].source' <<<"$p" | xargs basename) $(jq -r '(.fix.disabledReason // "") != ""' <<<"$p") $rc $(calls | grep -c '^hyprctl reload') $(sha256sum "$HYPR_SB/bindings.lua" | cut -d' ' -f1)"
rm -f "$TOGGLES_SB/hypr/zz-menu.lua"

# The real config, read-only, only when asked for.
if [[ ${NOTCH_CHECK_REAL_SCAN:-} == 1 ]]; then
  mt_before=$(stat -c '%Y %n' "$HOME/.config/hypr"/*.lua 2>/dev/null | sha256sum)
  real=$(lua "$REPO/bin/notch-setup-binds.lua" 2>/dev/null)
  mt_after=$(stat -c '%Y %n' "$HOME/.config/hypr"/*.lua 2>/dev/null | sha256sum)
  check "32. the real config scans read-only, and SUPER + SPACE is there" "1 same" \
    "$(jq -s '[.[] | select(.bind) | .bind | select(.modmask == 64 and .key == "SPACE")] | length' <<<"$real") $([[ $mt_before == "$mt_after" ]] && echo same || echo CHANGED)"
else
  skip "32. the real config scan (set NOTCH_CHECK_REAL_SCAN=1 to run it)"
fi


# ---------------------------------------------------------------------------
# B. The page, in a throwaway notch pointed at the same sandbox.
# ---------------------------------------------------------------------------

echo; echo "${BOLD}The Setup page${RESET}"

root_dir="$sb/shell"
mkdir -p "$root_dir"
ln -s "$SHELL_PATH/shell/Commons" "$root_dir/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root_dir/Ui"
ln -s "$SHELL_PATH/shell/services" "$root_dir/services"
ln -s "$REPO" "$root_dir/notch"
cp "$REPO/dev/harness/shell.qml" "$root_dir/shell.qml"
ipc() { quickshell ipc -p "$root_dir" call notch "$@" 2>/dev/null; }

start_notch() { # start_notch [extra env...]
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_FORCE_SETUP=1 \
    NOTCH_SETUP_DETACH=setsid NOTCH_SETUP_IPC_ACTIONS=1 "${env_common[@]}" \
    NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"bottomRadius":8}' "$@" \
    quickshell -p "$root_dir" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  sleep 0.6
}
stop_notch() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

# Two points the fixture detects: a bypass bind (fix) and old backups (fix).
cat "$sb/bindings.pre" >"$HYPR_SB/bindings.lua"
bypass_block
: >"$HYPR_SB/looknfeel.lua.bak.1700000009"
rm -rf "$STATE_SB/snapshots" "$STATUS_SB"

start_notch
ipc setup check "" >/dev/null
for _ in $(seq 1 60); do sleep 0.2; [[ $(ipc setup status "" | jq -r '.checking') == false ]] && break; done
status=$(ipc setup status "")
check "39. the page's issue count matches what detection found" "true" \
  "$(jq -r '.issueCount == ((.counts.fix // 0) + (.counts.action // 0) + (.counts.warn // 0)) and .issueCount > 0' <<<"$status")"

ipc view setup >/dev/null; sleep 0.9
g=$(ipc geometry)
check "40. view setup opens the page, top edge on the screen edge, square top corners" \
  "expanded true true 0 0" \
  "$(jq -r '.state' <<<"$g") $(jq -r '.setup.open' <<<"$g") $(jq -r '.setup.height > 32 and (.target.height == .setup.height)' <<<"$g") $(jq -r '.bar.y' <<<"$g") $(jq -r '.radii.topLeft' <<<"$g")"

d=$(ipc design)
check "43. every rounded thing on the page uses the notch's radius" "0" "$(python3 -c '
import json,sys
d=json.loads(sys.argv[1]); r=d["radius"]
bad=[i for i in d.get("setup", []) if i["drawn"] and not i["gradient"] and i["width"]>2 and i["height"]>2
     and abs(i["radius"]-max(0,min(r,i["height"]/2,i["width"]/2)))>0.01]
print(len(bad))' "$d")"

# Settings -> Setup, with no pass through rest.
ipc view settings >/dev/null; sleep 0.8
( for _ in $(seq 1 12); do ipc geometry | jq -rc '"\(.target.height) \(.setup.open)"'; done ) >"$sb/samples" &
sampler=$!
ipc view setup >/dev/null
wait "$sampler" 2>/dev/null
samples=$(cat "$sb/samples")
check "42. going from the settings to Setup never passes through the resting height" "0" \
  "$(grep -c '^32 ' <<<"$samples")"

# A fix, from the page.
snaps_before=$(run_setup snapshots --json | jq 'length')
ipc setup fix stray-backups >/dev/null
for _ in $(seq 1 60); do sleep 0.2; [[ $(ipc setup status "" | jq -r '.job.phase') == done ]] && break; done
job=$(ipc setup status "" | jq -c '.job')
check "45. a Fix from the page runs, finishes, and leaves one more snapshot" "done $((snaps_before + 1))" \
  "$(jq -r .phase <<<"$job") $(run_setup snapshots --json | jq 'length')"

# Undo it again.
snap=$(run_setup snapshots --json | jq -r '[.[] | select(.point == "stray-backups")][0].name')
ipc setup restore "$snap" >/dev/null
for _ in $(seq 1 60); do sleep 0.2; [[ $(ipc setup status "" | jq -r '.job.phase') == done ]] && break; done
check "46. Undo puts the files back" "done true" \
  "$(ipc setup status "" | jq -r '.job.phase') $([[ -f $HYPR_SB/looknfeel.lua.bak.1700000009 ]] && echo true || echo false)"

# Escape and the open keybind both leave the page.
ipc view setup >/dev/null; sleep 0.8
ipc toggle >/dev/null; sleep 1.0
g=$(ipc geometry)
check "55. the open keybind closes Setup rather than jumping to the widgets" "compact false none" \
  "$(jq -r .state <<<"$g") $(jq -r .setup.open <<<"$g") $(jq -r .panel.keyboard <<<"$g")"

check "53. Setup is not a contract built-in" "0" \
  "$(ipc contract 2>/dev/null | jq '[.builtins[]? | select(. == "notch.setup")] | length' 2>/dev/null || echo 0)"
stop_notch

# A notch that doesn't do Setup: no status file read, no job, and it says so.
rm -rf "$STATE_SB/lock"
jq '.reopen = true | .seen = false | .startedAt = (now * 1000 | floor)' "$STATUS_SB" >"$sb/t" 2>/dev/null && mv "$sb/t" "$STATUS_SB"
status_hash=$(sha256sum "$STATUS_SB" | cut -d' ' -f1)
env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 "${env_common[@]}" \
  NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' quickshell -p "$root_dir" -n >>"$sb/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 1.2
check "52. a notch without NOTCH_FORCE_SETUP reads nothing, starts nothing, and doesn't reopen" \
  "false compact false $status_hash" \
  "$(ipc setup status "" | jq -r .enabled) $(ipc geometry | jq -r .state) $(ipc geometry | jq -r .setup.open) $(sha256sum "$STATUS_SB" | cut -d' ' -f1)"
check "51. …and its fix verb is refused" "ipc" "$(ipc setup fix stray-backups | jq -r '.refused // ""')"
stop_notch

check "54. no QML errors in any of it" "none" \
  "$(grep -E '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-80 || true)$(grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"

echo
if (( failures )); then
  echo "${RED}$failures of $checks checks failed${RESET}${skipped:+ ${DIM}($skipped skipped)${RESET}}"
  exit 1
fi
echo "${GREEN}$checks checks pass${RESET}${skipped:+ ${DIM}($skipped skipped)${RESET}}"
