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
# A. The shipped catalogue: its entries, pins and deny list; invalid catalogues
#    are refused.
# B. Guards: denied and unknown ids, URLs and paths as ids, every sandbox hook
#    without both partners, the job lock (live, half made, stale), the notch
#    update's lock, a locked session, the plugins folder ignoring
#    XDG_CONFIG_HOME, and ack only ever marking its own finished job.
# C. bin/notch-plugins against the sandbox: every state, the local probe,
#    install (the exact commit, id and kinds checked before anything lands,
#    verified again after, a wrong folder moved aside, then enabled; the exit
#    code isn't trusted; a shell that never sees the plugin, within a
#    wall-clock bound), update (preview numbers, stale commits, a renamed
#    manifest, restart hints), the refusals, a stopped job (its whole process
#    group, its staging folder), the status file's mode, and the handoffs.
# D. The Plugins page in throwaway notches: its size and shape, the card (its
#    motion, keys, a refused repository), an install through it that survives
#    the notch being stopped, the notice after it (also with GitHub gone), a
#    failure, a job that never starts, handoffs, page switching and every
#    close path, the notch update and Refresh blocked while a plugin job runs,
#    and a forced test notch without hooks refusing everything.
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
SCRATCH="$sb/run/graveklar.notch"
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
    [[ "$1 ${2:-}" == "graveklar.face state" ]] && echo '{"open":false}'
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

catalogue() { # catalogue <file> <profiles repo>
  jq --arg face "file://$sb/gh/omarchy-face.git" --arg profiles "file://$sb/gh/$2.git" \
    '.plugins[0].url = $face | .plugins[1].url = $profiles' "$REPO/plugins/catalogue.json" >"$1"
}
catalogue "$sb/catalogue.json" omarchy-profiles
catalogue "$sb/catalogue-evil.json" evil-profiles
catalogue "$sb/catalogue-bar.json" bar-profiles
catalogue "$sb/catalogue-sneaky.json" sneaky-profiles

HOOKS=(NOTCH_PLUGINS_DIR="$PD" NOTCH_PLUGINS_OMARCHY="$sb/bin/omarchy" NOTCH_PLUGINS_CATALOGUE="$sb/catalogue.json"
       NOTCH_PLUGINS_SHELL="$sb/stubs/omarchy-shell" NOTCH_PLUGINS_TERMINAL="$sb/stubs/terminal"
       NOTCH_PLUGINS_SESSION_LOCKED="$sb/stubs/omarchy-hyprland-session-locked" NOTCH_PLUGINS_SCRATCH="$SCRATCH")
np() { env "${HOOKS[@]}" "$SCRIPT" "$@"; }
st="$sb/state/plugins-job.json"
field() { jq -r "$1" <<<"$2" 2>/dev/null; }
entry() { jq -c --arg id "$1" '.entries[] | select(.id == $id)' <<<"$2"; }
log_mark() { wc -l <"$sb/$1"; }
log_since() { tail -n +"$(($2 + 1))" "$sb/$1"; }
exists() { [[ -e $1 ]] && echo true || echo false; }
under() { (( $1 < $2 )) && echo true || echo false; } # under <ms> <limit>
scratch_left() { find "$SCRATCH" -mindepth 1 2>/dev/null | wc -l; }
forget_profiles() { rm -rf "$PD/kalinewb.profiles"; grep -vx kalinewb.profiles "$sb/enabled" >"$sb/enabled.new"; mv "$sb/enabled.new" "$sb/enabled"; }

# ---------------------------------------------------------------------------
echo "${BOLD}A. The catalogue${RESET}  ${DIM}sandbox $sb${RESET}"
shipped="$REPO/plugins/catalogue.json"
check "the shipped catalogue parses and validates" "0 2" "$(jq -e . "$shipped" >/dev/null; echo $?) $("$SCRIPT" catalogue | jq '.plugins | length')"
check "it has exactly the two entries" "graveklar.face kalinewb.profiles" "$(jq -r '[.plugins[].id] | join(" ")' "$shipped")"
check "both URLs are the pinned GitHub repos" \
  "https://github.com/Kalinewb/omarchy-face.git https://github.com/Kalinewb/omarchy-profiles.git" "$(jq -r '[.plugins[].url] | join(" ")' "$shipped")"
check "deny names liquid-notifications and face-lock; no entry is denied or the notch itself" "true true" \
  "$(jq -r '.deny as $d | "\(($d | index("graveklar.liquid-notifications") != null) and ($d | index("graveklar.face-lock") != null)) \(all(.plugins[]; .id as $i | $i != "graveklar.notch" and ($d | index($i)) == null))"' "$shipped")"
check "no entry's kinds include bar" "true" "$(jq -r 'all(.plugins[]; .kinds | index("bar") == null)' "$shipped")"
bad() { # bad <jq filter>: a broken copy of the test catalogue, then `state` against it
  jq "$1" "$sb/catalogue.json" >"$sb/bad.json"
  env "${HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$sb/bad.json" "$SCRIPT" state | jq -r .reason; echo "${PIPESTATUS[0]}"
}
check "a catalogue with a denied id is refused (catalogue, exit 1)" "catalogue 1" "$(bad '.plugins[1].id = "graveklar.liquid-notifications"' | tr '\n' ' ' | sed 's/ $//')"
check "a catalogue with an ext:: URL is refused" "catalogue 1" "$(bad '.plugins[0].url = "ext::sh -c touch% /tmp/pwned"' | tr '\n' ' ' | sed 's/ $//')"
check "a catalogue with ../ in a status path is refused" "catalogue 1" "$(bad '.plugins[0].status[0] = "../../bin/sh"' | tr '\n' ' ' | sed 's/ $//')"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}B. Guards${RESET}"
resolved=$(env PATH="$sb/stubs:/usr/share/omarchy/bin:/usr/bin" bash -c 'command -v omarchy-shell')
check "under the stub PATH, omarchy-shell is the stub" "$sb/stubs/omarchy-shell" "$resolved"
[[ $resolved == "$sb/stubs/omarchy-shell" ]] || { echo "${RED}the stubs aren't first on PATH: stopping before anything runs${RESET}"; finish; }
out=$(np run install graveklar.liquid-notifications "$st" "$(head_of omarchy-face)"); rc=$?
check "run install graveklar.liquid-notifications: denied, exit 2" "2 denied" "$rc $(field .reason "$out")"
out=$(np run install https://x/y.git "$st" "$(head_of omarchy-face)"); rc=$?
check "run install <a URL>: unknown-id, exit 2" "2 unknown-id" "$rc $(field .reason "$out")"
out=$(np run install ../x "$st" "$(head_of omarchy-face)"); rc=$?
check "run install ../x: unknown-id, exit 2" "2 unknown-id" "$rc $(field .reason "$out")"
out=$(env NOTCH_PLUGINS_DIR="$PD" "$SCRIPT" run install graveklar.face "$st" "$(head_of omarchy-face)"); rc=$?
check "NOTCH_PLUGINS_DIR without NOTCH_PLUGINS_OMARCHY: sandbox, exit 2" "2 sandbox" "$rc $(field .reason "$out")"
for hook in NOTCH_PLUGINS_CATALOGUE="$sb/catalogue.json" NOTCH_PLUGINS_SHELL="$sb/stubs/omarchy-shell" \
            NOTCH_PLUGINS_TERMINAL="$sb/stubs/terminal" NOTCH_PLUGINS_SESSION_LOCKED=false; do
  out=$(env "$hook" "$SCRIPT" state); rc=$?
  check "${hook%%=*} alone: sandbox, exit 2" "2 sandbox" "$rc $(field .reason "$out")"
done
mkdir -p -m 700 "$sb/state" && mkdir -p "$st.lock" && echo $$ >"$st.lock/pid"
out=$(np run enable graveklar.face "$st"); rc=$?
check "a job lock held by a live process: busy, exit 1" "1 busy" "$rc $(field .reason "$out")"
rm -rf "$st.lock"; mkdir -p "$st.lock"
out=$(np run enable graveklar.face "$st"); rc=$?
check "a lock just made, its pid not written yet: busy, never taken twice" "1 busy" "$rc $(field .reason "$out")"
rm -rf "$st.lock"
mkdir -p "$sb/state/update.json.lock" && echo $$ >"$sb/state/update.json.lock/pid"
out=$(np run enable graveklar.face "$st"); rc=$?
check "the notch's own update holding its lock: busy" "1 busy" "$rc $(field .reason "$out")"
rm -rf "$sb/state/update.json.lock"
sleep 0.1 & dead=$!; wait $dead
mkdir -p "$st.lock" && echo "$dead" >"$st.lock/pid"
out=$(np run enable graveklar.face "$st"); rc=$?
check "a stale lock (dead pid) is cleared and the job proceeds (to not-installed)" "1 not-installed false" "$rc $(field .reason "$out") $(exists "$st.lock")"
touch "$sb/locked"
out=$(np run enable graveklar.face "$st"); rc=$?
check "a locked session: locked" "1 locked failed" "$rc $(field .reason "$out") $(jq -r .phase "$st")"
rm -f "$sb/locked"
out=$(env -u XDG_CONFIG_HOME HOME="$sb/xdghome" XDG_CONFIG_HOME="$sb/xdg" XDG_RUNTIME_DIR="$sb/run" PATH="$sb/xdgstubs:$PATH" "$SCRIPT" state --local)
check "no hooks, XDG_CONFIG_HOME set: the plugins folder is still \$HOME/.config/omarchy/plugins (upstream's)" "$sb/xdghome/.config/omarchy/plugins true" \
  "$(field '"\(.pluginsDir) \(.local)"' "$out")"
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
s=$(np state)
check "state: Face ID not installed, remote = its repo's HEAD" "not-installed $(head_of omarchy-face)" "$(field '"\(.state) \(.remote)"' "$(entry graveklar.face "$s")")"
check "state: Profiles not installed, remote = its repo's HEAD" "not-installed $(head_of omarchy-profiles)" "$(field '"\(.state) \(.remote)"' "$(entry kalinewb.profiles "$s")")"

out=$(np run install graveklar.face "$st" 0123456789abcdef0123456789abcdef01234567); rc=$?
check "install with a commit GitHub doesn't have: changed, nothing installed, no clone left in scratch" "1 changed false 0" \
  "$rc $(field .reason "$out") $(exists "$PD/graveklar.face") $(scratch_left)"

sha=$(head_of omarchy-face)
p=$(np preview graveklar.face)
check "preview (not installed): install, GitHub's HEAD, its manifest id, not refused, clone removed" "install $sha graveklar.face  true 0" \
  "$(field '"\(.action) \(.remote) \(.manifestId) \(.refused) \(.ok)"' "$p") $(scratch_left)"

mark=$(log_mark shell.log)
out=$(np run install graveklar.face "$st" "$sha"); rc=$?
check "install: done; a git checkout of the pinned URL at the confirmed commit" "0 done true file://$sb/gh/omarchy-face.git $sha" \
  "$rc $(field .phase "$out") $(exists "$PD/graveklar.face/.git") $(git -C "$PD/graveklar.face" remote get-url origin) $(git -C "$PD/graveklar.face" rev-parse HEAD)"
calls=$(log_since shell.log "$mark")
check "…enabled with no placement, after the rescan" "true" \
  "$(awk '/^shell\|rescanPlugins$/ { r = NR } /^shell\|enablePlugin\|graveklar\.face\|\{\}$/ { e = NR } END { print (r > 0 && e > r) ? "true" : "false" }' <<<"$calls")"
check "…and no staging folder or scratch clone is left" "0 0" "$(find "$PD" -maxdepth 1 -name '.add.tmp.*' | wc -l) $(scratch_left)"
s=$(np state)
check "state: Face ID current, enabled, needs setup (the camera)" "current true needed" "$(field '"\(.state) \(.enabled) \(.setup)"' "$(entry graveklar.face "$s")")"

chmod 000 "$sb/gh/omarchy-face.git"
started=$(date +%s%3N)
s=$(np state --local)
took=$(( $(date +%s%3N) - started ))
chmod 755 "$sb/gh/omarchy-face.git"
echo "  ${DIM}state --local took ${took} ms${RESET}"
check "state --local with GitHub unreadable: under 2 s, installed, enabled, unchecked, local" "true true true unchecked unchecked true" \
  "$(under "$took" 2000) $(field '"\(.installed) \(.enabled) \(.relation) \(.state)"' "$(entry graveklar.face "$s")") $(field .local "$s")"

mark=$(log_mark calls.log)
out=$(np run install graveklar.face "$st" "$sha"); rc=$?
check "install again: already-installed, and upstream add never ran" "1 already-installed 0" \
  "$rc $(field .reason "$out") $(log_since calls.log "$mark" | grep -c '^omarchy plugin add')"

# A wrong id, caught before anything lands.
evil=(env "${HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$sb/catalogue-evil.json" "$SCRIPT")
p=$("${evil[@]}" preview kalinewb.profiles)
mark=$(log_mark shell.log); cmark=$(log_mark calls.log)
out=$("${evil[@]}" run install kalinewb.profiles "$st" "$(head_of evil-profiles)"); rc=$?
check "a repo whose manifest isn't the catalogue id: preview refused, run failed wrong-id naming it" "wrong-id false 1 wrong-id true" \
  "$(field '"\(.refused) \(.ok)"' "$p") $rc $(field .reason "$out") $(field '.message | contains("evil.profiles")' "$out")"
check "…nothing landed: no folder, no staging, upstream never ran, no rescan or enable" "false false 0 0 0" \
  "$(exists "$PD/evil.profiles") $(exists "$PD/kalinewb.profiles") $(find "$PD" -maxdepth 1 -name '.add.tmp.*' | wc -l) $(log_since calls.log "$cmark" | grep -c '^omarchy plugin add') $(log_since shell.log "$mark" | grep -cE 'rescanPlugins|enablePlugin')"

# A wrong id, caught only after upstream's own clone.
sneaky=(env "${HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$sb/catalogue-sneaky.json" NOTCH_PLUGINS_OMARCHY="$sb/bin/omarchy-sneaky" "$SCRIPT")
mark=$(log_mark shell.log)
out=$("${sneaky[@]}" run install kalinewb.profiles "$st" "$(head_of sneaky-profiles)"); rc=$?
refused=$(find "$PD" -mindepth 1 -maxdepth 1 -name '.notch-refused.evil.profiles.*')
check "GitHub renamed the id between the check and upstream's clone: failed wrong-id" "1 wrong-id" "$rc $(field .reason "$out")"
check "…the folder was moved aside to one .notch-refused.evil.profiles.*, named in movedTo" "false 1 true" \
  "$(exists "$PD/evil.profiles") $(grep -c . <<<"$refused") $([[ -n $refused && $(field .movedTo "$out") == "$refused" ]] && echo true || echo false)"
check "…never enabled, and the shell's plugin list doesn't have it" "0 false" \
  "$(log_since shell.log "$mark" | grep -c enablePlugin) $("$sb/stubs/omarchy-shell" shell listPlugins | jq 'any(.[]; .id == "evil.profiles")')"
rm -rf "$PD"/.notch-refused.*

cmark=$(log_mark calls.log)
barc=(env "${HOOKS[@]}" NOTCH_PLUGINS_CATALOGUE="$sb/catalogue-bar.json" "$SCRIPT")
p=$("${barc[@]}" preview kalinewb.profiles)
out=$("${barc[@]}" run install kalinewb.profiles "$st" "$(head_of bar-profiles)"); rc=$?
check "a repo whose manifest is a bar: preview refused, failed bar-kind, no folder, upstream never ran" "bar-kind 1 bar-kind false 0" \
  "$(field .refused "$p") $rc $(field .reason "$out") $(exists "$PD/kalinewb.profiles") $(log_since calls.log "$cmark" | grep -c '^omarchy plugin add')"

echo 1 >"$sb/stub-rescan-exit"
mark=$(log_mark calls.log)
out=$(np run install kalinewb.profiles "$st" "$(head_of omarchy-profiles)"); rc=$?
check "upstream add exits 1 (its rescan failed) but the plugin landed: done and enabled" "rc=1 0 done true" \
  "$(log_since calls.log "$mark" | grep -A1 '^omarchy plugin add' | grep -o 'rc=[0-9]*' | head -1) $rc $(field '"\(.phase) \(.enabled)"' "$out")"
rm -f "$sb/stub-rescan-exit"
forget_profiles

echo kalinewb.profiles >"$sb/stub-hide"
mark=$(log_mark shell.log)
started=$(date +%s%3N)
out=$(env "${HOOKS[@]}" NOTCH_PLUGINS_DISCOVER_MS=600 "$SCRIPT" run install kalinewb.profiles "$st" "$(head_of omarchy-profiles)"); rc=$?
waited=$(( $(date +%s%3N) - started ))
check "the shell never sees it: after the discovery wait, done with enabled:false (never failed), no enable" "0 done false 0 1" \
  "$rc $(field '"\(.phase) \(.enabled)"' "$out") $(log_since shell.log "$mark" | grep -c enablePlugin) $((waited >= 600))"
forget_profiles
echo 5 >"$sb/stub-list-sleep"
rm -f "$st"
env "${HOOKS[@]}" NOTCH_PLUGINS_DISCOVER_MS=600 "$SCRIPT" run install kalinewb.profiles "$st" "$(head_of omarchy-profiles)" >/dev/null &
job=$!
until [[ $(jq -r .step "$st" 2>/dev/null) == enabling ]] || ! kill -0 "$job" 2>/dev/null; do sleep 0.05; done
t1=$(date +%s%3N)
wait "$job"
took=$(( $(date +%s%3N) - t1 ))
rm -f "$sb/stub-list-sleep" "$sb/stub-hide"
echo "  ${DIM}discovery with a shell that hangs 5 s per list: ${took} ms${RESET}"
check "…a hung shell: the wait is bounded by the clock, not by polls × timeouts; the shipped wait is 10 s" "true done 10000" \
  "$(under "$took" 3500) $(jq -r .phase "$st") $(sed -n 's/.*NOTCH_PLUGINS_DISCOVER_MS:-\([0-9]*\)}.*/\1/p' "$SCRIPT" | tail -n 1)"
forget_profiles

# Update
publish omarchy-face Helper.qml "Helper tweak"
s=$(np state)
check "a published commit that isn't an entry point: update-available, behind 1" "update-available 1" "$(field '"\(.state) \(.behind)"' "$(entry graveklar.face "$s")")"
p=$(np preview graveklar.face)
check "preview: behind 1, its subject, 1 file, a restart likely, still Face ID" "true 1 Helper tweak 1 true graveklar.face " \
  "$(field '"\(.ok) \(.behind) \(.commits[0].subject) \(.files) \(.restartLikely) \(.manifestId) \(.refused)"' "$p")"
old=$(git -C "$PD/graveklar.face" rev-parse HEAD)
out=$(np run update graveklar.face "$st" "$old"); rc=$?
check "update with a stale commit: changed, HEAD unchanged" "1 changed $old" "$rc $(field .reason "$out") $(git -C "$PD/graveklar.face" rev-parse HEAD)"
new=$(head_of omarchy-face)
out=$(np run update graveklar.face "$st" "$new"); rc=$?
check "update with the confirmed commit: done, to = it, restart suggested" "0 done $new true $new" \
  "$rc $(field '"\(.phase) \(.to) \(.restartSuggested)"' "$out") $(git -C "$PD/graveklar.face" rev-parse HEAD)"
publish omarchy-face FacePanel.qml "Entry point tweak"
out=$(np run update graveklar.face "$st" "$(head_of omarchy-face)"); rc=$?
check "an entry-point-only update: done, no restart suggested" "0 done false" "$rc $(field '"\(.phase) \(.restartSuggested)"' "$out")"
publish_manifest omarchy-face '.id = "evil.face"' "Rename"
old=$(git -C "$PD/graveklar.face" rev-parse HEAD)
p=$(np preview graveklar.face)
mark=$(log_mark calls.log)
out=$(np run update graveklar.face "$st" "$(head_of omarchy-face)"); rc=$?
check "a published commit renaming the manifest id: preview refused, update wrong-id, HEAD unchanged, upstream never ran" \
  "wrong-id 1 wrong-id $old 0" "$(field .refused "$p") $rc $(field .reason "$out") $(git -C "$PD/graveklar.face" rev-parse HEAD) $(log_since calls.log "$mark" | grep -c '^omarchy plugin update')"
publish_manifest omarchy-face '.id = "graveklar.face"' "Rename back"

# Refusals
publish omarchy-face Helper.qml "One more"
echo "local" >"$PD/graveklar.face/local.txt" && git -C "$PD/graveklar.face" add local.txt && git -C "$PD/graveklar.face" commit -qm "local"
check "a local commit: local-changes" "local-changes" "$(field .state "$(entry graveklar.face "$(np state)")")"
mark=$(log_mark calls.log)
out=$(np run update graveklar.face "$st" "$(head_of omarchy-face)"); rc=$?
check "…and update refuses before upstream runs" "1 local-changes 0" "$rc $(field .reason "$out") $(log_since calls.log "$mark" | grep -c '^omarchy plugin update')"
git -C "$PD/graveklar.face" reset -q --hard HEAD~1
echo "// edit" >>"$PD/graveklar.face/Service.qml"
check "a tracked edit: local-changes" "local-changes" "$(field .state "$(entry graveklar.face "$(np state)")")"
git -C "$PD/graveklar.face" checkout -q Service.qml
mkdir -p "$PD/kalinewb.profiles" && cp -r "$FIX/profiles/." "$PD/kalinewb.profiles/"
check "a plain folder copy: other-source, and its status command never ran" "other-source unknown" \
  "$(field '"\(.state) \(.setup)"' "$(entry kalinewb.profiles "$(np state)")")"
out=$(np run update kalinewb.profiles "$st" "$(head_of omarchy-profiles)"); rc=$?
check "…and update refuses: not-git" "1 not-git" "$rc $(field .reason "$out")"
rm -rf "$PD/kalinewb.profiles"
mv "$sb/gh/omarchy-face.git" "$sb/gh/away.git"
check "the pinned repo can't be reached: offline" "offline" "$(field .state "$(entry graveklar.face "$(np state)")")"
mv "$sb/gh/away.git" "$sb/gh/omarchy-face.git"
out=$(env "${HOOKS[@]}" FIXTURE_FACE_INSTALL=running "$SCRIPT" run update graveklar.face "$st" "$(head_of omarchy-face)"); rc=$?
check "Face's own root build running: plugin-busy" "1 plugin-busy" "$rc $(field .reason "$out")"

# A stopped job: the runner alone is signalled.
stopped() { # stopped <signal>: "<exit code> <ms to exit> <phase> <reason>"
  local job t0 rc
  rm -f "$sb/hang.pid"
  # A background job of a script starts with INT ignored; give it back.
  env --default-signal=INT "${HOOKS[@]}" NOTCH_PLUGINS_OMARCHY="$sb/bin/omarchy-hang" "$SCRIPT" run install kalinewb.profiles "$st" "$(head_of omarchy-profiles)" >/dev/null &
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
out=$(np setup graveklar.face)
check "setup: Face's own panel, over IPC, with exactly 4 arguments" "true graveklar.face|open|setup|" "$(field .ok "$out") $(log_since shell.log "$mark" | tail -n 1)"
touch "$sb/stub-target-missing"
check "a plugin whose widget isn't hosted: not-hosted" '{"ok":false,"reason":"not-hosted"}' "$(np setup graveklar.face | jq -c '{ok, reason}')"
rm -f "$sb/stub-target-missing"
np state >/dev/null
out=$(np review graveklar.face)
for _ in $(seq 1 20); do [[ -s $sb/terminal.log ]] && break; sleep 0.05; done
check "review of an available update: the terminal gets exactly upstream's own update" "update 1|omarchy plugin update graveklar.face" \
  "$(field .mode "$out") $(tail -n 1 "$sb/terminal.log")"

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
profiles_ready='.checkedAt > 0 and .fullCheckedAt > 0 and ((.entries[] | select(.id == "kalinewb.profiles") | .state) == "not-installed")'

start
rest_height=$(ipc geometry | jq -r .window.height)
ipc plugins open >/dev/null
until_true 100 '.fullCheckedAt > 0' ; sleep 1.2
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
check "plugins status: two entries plus the notch, in the runner's states" "2 self $runner" \
  "$(field '"\(.entries | length) \(.self.state) \([.entries[].state] | join(" "))"' "$s")"

check "confirm with no card: no-such-button, and nothing ran" "no-such-button false" "$(ipc pluginsPress confirm) $(exists "$job_file")"
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.confirm.ready'
s=$(status)
check "Install… opens the card: install, the pinned URL" "install file://$sb/gh/omarchy-profiles.git true" "$(field '"\(.confirm.action) \(.confirm.url) \(.open)"' "$s")"
check "…with the exact commit GitHub has, and nothing ran" "$(head_of omarchy-profiles) false" "$(field .confirm.sha "$s") $(exists "$job_file")"
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
echo "  ${DIM}notice after $took ms; $(status | jq -c '{local, checking, fullCheckedAt}')${RESET}"
check "GitHub unreadable: a new notch shows done within 2 s of answering (the local probe decides)" "done true" \
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
ipc pluginsPress setup:graveklar.face >/dev/null
for _ in $(seq 1 30); do log_since shell.log "$mark" | grep -q '^graveklar.face|open|setup|$' && break; sleep 0.1; done
check "Open setup hands off to Face's own panel, and the page gets out of its way" "1 false" \
  "$(log_since shell.log "$mark" | grep -cx 'graveklar.face|open|setup|') $(ipc geometry | jq -r .plugins.open)"

ipc plugins open >/dev/null; sleep 0.9
ipc settings >/dev/null; sleep 0.5
check "the settings over the page close the page" "false true settings" "$(ipc geometry | jq -r '"\(.plugins.open) \(.settingsOpen) \(.view)"')"
ipc settings >/dev/null; ipc menu root >/dev/null; sleep 0.5
ipc plugins open >/dev/null; sleep 0.5
check "the page over the menu closes the menu" "false true plugins" "$(ipc geometry | jq -r '"\(.menu.open) \(.plugins.open) \(.view)"')"
ipc pluginsPress updates:graveklar.notch >/dev/null; sleep 0.6
check "the notch's own row opens the settings at Updates, unfolded" "false true true" \
  "$(ipc geometry | jq -r '"\(.plugins.open) \(.settingsOpen) \(.plugins.settingsUpdatesOpen)"')"
ipc settings >/dev/null; sleep 0.8
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

# A repository that isn't the plugin any more: the card refuses.
forget_profiles
start NOTCH_PLUGINS_CATALOGUE="$sb/catalogue-evil.json"
ipc plugins open >/dev/null
until_true 100 '.fullCheckedAt > 0'
ipc pluginsPress install:kalinewb.profiles >/dev/null
until_true 100 '.preview.id != null'
check "the card for a repository whose id changed: refused wrong-id, no Install button, nothing ran" "wrong-id false no-such-button" \
  "$(status | jq -r '"\(.confirm.refused) \(.confirm.ready)"') $(ipc pluginsPress confirm)"
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
buttons() { local n s; n=$(ipc geometry | jq -r .plugins.updateButtons.notice); ipc settings >/dev/null; sleep 0.6
  s=$(ipc geometry | jq -r .plugins.updateButtons.settings); ipc settings >/dev/null; sleep 0.8; echo "$s $n"; }
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
  "$(ipc pluginsPress install:graveklar.face) $(status | jq -r '"\(.enabled) \(.canAct) \(.checkedAt) \(.checking)"')"
check "no IPC verb installs: plugins install is an unknown action" '{"error":"unknown action"}' "$(ipc plugins install)"
stop

check "no QML errors" "none" "$(grep -E '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | grep . || echo none)"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}E. The live plugins folder${RESET}"
check "the live plugins folder's entries and mtimes are unchanged" "$marker" "$(live_marker)"

finish
