#!/bin/bash

# Installing the user's plugins from the notch, as numbers.
#
#   ./dev/plugins.sh
#
# Nothing here touches the live plugins folder, the live shell or GitHub. A
# sandbox holds bare "GitHub" repos built from dev/fixtures/plugins, a plugins
# folder under a sandbox HOME, a scratch folder, and stubs for omarchy-shell,
# hyprctl, the session-lock check and the terminal. The real upstream `omarchy
# plugin add/update/enable/list` run against it, through a stand-in that logs
# each call.
#
# A. The shipped catalogue: its three entries, their full-SHA pins and the
#    versions at them, the deny list, suite.json in step with it; invalid
#    catalogues are refused.
# B. Guards: denied and unknown ids (an old name too), URLs and paths as ids,
#    every sandbox hook without both partners, the job lock (live, half made,
#    stale), the notch update's lock, a locked session, the plugins folder
#    ignoring XDG_CONFIG_HOME, and ack only ever marking its own finished job.
# C. bin/notch-plugins against the sandbox, where GitHub has always moved past
#    the pin: every state from the disk alone, install (the pin and nothing
#    else, its id and kinds read with git before anything lands, verified
#    again after, a wrong folder moved aside, then enabled; the exit code
#    isn't trusted; a shell that never sees the plugin, within a wall-clock
#    bound), update (to a moved pin and only forward: stale cards, ahead and
#    diverged checkouts, a renamed manifest, restart hints, a global update
#    past the pin), review, the refusals, OLED Corners' install and removal,
#    Face's rename (a `was` folder, the stub rename through Setup, a stranded
#    checkout, a rerun, a copy), a stopped job (its whole process group, its
#    staging folder), the status file's mode, and the handoffs.
# D. The Plugins page in throwaway notches: its size and shape, the card (its
#    motion, keys), an install through it that survives the notch being
#    stopped, the notice after it (also with GitHub gone), a failure, a
#    refused pin, a job that never starts, handoffs, Corners' removal card,
#    page switching and every close path, the notch update and Refresh blocked
#    while a plugin job runs, and a forced test notch without hooks refusing
#    everything.
# E. The live plugins folder is exactly as it was.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}
finish() {
  echo
  if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
  else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
  exit $((failures > 0))
}

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
SCRIPT="$REPO/bin/notch-plugins"
FIX="$REPO/dev/fixtures/plugins"
# The fixed path upstream writes, whatever XDG_CONFIG_HOME says.
LIVE="$HOME/.config/omarchy/plugins"
live_marker() { find "$LIVE" -maxdepth 1 -printf '%f %T@\n' 2>/dev/null | sort; }
marker=$(live_marker)

sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-plugins.XXXXXX")
root="$sb/shell"
qs_pid=""
cleanup() {
  [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null
  chmod -R u+rwx "$sb/gh" 2>/dev/null
  [[ -n ${KEEP:-} ]] && echo "kept $sb" || rm -rf "$sb"
}
trap cleanup EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid \
       GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
PD="$sb/home/.config/omarchy/plugins"
SCRATCH="$sb/run/kalinewb.notch"
mkdir -p "$PD" "$sb/gh" "$sb/work" "$sb/stubs" "$sb/bin" "$sb/xdgstubs"
mkdir -p -m 700 "$sb/run"
: >"$sb/calls.log"; : >"$sb/shell.log"; : >"$sb/terminal.log"; : >"$sb/enabled"

# --- stubs ----------------------------------------------------------------------
# omarchy-shell: logs argv joined by "|"; listPlugins answers from the sandbox
# manifests (dot folders aside, as Omarchy's scan) and $sb/enabled (minus ids in
# $sb/stub-hide), after sleeping $sb/stub-list-sleep seconds if set;
# enablePlugin writes $sb/enabled; rescanPlugins exits with $sb/stub-rescan-exit;
# any other target says "Target not found." while $sb/stub-target-missing exists.
cat >"$sb/stubs/omarchy-shell" <<EOF
#!/bin/bash
sb="$sb"
EOF
cat >>"$sb/stubs/omarchy-shell" <<'EOF'
line=$(IFS='|'; echo "$*")
echo "$line" >>"$sb/shell.log"
case "$1 ${2:-}" in
  "shell listPlugins")
    [[ -f $sb/stub-list-sleep ]] && sleep "$(cat "$sb/stub-list-sleep")"
    for m in "$sb"/home/.config/omarchy/plugins/*/manifest.json; do [[ -f $m ]] && cat "$m"; done |
      jq -sc --rawfile enabled "$sb/enabled" --rawfile hide <(cat "$sb/stub-hide" 2>/dev/null) \
        '[.[] | .id as $i | select(($hide | split("\n") | index($i)) == null)
          | {id, name, kinds, enabled: (($enabled | split("\n") | index($i)) != null)}]' ;;
  "shell enablePlugin")
    if [[ -f $sb/home/.config/omarchy/plugins/$3/manifest.json ]]; then echo "$3" >>"$sb/enabled"; echo ok; else echo unknown; fi ;;
  "shell rescanPlugins")
    exit "$(cat "$sb/stub-rescan-exit" 2>/dev/null || echo 0)" ;;
  *)
    if [[ -f $sb/stub-target-missing ]]; then echo "Target not found." >&2; exit 1; fi
    [[ "$1 ${2:-}" == "graveklar.face state" || "$1 ${2:-}" == "kalinewb.face state" ]] && echo '{"open":false}'
    exit 0 ;;
esac
EOF
printf '#!/bin/bash\nexit 1\n' >"$sb/stubs/hyprctl"
cat >"$sb/stubs/omarchy-hyprland-session-locked" <<EOF
#!/bin/bash
[[ -f "$sb/locked" ]]
EOF
cat >"$sb/stubs/terminal" <<EOF
#!/bin/bash
echo "\$#|\$*" >>"$sb/terminal.log"
EOF
# `omarchy` for the XDG check, which runs with no hooks: an empty plugin list.
printf '#!/bin/bash\necho "[]"\n' >"$sb/xdgstubs/omarchy"
# The omarchy stand-in: logs the call and its exit code, then runs the real
# omarchy with the sandbox HOME and the stubs first on PATH. For add/update,
# $sb/omarchy-sleep delays it and $sb/omarchy-fail makes it fail with that line.
# (Upstream's plugin commands find the plugins folder from HOME alone.)
cat >"$sb/bin/omarchy" <<EOF
#!/bin/bash
sb="$sb"
EOF
cat >>"$sb/bin/omarchy" <<'EOF'
echo "omarchy $*" >>"$sb/calls.log"
if [[ "$1 ${2:-}" == "plugin add" || "$1 ${2:-}" == "plugin update" ]]; then
  [[ -f $sb/omarchy-sleep ]] && sleep "$(cat "$sb/omarchy-sleep")"
  if [[ -f $sb/omarchy-fail ]]; then cat "$sb/omarchy-fail" >&2; echo "omarchy rc=1" >>"$sb/calls.log"; exit 1; fi
fi
env HOME="$sb/home" PATH="$sb/stubs:/usr/share/omarchy/bin:/usr/bin" OMARCHY_PATH=/usr/share/omarchy omarchy "$@"
rc=$?
echo "omarchy rc=$rc" >>"$sb/calls.log"
exit $rc
EOF
# A stand-in whose `plugin add` stages a folder the way upstream does, then
# hangs: for stopping a job.
cat >"$sb/bin/omarchy-hang" <<EOF
#!/bin/bash
sb="$sb"
EOF
cat >>"$sb/bin/omarchy-hang" <<'EOF'
if [[ "$1 ${2:-}" == "plugin add" ]]; then
  echo $$ >"$sb/hang.pid"
  mkdir -p "$sb/home/.config/omarchy/plugins/.add.tmp.$$"
  exec sleep 30
fi
exec "$sb/bin/omarchy" "$@"
EOF
# A stand-in that renames the repository's manifest id on "GitHub" between the
# runner's check and upstream's clone.
cat >"$sb/bin/omarchy-sneaky" <<EOF
#!/bin/bash
sb="$sb"
EOF
cat >>"$sb/bin/omarchy-sneaky" <<'EOF'
if [[ "$1 ${2:-}" == "plugin add" ]]; then
  w="$sb/work/sneaky-profiles"
  jq '.id = "evil.profiles"' "$w/manifest.json" >"$w/m.json" && mv "$w/m.json" "$w/manifest.json"
  git -C "$w" commit -qam "Rename" && git -C "$w" push -q origin main
fi
exec "$sb/bin/omarchy" "$@"
EOF
chmod +x "$sb"/stubs/* "$sb"/bin/* "$sb/xdgstubs/omarchy"

# --- "GitHub" -------------------------------------------------------------------
mkrepo() { # mkrepo <fixture> <repo name> [jq filter for its manifest]
  local w="$sb/work/$2"
  mkdir -p "$w" && cp -r "$FIX/$1/." "$w/"
  if [[ -n ${3:-} ]]; then jq "$3" "$w/manifest.json" >"$w/manifest.new" && mv "$w/manifest.new" "$w/manifest.json"; fi
  git -C "$w" init -q -b main && git -C "$w" add -A && git -C "$w" commit -qm "Initial"
  git init -q --bare -b main "$sb/gh/$2.git"
  git -C "$w" remote add origin "file://$sb/gh/$2.git" && git -C "$w" push -q origin main
}
mkrepo face omarchy-face
mkrepo profiles omarchy-profiles
mkrepo corners omarchy-oled-corners
mkrepo profiles evil-profiles '.id = "evil.profiles"'
mkrepo profiles bar-profiles '.kinds = ["bar"] | .entryPoints = {bar: "Panel.qml"}'
mkrepo profiles sneaky-profiles
publish() { # publish <repo> <file> <subject>
  echo "// $3" >>"$sb/work/$1/$2"
  git -C "$sb/work/$1" commit -qam "$3" && git -C "$sb/work/$1" push -q origin main
}
publish_manifest() { # publish_manifest <repo> <jq filter> <subject>
  local w="$sb/work/$1"
  jq "$2" "$w/manifest.json" >"$w/m.json" && mv "$w/m.json" "$w/manifest.json"
  git -C "$w" commit -qam "$3" && git -C "$w" push -q origin main
}
head_of() { git -C "$sb/gh/$1.git" rev-parse HEAD; }

# catalogue <file> <profiles repo> [face pin] [profiles pin] [corners pin]: the
# shipped catalogue on the sandbox's "GitHub", pinned to each repo's HEAD unless
# given.
catalogue() {
  jq --arg face "file://$sb/gh/omarchy-face.git" --arg profiles "file://$sb/gh/$2.git" \
     --arg corners "file://$sb/gh/omarchy-oled-corners.git" \
     --arg fpin "${3:-$(head_of omarchy-face)}" --arg ppin "${4:-$(head_of "$2")}" --arg cpin "${5:-$(head_of omarchy-oled-corners)}" '
    .plugins[0].url = $face | .plugins[0].pin = $fpin | .plugins[0].version = "2.0.0"
    | .plugins[1].url = $profiles | .plugins[1].pin = $ppin | .plugins[1].version = "1.0.0"
    | .plugins[2].url = $corners | .plugins[2].pin = $cpin | .plugins[2].version = "1.0.0"' "$REPO/plugins/catalogue.json" >"$1"
}
catalogue "$sb/catalogue.json" omarchy-profiles
catalogue "$sb/catalogue-evil.json" evil-profiles
catalogue "$sb/catalogue-bar.json" bar-profiles
catalogue "$sb/catalogue-sneaky.json" sneaky-profiles

HOOKS=(NOTCH_PLUGINS_DIR="$PD" NOTCH_PLUGINS_OMARCHY="$sb/bin/omarchy" NOTCH_PLUGINS_CATALOGUE="$sb/catalogue.json"
       NOTCH_PLUGINS_SHELL="$sb/stubs/omarchy-shell" NOTCH_PLUGINS_TERMINAL="$sb/stubs/terminal"
       NOTCH_PLUGINS_SESSION_LOCKED="$sb/stubs/omarchy-hyprland-session-locked" NOTCH_PLUGINS_SCRATCH="$SCRATCH")
# What a renamed plugin's update needs: Setup sandboxed into the same HOME,
# every command it runs a stub (bin/notch-setup refuses otherwise).
SETUP_HOOKS=(NOTCH_SETUP_SANDBOX="$sb" NOTCH_SETUP_HYPRCTL="$sb/stubs/hyprctl" NOTCH_SETUP_OMARCHY_SHELL="$sb/stubs/omarchy-shell"
             NOTCH_SETUP_OMARCHY="$sb/bin/omarchy" NOTCH_SETUP_TOGGLE_BAR=true NOTCH_SETUP_KILL=true
             NOTCH_SETUP_SESSION_LOCKED="$sb/stubs/omarchy-hyprland-session-locked" NOTCH_SETUP_RESTART_SHELL=true
             NOTCH_SETUP_LUA=false FIXTURE_RENAME_LOG="$sb/rename.log")
np() { env "${HOOKS[@]}" "$SCRIPT" "$@"; }
npc() { local c=$1; shift; env "${HOOKS[@]}" "${SETUP_HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$c" "$SCRIPT" "$@"; }
st="$sb/state/plugins-job.json"
field() { jq -r "$1" <<<"$2" 2>/dev/null; }
entry() { jq -c --arg id "$1" '.entries[] | select(.id == $id)' <<<"$2"; }
log_mark() { wc -l <"$sb/$1"; }
log_since() { tail -n +"$(($2 + 1))" "$sb/$1"; }
exists() { [[ -e $1 ]] && echo true || echo false; }
under() { (( $1 < $2 )) && echo true || echo false; } # under <ms> <limit>
scratch_left() { find "$SCRATCH" -mindepth 1 2>/dev/null | wc -l; }
forget() { rm -rf "$PD/$1"; grep -vx "$1" "$sb/enabled" >"$sb/enabled.new"; mv "$sb/enabled.new" "$sb/enabled"; }
forget_profiles() { forget kalinewb.profiles; }
head_in() { git -C "$PD/$1" rev-parse HEAD 2>/dev/null; }

# ---------------------------------------------------------------------------
echo "${BOLD}A. The catalogue${RESET}  ${DIM}sandbox $sb${RESET}"
shipped="$REPO/plugins/catalogue.json"
check "the shipped catalogue parses and validates, version 2" "0 3 2" \
  "$(jq -e . "$shipped" >/dev/null; echo $?) $("$SCRIPT" catalogue | jq '.plugins | length') $(jq .version "$shipped")"
check "it has exactly the three entries" "kalinewb.face kalinewb.profiles kalinewb.oled-corners" "$(jq -r '[.plugins[].id] | join(" ")' "$shipped")"
check "every URL is the plugin's GitHub repo" \
  "https://github.com/Kalinewb/omarchy-face.git https://github.com/Kalinewb/omarchy-profiles.git https://github.com/Kalinewb/omarchy-oled-corners.git" \
  "$(jq -r '[.plugins[].url] | join(" ")' "$shipped")"
check "every entry pins a full 40-hex commit and names its version" "true" \
  "$(jq -r 'all(.plugins[]; (.pin | test("^[0-9a-f]{40}$")) and (.version | length > 0))' "$shipped")"
check "Face is kalinewb.face, and was graveklar.face; only Corners is removed by Omarchy, with no panel" "graveklar.face kalinewb.oled-corners true" \
  "$(jq -r '"\(.plugins[0].was) \([.plugins[] | select(.removeVia == "omarchy") | .id] | join(" ")) \(.plugins[2] | has("status") or has("setup") or has("remove") | not)"' "$shipped")"
check "deny names liquid-notifications and both face-locks; no entry is denied or the notch itself" "true true" \
  "$(jq -r '.deny as $d | "\(["graveklar.liquid-notifications", "graveklar.face-lock", "kalinewb.face-lock"] | all(. as $i | $d | index($i) != null)) \(all(.plugins[]; .id as $i | $i != "kalinewb.notch" and ($d | index($i)) == null))"' "$shipped")"
check "no entry's kinds include bar" "true" "$(jq -r 'all(.plugins[]; .kinds | index("bar") == null)' "$shipped")"
# Each pin, read in the sibling checkout when it is there: the version the
# catalogue shows is the manifest's at the pin, and the id is the entry's (or
# the name it had).
SIBLINGS=${NOTCH_SIBLINGS:-$(dirname "$REPO")}
while read -r id was url pin version; do
  repo="$SIBLINGS/$(basename "$url" .git)"
  if ! git -C "$repo" cat-file -e "$pin^{commit}" 2>/dev/null; then echo "  ${DIM}skip  $id's pin: no checkout of it at $repo${RESET}"; continue; fi
  at=$(git -C "$repo" show "$pin:manifest.json")
  [[ $was == - ]] && was=""
  check "$id: the manifest at its pin is version $version, and names $id${was:+ or $was}" "$version true" \
    "$(jq -r .version <<<"$at") $(jq -r --arg id "$id" --arg was "$was" '.id == $id or .id == $was' <<<"$at")"
done < <(jq -r '.plugins[] | "\(.id) \(.was // "-") \(.url) \(.pin) \(.version)"' "$shipped")
suite="$REPO/suite.json"
pins_all=$(jq -r --slurpfile c "$shipped" '.pinned as $p | ([$c[0].self.id] + [$c[0].plugins[] | .id, (.was // empty)]) | all(. as $i | $p | index($i) != null)' "$suite")
check "suite.json: version 1, the bar is the notch, and it pins the notch, every entry and every old name" "1 true true" \
  "$(jq -r .version "$suite") $(jq -r --slurpfile c "$shipped" '.bar == $c[0].self.id' "$suite") $pins_all"
check "…and the companions and both lock clones" "true" \
  "$(jq -r '.pinned as $p | ["kalinewb.notch-menu", "kalinewb.notch-osd", "kalinewb.notch-notifications", "graveklar.face-lock", "kalinewb.face-lock"] | all(. as $i | $p | index($i) != null)' "$suite")"
bad() { # bad <jq filter>: a broken copy of the test catalogue, then `state` against it
  jq "$1" "$sb/catalogue.json" >"$sb/bad.json"
  env "${HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$sb/bad.json" "$SCRIPT" state | jq -r .reason; echo "${PIPESTATUS[0]}"
}
for filter in '.plugins[1].id = "graveklar.liquid-notifications"' '.plugins[0].url = "ext::sh -c touch% /tmp/pwned"' \
              '.plugins[0].status[0] = "../../bin/sh"' '.version = 1' '.plugins[1].pin = "8b4360e"' 'del(.plugins[1].version)' \
              '.plugins[0].was = "kalinewb.face-lock"' '.plugins[0].was = .plugins[0].id' '.plugins[2].removeVia = "rm"' \
              'del(.plugins[2].removeVia)'; do
  check "a catalogue with $filter is refused (catalogue, exit 1)" "catalogue 1" "$(bad "$filter" | tr '\n' ' ' | sed 's/ $//')"
done

# ---------------------------------------------------------------------------
echo; echo "${BOLD}B. Guards${RESET}"
resolved=$(env PATH="$sb/stubs:/usr/share/omarchy/bin:/usr/bin" bash -c 'command -v omarchy-shell')
check "under the stub PATH, omarchy-shell is the stub" "$sb/stubs/omarchy-shell" "$resolved"
[[ $resolved == "$sb/stubs/omarchy-shell" ]] || { echo "${RED}the stubs aren't first on PATH: stopping before anything runs${RESET}"; finish; }
fpin=$(head_of omarchy-face)
out=$(np run install graveklar.liquid-notifications "$st" "$fpin"); rc=$?
check "run install graveklar.liquid-notifications: denied, exit 2" "2 denied" "$rc $(field .reason "$out")"
out=$(np run install kalinewb.face-lock "$st" "$fpin"); rc=$?
check "run install kalinewb.face-lock: denied, exit 2" "2 denied" "$rc $(field .reason "$out")"
out=$(np run install graveklar.face "$st" "$fpin"); rc=$?
check "run install graveklar.face (a name Face had, not a catalogue id): unknown-id, exit 2" "2 unknown-id" "$rc $(field .reason "$out")"
out=$(np run install https://x/y.git "$st" "$fpin"); rc=$?
check "run install <a URL>: unknown-id, exit 2" "2 unknown-id" "$rc $(field .reason "$out")"
out=$(np run install ../x "$st" "$fpin"); rc=$?
check "run install ../x: unknown-id, exit 2" "2 unknown-id" "$rc $(field .reason "$out")"
out=$(np run remove kalinewb.profiles "$st"); rc=$?
check "run remove of a plugin with its own panel: usage, exit 2 (its panel removes it)" "2 usage" "$rc $(field .reason "$out")"
out=$(env NOTCH_PLUGINS_DIR="$PD" "$SCRIPT" run install kalinewb.face "$st" "$fpin"); rc=$?
check "NOTCH_PLUGINS_DIR without NOTCH_PLUGINS_OMARCHY: sandbox, exit 2" "2 sandbox" "$rc $(field .reason "$out")"
for hook in NOTCH_PLUGINS_CATALOGUE="$sb/catalogue.json" NOTCH_PLUGINS_SHELL="$sb/stubs/omarchy-shell" \
            NOTCH_PLUGINS_TERMINAL="$sb/stubs/terminal" NOTCH_PLUGINS_SESSION_LOCKED=false; do
  out=$(env "$hook" "$SCRIPT" state); rc=$?
  check "${hook%%=*} alone: sandbox, exit 2" "2 sandbox" "$rc $(field .reason "$out")"
done
out=$(np state --local); rc=$?
check "state takes no options (there is no network probe to skip)" "2 usage" "$rc $(field .reason "$out")"
mkdir -p -m 700 "$sb/state" && mkdir -p "$st.lock" && echo $$ >"$st.lock/pid"
out=$(np run enable kalinewb.face "$st"); rc=$?
check "a job lock held by a live process: busy, exit 1" "1 busy" "$rc $(field .reason "$out")"
rm -rf "$st.lock"; mkdir -p "$st.lock"
out=$(np run enable kalinewb.face "$st"); rc=$?
check "a lock just made, its pid not written yet: busy, never taken twice" "1 busy" "$rc $(field .reason "$out")"
rm -rf "$st.lock"
mkdir -p "$sb/state/update.json.lock" && echo $$ >"$sb/state/update.json.lock/pid"
out=$(np run enable kalinewb.face "$st"); rc=$?
check "the notch's own update holding its lock: busy" "1 busy" "$rc $(field .reason "$out")"
rm -rf "$sb/state/update.json.lock"
sleep 0.1 & dead=$!; wait $dead
mkdir -p "$st.lock" && echo "$dead" >"$st.lock/pid"
out=$(np run enable kalinewb.face "$st"); rc=$?
check "a stale lock (dead pid) is cleared and the job proceeds (to not-installed)" "1 not-installed false" "$rc $(field .reason "$out") $(exists "$st.lock")"
touch "$sb/locked"
out=$(np run enable kalinewb.face "$st"); rc=$?
check "a locked session: locked" "1 locked failed" "$rc $(field .reason "$out") $(jq -r .phase "$st")"
rm -f "$sb/locked"
out=$(env -u XDG_CONFIG_HOME HOME="$sb/xdghome" XDG_CONFIG_HOME="$sb/xdg" XDG_RUNTIME_DIR="$sb/run" PATH="$sb/xdgstubs:$PATH" "$SCRIPT" state)
check "no hooks, XDG_CONFIG_HOME set: the plugins folder is still \$HOME/.config/omarchy/plugins (upstream's)" "$sb/xdghome/.config/omarchy/plugins" \
  "$(field .pluginsDir "$out")"
job=$(jq -r .job "$st")
cp "$st" "$sb/not-a-job.json"
out=$(np ack "$sb/not-a-job.json" "$job"); rc=$?
check "ack refuses any file but plugins-job.json" "2 usage" "$rc $(field .reason "$out")"
np ack "$st" "someone-else" >/dev/null
check "ack of another job leaves the file alone" "false" "$(jq -r .seen "$st")"
mkdir -p "$st.lock" && echo $$ >"$st.lock/pid"
np ack "$st" "$job" >/dev/null
check "ack while a job holds the lock leaves the file alone (that job replaces it)" "false" "$(jq -r .seen "$st")"
rm -rf "$st.lock"
np ack "$st" "$job" >/dev/null
check "ack of that finished job marks it seen, and lets go of the lock" "true false" "$(jq -r .seen "$st") $(exists "$st.lock")"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}C. The runner against the sandbox${RESET}"
# GitHub has moved on past every pin: what lands is the pin, never HEAD.
ppin=$(head_of omarchy-profiles)
publish omarchy-profiles Panel.qml "Past the pin"
s=$(np state)
check "state: all three not installed, each row naming its pin and version" "not-installed $fpin 2.0.0 not-installed $ppin not-installed" \
  "$(field '"\(.state) \(.pin) \(.pinVersion)"' "$(entry kalinewb.face "$s")") $(field '"\(.state) \(.pin)"' "$(entry kalinewb.profiles "$s")") $(field .state "$(entry kalinewb.oled-corners "$s")")"

catalogue "$sb/catalogue.json" omarchy-profiles "$fpin" "$ppin"
out=$(np run install kalinewb.profiles "$st" 0123456789abcdef0123456789abcdef01234567); rc=$?
check "install with a commit that isn't the pin (a stale card): changed, nothing installed, nothing in scratch" "1 changed false 0" \
  "$rc $(field .reason "$out") $(exists "$PD/kalinewb.profiles") $(scratch_left)"
check "…and it says why in words" "true" "$(field '.message | contains("Open it again")' "$out")"

chmod 000 "$sb/gh/omarchy-profiles.git"
p=$(np preview kalinewb.profiles)
chmod 755 "$sb/gh/omarchy-profiles.git"
check "preview (not installed), GitHub unreadable: install, the pin, its version, ok -- no network" "install $ppin 1.0.0 true" \
  "$(field '"\(.action) \(.remote) \(.version) \(.ok)"' "$p")"

mark=$(log_mark shell.log)
out=$(np run install kalinewb.profiles "$st" "$ppin"); rc=$?
check "a pinned install lands with HEAD = the pin (not GitHub's HEAD), detached, origin = the catalogue URL" \
  "0 done $ppin detached file://$sb/gh/omarchy-profiles.git" \
  "$rc $(field .phase "$out") $(head_in kalinewb.profiles) $(git -C "$PD/kalinewb.profiles" symbolic-ref -q HEAD || echo detached) $(git -C "$PD/kalinewb.profiles" remote get-url origin)"
calls=$(log_since shell.log "$mark")
check "…enabled with no placement, after the rescan" "true" \
  "$(awk '/^shell\|rescanPlugins$/ { r = NR } /^shell\|enablePlugin\|kalinewb\.profiles\|\{\}$/ { e = NR } END { print (r > 0 && e > r) ? "true" : "false" }' <<<"$calls")"
check "…upstream was handed a local path, and no staging folder or scratch clone is left" "true 0 0" \
  "$(grep '^omarchy plugin add' "$sb/calls.log" | tail -1 | grep -qF "$SCRATCH/" && echo true || echo false) $(find "$PD" -maxdepth 1 -name '.add.tmp.*' | wc -l) $(scratch_left)"
s=$(np state)
check "state: Profiles pinned to the verified version, enabled" "current current true" "$(field '"\(.state) \(.relation) \(.enabled)"' "$(entry kalinewb.profiles "$s")")"

chmod 000 "$sb/gh/omarchy-profiles.git"
started=$(date +%s%3N)
s=$(np state)
took=$(( $(date +%s%3N) - started ))
chmod 755 "$sb/gh/omarchy-profiles.git"
echo "  ${DIM}state took ${took} ms${RESET}"
check "state with GitHub unreadable: under 2 s, still current (the probe never touches the network)" "true current" \
  "$(under "$took" 2000) $(field .state "$(entry kalinewb.profiles "$s")")"

mark=$(log_mark calls.log)
out=$(np run install kalinewb.profiles "$st" "$ppin"); rc=$?
check "install again: already-installed, and upstream add never ran" "1 already-installed 0" \
  "$rc $(field .reason "$out") $(log_since calls.log "$mark" | grep -c '^omarchy plugin add')"
forget_profiles

# A wrong id at the pin, caught before the plugins folder is touched.
evil=(env "${HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$sb/catalogue-evil.json" "$SCRIPT")
mark=$(log_mark shell.log); cmark=$(log_mark calls.log); before=$(ls -A "$PD" | sort | tr '\n' ' ')
out=$("${evil[@]}" run install kalinewb.profiles "$st" "$(head_of evil-profiles)"); rc=$?
check "a pin whose manifest isn't the catalogue id: failed wrong-id naming it" "1 wrong-id true" \
  "$rc $(field .reason "$out") $(field '.message | contains("evil.profiles")' "$out")"
check "…the plugins folder untouched: upstream never ran, no rescan or enable, nothing in scratch" "$before 0 0 0" \
  "$(ls -A "$PD" | sort | tr '\n' ' ') $(log_since calls.log "$cmark" | grep -c '^omarchy plugin add') $(log_since shell.log "$mark" | grep -cE 'rescanPlugins|enablePlugin') $(scratch_left)"

# What lands still isn't trusted: a stand-in that moves the staged clone past the pin.
cat >"$sb/bin/omarchy-sneaky" <<EOF
#!/bin/bash
if [[ "\$1 \${2:-}" == "plugin add" ]]; then
  git -C "\$3" show HEAD:manifest.json | jq '.id = "evil.profiles"' >"\$3/manifest.json"
  git -C "\$3" -c user.name=x -c user.email=x@x.invalid commit -qam "Rename"
fi
exec "$sb/bin/omarchy" "\$@"
EOF
chmod +x "$sb/bin/omarchy-sneaky"
sneaky=(env "${HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$sb/catalogue-sneaky.json" NOTCH_PLUGINS_OMARCHY="$sb/bin/omarchy-sneaky" "$SCRIPT")
mark=$(log_mark shell.log)
out=$("${sneaky[@]}" run install kalinewb.profiles "$st" "$(head_of sneaky-profiles)"); rc=$?
refused=$(find "$PD" -mindepth 1 -maxdepth 1 -name '.notch-refused.evil.profiles.*')
check "the folder that landed isn't the pin's (renamed after the check): failed wrong-id" "1 wrong-id" "$rc $(field .reason "$out")"
check "…the folder was moved aside to one .notch-refused.evil.profiles.*, named in movedTo" "false 1 true" \
  "$(exists "$PD/evil.profiles") $(grep -c . <<<"$refused") $([[ -n $refused && $(field .movedTo "$out") == "$refused" ]] && echo true || echo false)"
check "…never enabled, and the shell's plugin list doesn't have it" "0 false" \
  "$(log_since shell.log "$mark" | grep -c enablePlugin) $("$sb/stubs/omarchy-shell" shell listPlugins | jq 'any(.[]; .id == "evil.profiles")')"
rm -rf "$PD"/.notch-refused.*

cmark=$(log_mark calls.log)
barc=(env "${HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$sb/catalogue-bar.json" "$SCRIPT")
out=$("${barc[@]}" run install kalinewb.profiles "$st" "$(head_of bar-profiles)"); rc=$?
check "a pin whose manifest is a bar: failed bar-kind, no folder, upstream never ran" "1 bar-kind false 0" \
  "$rc $(field .reason "$out") $(exists "$PD/kalinewb.profiles") $(log_since calls.log "$cmark" | grep -c '^omarchy plugin add')"

mv "$sb/gh/omarchy-profiles.git" "$sb/gh/away.git"
out=$(np run install kalinewb.profiles "$st" "$ppin"); rc=$?
mv "$sb/gh/away.git" "$sb/gh/omarchy-profiles.git"
check "GitHub can't be reached: offline, nothing installed, nothing in scratch" "1 offline false 0" \
  "$rc $(field .reason "$out") $(exists "$PD/kalinewb.profiles") $(scratch_left)"

echo 1 >"$sb/stub-rescan-exit"
mark=$(log_mark calls.log)
out=$(np run install kalinewb.profiles "$st" "$ppin"); rc=$?
check "upstream add exits 1 (its rescan failed) but the plugin landed: done and enabled" "rc=1 0 done true" \
  "$(log_since calls.log "$mark" | grep -A1 '^omarchy plugin add' | grep -o 'rc=[0-9]*' | head -1) $rc $(field '"\(.phase) \(.enabled)"' "$out")"
rm -f "$sb/stub-rescan-exit"
forget_profiles

echo kalinewb.profiles >"$sb/stub-hide"
mark=$(log_mark shell.log)
started=$(date +%s%3N)
out=$(env "${HOOKS[@]}" NOTCH_PLUGINS_DISCOVER_MS=600 "$SCRIPT" run install kalinewb.profiles "$st" "$ppin"); rc=$?
waited=$(( $(date +%s%3N) - started ))
check "the shell never sees it: after the discovery wait, done with enabled:false (never failed), no enable" "0 done false 0 1" \
  "$rc $(field '"\(.phase) \(.enabled)"' "$out") $(log_since shell.log "$mark" | grep -c enablePlugin) $((waited >= 600))"
forget_profiles
echo 5 >"$sb/stub-list-sleep"
rm -f "$st"
env "${HOOKS[@]}" NOTCH_PLUGINS_DISCOVER_MS=600 "$SCRIPT" run install kalinewb.profiles "$st" "$ppin" >/dev/null &
job=$!
until [[ $(jq -r .step "$st" 2>/dev/null) == enabling ]] || ! kill -0 "$job" 2>/dev/null; do sleep 0.05; done
t1=$(date +%s%3N)
wait "$job"
took=$(( $(date +%s%3N) - t1 ))
rm -f "$sb/stub-list-sleep" "$sb/stub-hide"
echo "  ${DIM}discovery with a shell that hangs 5 s per list: ${took} ms${RESET}"
check "…a hung shell: the wait is bounded by the clock, not by polls × timeouts; the shipped wait is 10 s" "true done 10000" \
  "$(under "$took" 3500) $(jq -r .phase "$st") $(sed -n 's/.*NOTCH_PLUGINS_DISCOVER_MS:-\([0-9]*\)}.*/\1/p' "$SCRIPT" | tail -n 1)"

# Update: the notch moves the pin (a new catalogue), and the update follows it.
grep -qx kalinewb.profiles "$sb/enabled" || echo kalinewb.profiles >>"$sb/enabled"
publish omarchy-profiles Helper.qml "Helper tweak"
p2=$(head_of omarchy-profiles)
catalogue "$sb/catalogue.json" omarchy-profiles "$fpin" "$p2"
s=$(np state)
check "a moved pin, not here yet: update-available (verified update ready), nothing fetched" "update-available behind false" \
  "$(field '"\(.state) \(.relation)"' "$(entry kalinewb.profiles "$s")") $(git -C "$PD/kalinewb.profiles" cat-file -e "$p2^{commit}" 2>/dev/null && echo true || echo false)"
p=$(np preview kalinewb.profiles)
check "preview fetches the pin: 2 commits behind, the newest subject, 2 files, a restart likely, still Profiles" "true 2 Helper tweak 2 true kalinewb.profiles  $p2" \
  "$(field '"\(.ok) \(.behind) \(.commits[0].subject) \(.files) \(.restartLikely) \(.manifestId) \(.refused) \(.remote)"' "$p")"
out=$(np run update kalinewb.profiles "$st" "$ppin"); rc=$?
check "update with the old pin (a card from before the notch moved it): changed, HEAD unchanged" "1 changed $ppin" "$rc $(field .reason "$out") $(head_in kalinewb.profiles)"
mark=$(log_mark calls.log)
out=$(np run update kalinewb.profiles "$st" "$p2"); rc=$?
check "moving the pin and updating gives HEAD = the new pin, detached, restart suggested" "0 done $p2 true $p2 detached" \
  "$rc $(field '"\(.phase) \(.to) \(.restartSuggested)"' "$out") $(head_in kalinewb.profiles) $(git -C "$PD/kalinewb.profiles" symbolic-ref -q HEAD || echo detached)"
check "…validated by upstream, never \`omarchy plugin update\`" "1 0" \
  "$(log_since calls.log "$mark" | grep -c '^omarchy plugin validate') $(log_since calls.log "$mark" | grep -c '^omarchy plugin update')"
out=$(np run update kalinewb.profiles "$st" "$p2"); rc=$?
check "updating again at the pin: done, nothing moves" "0 done $p2" "$rc $(field .phase "$out") $(head_in kalinewb.profiles)"
publish omarchy-profiles Panel.qml "Entry point tweak"
catalogue "$sb/catalogue.json" omarchy-profiles "$fpin" "$(head_of omarchy-profiles)"
out=$(np run update kalinewb.profiles "$st" "$(head_of omarchy-profiles)"); rc=$?
check "an entry-point-only update: done, no restart suggested" "0 done false" "$rc $(field '"\(.phase) \(.restartSuggested)"' "$out")"
publish_manifest omarchy-profiles '.id = "evil.profiles"' "Rename"
catalogue "$sb/catalogue.json" omarchy-profiles "$fpin" "$(head_of omarchy-profiles)"
old=$(head_in kalinewb.profiles)
p=$(np preview kalinewb.profiles)
out=$(np run update kalinewb.profiles "$st" "$(head_of omarchy-profiles)"); rc=$?
check "a pin whose manifest renames the id: preview refused, update wrong-id, HEAD unchanged" "wrong-id 1 wrong-id $old" \
  "$(field .refused "$p") $rc $(field .reason "$out") $(head_in kalinewb.profiles)"
publish_manifest omarchy-profiles '.id = "kalinewb.profiles"' "Rename back"
p3=$(head_of omarchy-profiles)
catalogue "$sb/catalogue.json" omarchy-profiles "$fpin" "$p3"
np run update kalinewb.profiles "$st" "$p3" >/dev/null

# Ahead of, or beside, the pin: IPC can still ask, and nothing moves.
git -C "$PD/kalinewb.profiles" -c user.name=x -c user.email=x@x.invalid commit -q --allow-empty -m "Local, on top"
ahead=$(head_in kalinewb.profiles)
check "a local commit on top of the pin: newer" "newer" "$(field .state "$(entry kalinewb.profiles "$(np state)")")"
out=$(np run update kalinewb.profiles "$st" "$p3"); rc=$?
check "IPC run update with HEAD ahead of the pin: refused, HEAD unchanged" "1 local-changes $ahead" "$rc $(field .reason "$out") $(head_in kalinewb.profiles)"
git -C "$PD/kalinewb.profiles" checkout -q --detach "$p3~1"
git -C "$PD/kalinewb.profiles" -c user.name=x -c user.email=x@x.invalid commit -q --allow-empty -m "Local, beside"
beside=$(head_in kalinewb.profiles)
check "a local commit beside the pin: local-changes (differs from the verified version)" "local-changes diverged" \
  "$(field '"\(.state) \(.relation)"' "$(entry kalinewb.profiles "$(np state)")")"
out=$(np run update kalinewb.profiles "$st" "$p3"); rc=$?
check "IPC run update with HEAD diverged from the pin: refused, HEAD unchanged" "1 local-changes $beside" "$rc $(field .reason "$out") $(head_in kalinewb.profiles)"
git -C "$PD/kalinewb.profiles" checkout -q --detach "$p3"

# A global `omarchy plugin update` (upstream's fetch + ff-only) takes it past the pin.
publish omarchy-profiles Helper.qml "Past the verified version"
"$sb/bin/omarchy" plugin update kalinewb.profiles --yes >/dev/null 2>&1
check "a stand-in global \`omarchy plugin update\`: past the pin, newer, and the row offers no update" "$(head_of omarchy-profiles) newer" \
  "$(head_in kalinewb.profiles) $(field .state "$(entry kalinewb.profiles "$(np state)")")"
git -C "$PD/kalinewb.profiles" checkout -q --detach "$p3"

# Review: a floating terminal, nothing from the plugin run.
mark=$(log_mark terminal.log)
out=$(np review kalinewb.profiles)
for _ in $(seq 1 20); do [[ $(log_mark terminal.log) -gt $mark ]] && break; sleep 0.05; done
check "review on a detached checkout at the pin: update mode, the terminal logs HEAD..<pin>" "update true" \
  "$(field .mode "$out") $(tail -n 1 "$sb/terminal.log" | grep -qF "git log --stat HEAD..$p3" && echo true || echo false)"
publish omarchy-profiles Helper.qml "Reviewed before fetching"
p4=$(head_of omarchy-profiles)
catalogue "$sb/catalogue.json" omarchy-profiles "$fpin" "$p4"
mark=$(log_mark terminal.log)
out=$(np review kalinewb.profiles)
for _ in $(seq 1 20); do [[ $(log_mark terminal.log) -gt $mark ]] && break; sleep 0.05; done
cmd=$(tail -n 1 "$sb/terminal.log" | cut -d'|' -f2-)
ran=$(env GIT_CONFIG_GLOBAL=/dev/null bash -c "$cmd" 2>&1)
check "review with the pin absent locally: its command fetches it, and logs HEAD..<pin> without \"bad revision\"" "update true false" \
  "$(field .mode "$out") $(grep -qF "Reviewed before fetching" <<<"$ran" && echo true || echo false) $(grep -q 'bad revision' <<<"$ran" && echo true || echo false)"
np run update kalinewb.profiles "$st" "$p4" >/dev/null

# Refusals
echo "// edit" >>"$PD/kalinewb.profiles/Panel.qml"
check "a tracked edit: local-changes (local edits)" "local-changes true" "$(field '"\(.state) \(.dirty)"' "$(entry kalinewb.profiles "$(np state)")")"
publish omarchy-profiles Helper.qml "One more"
catalogue "$sb/catalogue.json" omarchy-profiles "$fpin" "$(head_of omarchy-profiles)"
out=$(np run update kalinewb.profiles "$st" "$(head_of omarchy-profiles)"); rc=$?
check "…and update refuses before anything moves" "1 local-changes $p4" "$rc $(field .reason "$out") $(head_in kalinewb.profiles)"
git -C "$PD/kalinewb.profiles" checkout -q Panel.qml
forget_profiles
mkdir -p "$PD/kalinewb.profiles" && cp -r "$FIX/profiles/." "$PD/kalinewb.profiles/"
check "a plain folder copy: other-source, and its status command never ran" "other-source unknown" \
  "$(field '"\(.state) \(.setup)"' "$(entry kalinewb.profiles "$(np state)")")"
out=$(np run update kalinewb.profiles "$st" "$(head_of omarchy-profiles)"); rc=$?
check "…and update refuses: not-git" "1 not-git" "$rc $(field .reason "$out")"
forget_profiles

# OLED Corners: no panel of its own, so it is removed from here.
cpin=$(head_of omarchy-oled-corners)
out=$(np run install kalinewb.oled-corners "$st" "$cpin"); rc=$?
check "Corners installs at its pin and is turned on" "0 done true $cpin" "$rc $(field '"\(.phase) \(.enabled)"' "$out") $(head_in kalinewb.oled-corners)"
check "…and its row offers Remove, with no panel to hand off to" "current" "$(field .state "$(entry kalinewb.oled-corners "$(np state)")")"
mark=$(log_mark calls.log)
out=$(np run remove kalinewb.oled-corners "$st"); rc=$?
check "Corners removes: done, the folder gone, by upstream's own remove" "0 done false 1" \
  "$rc $(field .phase "$out") $(exists "$PD/kalinewb.oled-corners") $(log_since calls.log "$mark" | grep -c '^omarchy plugin remove kalinewb.oled-corners --yes')"
out=$(np run remove kalinewb.oled-corners "$st"); rc=$?
check "…and removing it again: not-installed" "1 not-installed" "$rc $(field .reason "$out")"

# Face: kalinewb.face now, graveklar.face before. Its 2.x pin still says the old id.
mkdir -p "$sb/home/.config/omarchy"
printf '%s\n' '{"bar": {"id": "kalinewb.notch", "layout": {"right": [{"id": "graveklar.face"}]}}, "plugins": [{"id": "graveklar.face-lock"}]}' \
  >"$sb/home/.config/omarchy/shell.json"
out=$(np run install kalinewb.face "$st" "$fpin"); rc=$?
check "Face's 2.x pin installs under the id it carries, graveklar.face, and is turned on" "0 done true true false" \
  "$rc $(field '"\(.phase) \(.enabled)"' "$out") $(exists "$PD/graveklar.face/.git") $(exists "$PD/kalinewb.face")"
s=$(np state)
check "with only the old folder the row is that folder's: current, enabled, needs setup" "current graveklar.face true needed" \
  "$(field '"\(.state) \(.folder) \(.enabled) \(.setup)"' "$(entry kalinewb.face "$s")")"
out=$(np run install kalinewb.face "$st" "$fpin"); rc=$?
check "…and Install refuses: renamed" "1 renamed" "$rc $(field .reason "$out")"
mark=$(log_mark shell.log)
out=$(np setup kalinewb.face)
check "setup hands off to the id the panel answers to, graveklar.face" "true graveklar.face|open|setup|" "$(field .ok "$out") $(log_since shell.log "$mark" | tail -n 1)"
out=$(env "${HOOKS[@]}" FIXTURE_FACE_INSTALL=running "$SCRIPT" run update kalinewb.face "$st" "$fpin"); rc=$?
check "Face's own root build running: plugin-busy" "1 plugin-busy" "$rc $(field .reason "$out")"
out=$(npc "$sb/catalogue.json" run update kalinewb.face "$st" "$fpin"); rc=$?
check "an update at the pin with nothing to rename: done, the rename never needed" "0 done false 0" \
  "$rc $(field '"\(.phase) \(.renamed)"' "$out") $(cat "$sb/rename.log" 2>/dev/null | grep -c .)"

# The 3.0.0 pin carries the new id; the update lands it in the old folder, and
# Setup has Face's own script finish the move.
publish_manifest omarchy-face '.id = "kalinewb.face" | .version = "3.0.0"' "Rename Face to kalinewb.face"
f3=$(head_of omarchy-face)
catalogue "$sb/catalogue.json" omarchy-profiles "$f3" "$(head_of omarchy-profiles)"
s=$(np state)
check "the 3.0.0 pin: update-available on the old folder" "update-available graveklar.face" "$(field '"\(.state) \(.folder)"' "$(entry kalinewb.face "$s")")"
p=$(np preview kalinewb.face)
check "…its card says the update renames it" "true true kalinewb.face 3.0.0" "$(field '"\(.ok) \(.renames) \(.manifestId) \(.version)"' "$p")"
out=$(env "${HOOKS[@]}" "$SCRIPT" run update kalinewb.face "$st" "$f3"); rc=$?
check "without Setup's sandbox a sandboxed rename refuses (after the checkout), and nothing renamed" "1 sandbox false" \
  "$rc $(field .reason "$out") $(exists "$PD/kalinewb.face")"
git -C "$PD/graveklar.face" checkout -q --detach "$fpin"
: >"$sb/rename.log"
out=$(npc "$sb/catalogue.json" run update kalinewb.face "$st" "$f3"); rc=$?
check "a was update checks out the pin in graveklar.face, then runs the stub once with --finish --wait --from <old HEAD>" \
  "0 done true $f3 --finish --wait --from $fpin 1" \
  "$rc $(field '"\(.phase) \(.renamed) \(.to)"' "$out") $(cat "$sb/rename.log") $(grep -c . "$sb/rename.log")"
check "…the folder is kalinewb.face, shell.json names only the new ids, and the row follows it" "true false 0 current kalinewb.face" \
  "$(exists "$PD/kalinewb.face/.git") $(exists "$PD/graveklar.face") $(grep -c 'graveklar\.face' "$sb/home/.config/omarchy/shell.json") $(field '"\(.relation) \(.folder)"' "$(entry kalinewb.face "$(np state)")")"
check "…inside Setup's snapshot, whose Undo is Face's --rollback" "true" \
  "$(jq -r '.undo[0] | (.[0] | endswith("kalinewb.face/bin/omarchy-face-rename")) and .[1] == "--rollback"' "$sb/home/.local/state/kalinewb.notch/setup/snapshots/"*-face-renamed/meta.json 2>/dev/null)"

# Stranded: the pin checked out in the old folder, the rename never ran.
"$PD/kalinewb.face/bin/omarchy-face-rename" --rollback >/dev/null
: >"$sb/rename.log"
out=$(npc "$sb/catalogue.json" run update kalinewb.face "$st" "$f3"); rc=$?
check "a stranded checkout (at the pin, still graveklar.face) finishes: no checkout, one --finish, renamed" "0 true --finish --wait --from $f3 true" \
  "$rc $(field .renamed "$out") $(cat "$sb/rename.log") $(exists "$PD/kalinewb.face")"
: >"$sb/rename.log"
out=$(npc "$sb/catalogue.json" run update kalinewb.face "$st" "$f3"); rc=$?
check "a rerun is a no-op: done, nothing renamed, the stub never called" "0 done false 0" \
  "$rc $(field '"\(.phase) \(.renamed)"' "$out") $(grep -c . "$sb/rename.log")"

# A copy of Face with no .git in the old folder (Face's own install.sh): not ours to update.
forget kalinewb.face
mkdir -p "$PD/graveklar.face" && cp -r "$FIX/face/." "$PD/graveklar.face/"
check "a non-git was folder reads other-source" "other-source graveklar.face" "$(field '"\(.state) \(.folder)"' "$(entry kalinewb.face "$(np state)")")"
out=$(npc "$sb/catalogue.json" run update kalinewb.face "$st" "$f3"); rc=$?
check "…and Update refuses: not-git" "1 not-git" "$rc $(field .reason "$out")"
forget graveklar.face
catalogue "$sb/catalogue.json" omarchy-profiles "$fpin" "$(head_of omarchy-profiles)"
np run install kalinewb.face "$st" "$fpin" >/dev/null

# A stopped job: the runner alone is signalled.
stopped() { # stopped <signal>: "<exit code> <ms to exit> <phase> <reason>"
  local job t0 rc
  rm -f "$sb/hang.pid"
  # A background job of a script starts with INT ignored; give it back.
  env --default-signal=INT "${HOOKS[@]}" NOTCH_PLUGINS_OMARCHY="$sb/bin/omarchy-hang" "$SCRIPT" run install kalinewb.profiles "$st" "$(jq -r '.plugins[1].pin' "$sb/catalogue.json")" >/dev/null &
  job=$!
  for _ in $(seq 1 100); do [[ -s $sb/hang.pid && -d $PD/.add.tmp.$(cat "$sb/hang.pid" 2>/dev/null) ]] && break; sleep 0.05; done
  t0=$(date +%s%3N)
  kill "-$1" "$job"; wait "$job"; rc=$?
  echo "$rc $(( $(date +%s%3N) - t0 )) $(jq -r '"\(.phase) \(.reason)"' "$st")"
}
r=$(stopped TERM)
check "TERM to the runner mid-install: within 1 s it exits 143 and the status says failed, stopped" "143 true failed stopped" \
  "$(cut -d' ' -f1 <<<"$r") $(under "$(cut -d' ' -f2 <<<"$r")" 1000) $(cut -d' ' -f3- <<<"$r")"
hang=$(cat "$sb/hang.pid")
sleep 0.2
check "…upstream (a child in its own group) is gone too, and its staging folder removed" "false 0 false" \
  "$(kill -0 "$hang" 2>/dev/null && echo true || echo false) $(find "$PD" -maxdepth 1 -name '.add.tmp.*' | wc -l) $(exists "$PD/kalinewb.profiles")"
r=$(stopped INT)
check "INT the same way: exit 130, failed, stopped, nothing left" "130 failed stopped 0" "$(cut -d' ' -f1,3- <<<"$r") $(find "$PD" -maxdepth 1 -name '.add.tmp.*' | wc -l)"
check "the status file is mode 600 in a 700 folder, with no temp files, lock or scratch left" "600 700 0 false 0" \
  "$(stat -c %a "$st") $(stat -c %a "$sb/state") $(find "$sb/state" -name 'plugins-job.json.*' | wc -l) $(exists "$st.lock") $(scratch_left)"

# Handoffs
mark=$(log_mark shell.log)
out=$(np setup kalinewb.face)
check "setup: Face's own panel, over IPC, with exactly 4 arguments" "true graveklar.face|open|setup|" "$(field .ok "$out") $(log_since shell.log "$mark" | tail -n 1)"
touch "$sb/stub-target-missing"
check "a plugin whose widget isn't hosted: not-hosted" '{"ok":false,"reason":"not-hosted"}' "$(np setup kalinewb.face | jq -c '{ok, reason}')"
rm -f "$sb/stub-target-missing"
out=$(np setup kalinewb.oled-corners); rc=$?
check "a plugin with no panel has nothing to hand off to: usage, exit 2" "2 usage" "$rc $(field .reason "$out")"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}D. The Plugins page${RESET}"
mkdir -p "$root"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
ui="$sb/ui"
job_file="$ui/plugins-job.json"
CONFIG='{"batteryPeek":false,"bottomRadius":8}'
launch() { # launch [env...]: a test notch, returning once it answers
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_FORCE_PLUGINS=1 NOTCH_PLUGINS_DETACH=setsid \
    "${HOOKS[@]}" NOTCH_PLUGINS_STATE_DIR="$ui" NOTCH_PLUGINS_DONE_MS=2500 \
    NOTCH_HARNESS_CONFIG="$CONFIG" "$@" \
    quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
}
start() { launch "$@"; sleep 1; }
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }
status() { ipc plugins status; }
until_true() { # until_true <tries of 0.1 s> <jq over `plugins status`>
  for _ in $(seq 1 "$1"); do [[ $(status | jq -r "$2" 2>/dev/null) == true ]] && return 0; sleep 0.1; done
  return 1
}
pview() { jq -c --arg id "$1" '.entries[] | select(.id == $id)' <<<"$2"; }
profiles_ready='.checkedAt > 0 and ((.entries[] | select(.id == "kalinewb.profiles") | .state) == "not-installed")'

start
rest_height=$(ipc geometry | jq -r .window.height)
ipc plugins open >/dev/null
until_true 100 '.checkedAt > 0' ; sleep 1.2
g=$(ipc geometry); s=$(status)
echo "  ${DIM}$(jq -c '{state, view, target, bar: {width: .bar.width, height: .bar.height}, plugins: (.plugins | {open, size, content, host})}' <<<"$g")${RESET}"
check "plugins open: the notch expands into the plugins view" "expanded plugins true" "$(field '"\(.state) \(.view) \(.plugins.open)"' "$g")"
check "the notch's target is the page's size" "true" "$(field '.target.width == .plugins.size.width and .target.height == .plugins.size.height and .plugins.size.height > 100' "$g")"
check "…and it has arrived there, top edge on the screen edge, square top corners, radius 8" "true" \
  "$(field '(.bar.width - .target.width | fabs) < 0.5 and (.bar.height - .target.height | fabs) < 0.5 and .bar.y == 0 and .radii.topLeft == 0 and .radii.topRight == 0 and .radii.bottomLeft == 8' "$g")"
check "the panel content holding the page is at least the page's size (never clipped)" "true" \
  "$(field '.plugins.content.width >= .plugins.size.width and .plugins.content.height >= .plugins.size.height' "$g")"
check "the bar window keeps its resting height (the page draws in the panel window)" "$rest_height true" "$(field '"\(.window.height) \(.panel.height >= .plugins.size.height)"' "$g")"
audit() { python3 -c '
import json,sys; d=json.loads(sys.argv[1]); r=d["radius"]
items=[i for i in d["plugins"] if i["drawn"] and not i["gradient"] and i["width"]>2 and i["height"]>2]
bad=[i for i in items if abs(i["radius"]-max(0,min(r,i["height"]/2,i["width"]/2)))>0.01]
print(len(items)>0, len(bad))' "$(ipc design)"; }
check "every drawn rounded item on the page has the notch's radius" "True 0" "$(audit)"
check "the page's text is Apple white on the notch's black" "#FFFFFF #000000" "$(field '"\(.plugins.foreground) \(.plugins.surface)"' "$g")"
runner=$(np state | jq -r '[.entries[].state] | join(" ")')
check "plugins status: three entries plus the notch, in the runner's states" "3 self $runner" \
  "$(field '"\(.entries | length) \(.self.state) \([.entries[].state] | join(" "))"' "$s")"

check "confirm with no card: no-such-button, and nothing ran" "no-such-button false" "$(ipc pluginsPress confirm) $(exists "$job_file")"
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
s=$(status)
check "Install… opens the card: install, the pinned URL" "install file://$sb/gh/omarchy-profiles.git true" "$(field '"\(.confirm.action) \(.confirm.url) \(.open)"' "$s")"
check "…with the catalogue's pin (not GitHub's HEAD), and nothing ran" "$(jq -r '.plugins[1].pin' "$sb/catalogue.json") false" "$(field .confirm.sha "$s") $(exists "$job_file")"
for _ in $(seq 1 30); do [[ $(ipc geometry | jq -r '.plugins.motion | length >= 50') == true ]] && break; sleep 0.1; done
g=$(ipc geometry)
echo "  ${DIM}card open: $(jq -c '.plugins | {listHeight, heldHeight, layers, samples: (.motion | length), heights: [.motion[] | .drawn] | unique | .[:6]}' <<<"$g")${RESET}"
check "opening the card: sampled every 16 ms, the notch never drops below the list's height, and the list is gone before the card shows" "true true true" \
  "$(field '.plugins.motion | "\(length >= 30) \(all(.[]; .drawn >= .list - 0.5)) \(([.[] | select(.card > 0)] | first | .listOpacity) == 0)"' "$g")"
check "the card's buttons have the notch's radius too" "True 0 true" "$(audit) $(field .plugins.card "$g")"
k1=$(field .plugins.focus "$g"); ipc pluginsPress key:tab >/dev/null; k2=$(ipc geometry | jq -r .plugins.focus)
ipc pluginsPress key:backtab >/dev/null; k3=$(ipc geometry | jq -r .plugins.focus)
check "card keys: Cancel has focus, Tab moves to Install, Shift+Tab back" "cancel confirm cancel" "$k1 $k2 $k3"
ipc pluginsPress key:escape >/dev/null; sleep 1.1
g=$(ipc geometry)
check "Escape cancels the card, and nothing ran" "null true false" "$(status | jq -c .confirm) $(field .plugins.open "$g") $(exists "$job_file")"
check "closing the card: while any of it shows the notch holds its height, then settles on the list's" "true true true" \
  "$(field '.plugins.motion | "\(length >= 30) \(all(.[] | select(.card > 0); .drawn >= .held - 0.5)) \((last | .held) == (last | .list))"' "$g")"
ipc pluginsPress key:up >/dev/null; ipc pluginsPress key:up >/dev/null
ipc pluginsPress key:down >/dev/null; sel=$(ipc geometry | jq -r .plugins.selected)
ipc pluginsPress key:return >/dev/null; sleep 0.3; opened=$(status | jq -r '.confirm.action // "none"')
ipc pluginsPress key:return >/dev/null; sleep 0.3
check "list keys: Up to the top, Down picks Profiles, Enter opens its Install card, Enter on Cancel closes it" "1 install null" "$sel $opened $(status | jq -c .confirm)"

ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
ipc pluginsPress confirm >/dev/null
until_true 150 '.job.phase == "done"'
until_true 100 '(.entries[] | select(.id == "kalinewb.profiles") | .state) == "current"'
s=$(status)
check "Install through the page: the detached job is done" "done install kalinewb.profiles" "$(field '"\(.job.phase) \(.job.action) \(.job.id)"' "$s")"
check "…and the disk, re-read, says current and enabled" "current true" \
  "$(field '"\(.state)"' "$(pview kalinewb.profiles "$s")") $(field '.probe[] | select(.id == "kalinewb.profiles") | .enabled' "$s")"
stop

forget_profiles
echo 2 >"$sb/omarchy-sleep"
start
ipc plugins open >/dev/null
until_true 100 "$profiles_ready"
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
ipc pluginsPress confirm >/dev/null
sleep 0.3
stop
for _ in $(seq 1 100); do [[ $(jq -r .phase "$job_file" 2>/dev/null) == done ]] && break; sleep 0.1; done
rm -f "$sb/omarchy-sleep"
check "the notch stopped 0.3 s after confirm: the job still finishes" "done true" "$(jq -r .phase "$job_file") $(exists "$PD/kalinewb.profiles/.git")"
start
until_true 100 '.notice == "done"'; sleep 0.8
g=$(ipc geometry); s=$(status)
check "a new notch pops down the notice: done, state notice" "done notice plugins" "$(field .notice "$s") $(field '"\(.state) \(.plugins.noticeKind)"' "$g")"
check "…and the notch's target is the notice's size" "true" "$(field '.target.width == .update.size.width and .target.height == .update.size.height and .update.size.height > 32' "$g")"
for _ in $(seq 1 50); do sleep 0.1; [[ $(status | jq -r .notice) == "" ]] && break; done
sleep 1.0
check "…then it clears itself, marked seen (in the file too), and the notch rests" " true true compact" \
  "$(status | jq -r '"\(.notice) \(.job.seen)"') $(jq -r .seen "$job_file") $(ipc geometry | jq -r .state)"
stop

# The notice without GitHub: the repo goes away as soon as the job is done.
forget_profiles
echo 2 >"$sb/omarchy-sleep"
start
ipc plugins open >/dev/null
until_true 100 "$profiles_ready"
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
ipc pluginsPress confirm >/dev/null
sleep 0.3
stop
for _ in $(seq 1 100); do [[ $(jq -r .phase "$job_file" 2>/dev/null) == done ]] && break; sleep 0.05; done
chmod 000 "$sb/gh/omarchy-profiles.git"
rm -f "$sb/omarchy-sleep"
launch
t0=$(date +%s%3N)
until_true 40 '.notice == "done"'
took=$(( $(date +%s%3N) - t0 ))
echo "  ${DIM}notice after $took ms; $(status | jq -c '{checking, checkedAt}')${RESET}"
check "GitHub unreadable: a new notch shows done within 2 s of answering (the probe reads the disk alone)" "done true" \
  "$(status | jq -r .notice) $(under "$took" 2000)"
ipc pluginsPress notice:dismiss >/dev/null
stop
chmod 755 "$sb/gh/omarchy-profiles.git"

forget_profiles
echo "fatal: unable to access the repository" >"$sb/omarchy-fail"
start
ipc plugins open >/dev/null
until_true 100 "$profiles_ready"
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
ipc pluginsPress confirm >/dev/null
until_true 150 '.job.phase == "failed"'
ipc plugins close >/dev/null
until_true 30 '.notice == "failed"'; sleep 1.0
s=$(status)
check "a failing install: the notice says failed, with the reason" "failed fatal: unable to access the repository notice" \
  "$(field '"\(.notice) \(.job.message)"' "$s") $(ipc geometry | jq -r .state)"
ipc pluginsPress notice:dismiss >/dev/null; sleep 1.0
check "…until dismissed" " true compact" "$(status | jq -r '"\(.notice) \(.job.seen)"') $(ipc geometry | jq -r .state)"
rm -f "$sb/omarchy-fail"

# A job whose runner refuses before writing anything (another holds the lock).
sleep 60 & holder=$!
mkdir -p "$job_file.lock" && echo "$holder" >"$job_file.lock/pid"
ipc plugins open >/dev/null
until_true 100 "$profiles_ready"
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
ipc pluginsPress confirm >/dev/null
sleep 0.5; first=$(status | jq -r .jobRunning)
until_true 100 '.notice == "failed"'
check "a job that never starts: running at first, then failed not-started within seconds, and nothing blocked" "true failed not-started false" \
  "$first $(status | jq -r '"\(.notice) \(.job.reason) \(.jobRunning)"')"
ipc plugins close >/dev/null; sleep 1
ipc pluginsPress notice:dismiss >/dev/null; sleep 0.8
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; rm -rf "$job_file.lock"

mark=$(log_mark shell.log)
ipc plugins open >/dev/null; sleep 0.9
ipc pluginsPress setup:kalinewb.face >/dev/null
for _ in $(seq 1 30); do log_since shell.log "$mark" | grep -q '^graveklar.face|open|setup|$' && break; sleep 0.1; done
check "Open setup hands off to Face's own panel (under the id it is installed as), and the page gets out of its way" "1 false" \
  "$(log_since shell.log "$mark" | grep -cx 'graveklar.face|open|setup|') $(ipc geometry | jq -r .plugins.open)"

ipc plugins open >/dev/null; sleep 0.9
ipc settings >/dev/null; sleep 0.5
check "the settings over the page close the page" "false true settings" "$(ipc geometry | jq -r '"\(.plugins.open) \(.settingsOpen) \(.view)"')"
ipc settings >/dev/null; ipc menu root >/dev/null; sleep 0.5
ipc plugins open >/dev/null; sleep 0.5
check "the page over the menu closes the menu" "false true plugins" "$(ipc geometry | jq -r '"\(.menu.open) \(.plugins.open) \(.view)"')"
# The notch's own row used to carry a button that sent you to Settings ->
# Updates to press a different button for the same thing. The row does it here
# now: installing and updating is one place, choosing is the other.
ipc pluginsPress checkSelf:kalinewb.notch >/dev/null; sleep 0.6
check "the notch's own row checks for its update in place, without leaving the page" "true false" \
  "$(ipc geometry | jq -r '"\(.plugins.open) \(.settingsOpen)"')"
ipc plugins open:kalinewb.profiles >/dev/null; sleep 0.9
check "plugins open:<id> opens the page at that entry, scrolled into view" "kalinewb.profiles 1 true" \
  "$(ipc geometry | jq -r '"\(.plugins.focusId) \(.plugins.selected) \(.plugins.scroll.selectedShown)"')"
stop

CONFIG='{"batteryPeek":false,"bottomRadius":8,"openAction":"widgets"}' start
ipc plugins open >/dev/null; sleep 0.9
ipc toggle >/dev/null; sleep 0.6
check "the open keybind over the page (closePanels): page closed, widgets, keyboard released" "false widgets none" \
  "$(ipc geometry | jq -r '"\(.plugins.open) \(.view) \(.panel.keyboard)"')"
stop
CONFIG='{"batteryPeek":false,"bottomRadius":8,"stayOpen":true,"openAction":"clock"}' start
ipc plugins open >/dev/null; sleep 0.9
ipc collapse >/dev/null; sleep 0.6
check "stayOpen: a collapse under the page doesn't flip its view (the showPinnedView guard)" "plugins true" \
  "$(ipc geometry | jq -r '"\(.view) \(.plugins.open)"')"
stop

# A pin that isn't the plugin: the card can't know without the network, so
# the job refuses it, and nothing lands.
forget_profiles
start NOTCH_PLUGINS_CATALOGUE="$sb/catalogue-evil.json"
ipc plugins open >/dev/null
until_true 100 '.checkedAt > 0'
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
ipc pluginsPress confirm >/dev/null
until_true 150 '.job.phase == "failed"'
check "installing a pin whose id isn't the plugin's: the job fails wrong-id and nothing lands" "failed wrong-id false" \
  "$(status | jq -r '"\(.job.phase) \(.job.reason)"') $(exists "$PD/evil.profiles")"
ipc pluginsPress notice:dismiss >/dev/null
stop

# OLED Corners has no panel: Remove… opens a card here, no preview.
np run install kalinewb.oled-corners "$st" "$(jq -r '.plugins[2].pin' "$sb/catalogue.json")" >/dev/null
start
ipc plugins open >/dev/null
until_true 100 '(.entries[] | select(.id == "kalinewb.oled-corners") | .state) == "current"'
mark=$(log_mark shell.log)
ipc pluginsPress remove:kalinewb.oled-corners >/dev/null
until_true 50 '.confirm.ready'
check "Corners' Remove… opens the card, ready at once, with no handoff" "remove true 0" \
  "$(status | jq -r '"\(.confirm.action) \(.confirm.ready)"') $(log_since shell.log "$mark" | grep -c '^kalinewb.oled-corners|')"
ipc pluginsPress confirm >/dev/null
until_true 150 '.job.phase == "done"'
until_true 100 '(.entries[] | select(.id == "kalinewb.oled-corners") | .state) == "not-installed"'
check "…and confirming removes it: done, the folder gone, the row back to Install…" "done remove false not-installed" \
  "$(status | jq -r '"\(.job.phase) \(.job.action)"') $(exists "$PD/kalinewb.oled-corners") $(status | jq -r '.entries[] | select(.id == "kalinewb.oled-corners") | .state')"
stop

# The notch's own update waits while a plugin job runs (and its buttons say so).
git clone -q --bare "$REPO" "$sb/notch-origin.git"
git clone -q "$sb/notch-origin.git" "$sb/notch-plugin"
git clone -q "$sb/notch-origin.git" "$sb/notch-work"
jq '.version = "9.9.9"' "$sb/notch-work/manifest.json" >"$sb/notch-work/m.json" && mv "$sb/notch-work/m.json" "$sb/notch-work/manifest.json"
git -C "$sb/notch-work" commit -qam "Test: a newer notch" && git -C "$sb/notch-work" push -q origin HEAD
forget_profiles
echo 4 >"$sb/omarchy-sleep"
start NOTCH_FORCE_UPDATES=1 NOTCH_UPDATE_DIR="$sb/notch-plugin" NOTCH_UPDATE_STATE_DIR="$ui" NOTCH_UPDATE_APPLY=true \
  NOTCH_UPDATE_RESTART=none NOTCH_UPDATE_FIRST_CHECK_MS=300 NOTCH_UPDATE_DETACH=setsid
for _ in $(seq 1 80); do [[ $(ipc update status | jq -r .notice) == available ]] && break; sleep 0.1; done
ipc plugins open >/dev/null
until_true 100 "$profiles_ready"
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
ipc pluginsPress confirm >/dev/null
sleep 0.5; refresh_during=$(ipc geometry | jq -r .plugins.refreshEnabled)
ipc plugins close >/dev/null; sleep 0.8
# Each button read while its panel is on show (a hidden panel's buttons are
# disabled anyway).
# The notch's own Update button is on the Plugins page now, on its own row --
# not in Settings -- so it is read from the model rather than by opening a panel.
buttons() { local n s; n=$(ipc geometry | jq -r .plugins.updateButtons.notice)
  s=$(ipc geometry | jq -r .plugins.updateButtons.page); echo "$s $n"; }
u=$(ipc update now)
check "while a plugin job runs: the notch update doesn't start, both Update buttons and Refresh are disabled" "true available false false false false" \
  "$(status | jq -r .jobRunning) $(field .notice "$u") $(exists "$ui/update.json") $(buttons) $refresh_during"
until_true 150 '.job.phase == "done"'
rm -f "$sb/omarchy-sleep"
check "…and once it has finished they take clicks again" "false true true" "$(status | jq -r .jobRunning) $(buttons)"
stop

# A forced test notch without the sandbox hooks: the dangerous case.
NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_FORCE_PLUGINS=1 NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 1
ipc plugins open >/dev/null; sleep 0.5
ipc plugins refresh >/dev/null; sleep 2
check "NOTCH_FORCE_PLUGINS=1 without hooks: presses refused, and a refresh never probes" "refused true false 0 false" \
  "$(ipc pluginsPress install:kalinewb.face) $(status | jq -r '"\(.enabled) \(.canAct) \(.checkedAt) \(.checking)"')"
check "no IPC verb installs: plugins install is an unknown action" '{"error":"unknown action"}' "$(ipc plugins install)"
stop

check "no QML errors" "none" "$(grep -E '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | grep . || echo none)"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}E. The live plugins folder${RESET}"
check "the live plugins folder's entries and mtimes are unchanged" "$marker" "$(live_marker)"

finish
