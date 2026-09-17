#!/bin/bash

# The notch's own updates, as numbers.
#
#   ./dev/update.sh
#
# Nothing here touches the live plugin or GitHub. A sandbox holds a bare
# "GitHub" (cloned from this repo's HEAD), a "plugin" checkout of it, and a
# work clone that publishes newer versions.
#
# 1. bin/notch-update against the sandbox: every check state (current,
#    available, dirty, ahead, diverged, not-git, offline) with its versions and
#    counts; `run` fast-forwards and writes the status file (done, already up to
#    date, failed with the reason, refused while another run holds the lock, and
#    refused without a stand-in updater when pointed at a sandbox); `ack` and
#    `snooze`.
# 2. The pop-down in a throwaway notch pointed at the sandbox: a newer version
#    pops the notch down into the notice, and the notch's size equals the
#    notice's with its top edge on the screen edge and the notch's radius on
#    its buttons. Opening the notch covers it, and closing brings it back.
#    Later snoozes that version, across a restart, until a newer one comes out.
#    Update runs detached, fast-forwards the checkout, shows "done", then
#    clears itself. A failing update shows the reason until dismissed. A notch
#    that doesn't update itself never shows any of it.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
SCRIPT="$REPO/bin/notch-update"
sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-update.XXXXXX")
root="$sb/shell"
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.invalid \
       GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.invalid
git clone -q --bare "$REPO" "$sb/origin.git"
git clone -q "$sb/origin.git" "$sb/plugin"
git clone -q "$sb/origin.git" "$sb/work"
publish() { # publish <version> <subject>
  jq --arg v "$1" '.version = $v' "$sb/work/manifest.json" >"$sb/work/manifest.json.new" && mv "$sb/work/manifest.json.new" "$sb/work/manifest.json"
  git -C "$sb/work" commit -qam "$2" && git -C "$sb/work" push -q origin HEAD
}
origin_sha() { git -C "$sb/origin.git" rev-parse HEAD; }
field() { jq -r "$1" <<<"$2"; }
APPLY='git -C "$NOTCH_UPDATE_DIR" fetch -q origin HEAD && git -C "$NOTCH_UPDATE_DIR" merge -q --ff-only FETCH_HEAD'
base_version=$(jq -r .version "$sb/plugin/manifest.json")

echo "${BOLD}bin/notch-update${RESET}  ${DIM}sandbox $sb${RESET}"
c=$(NOTCH_UPDATE_DIR="$sb/plugin" "$SCRIPT" check)
check "current: the checkout is origin's HEAD" "current 0 0 $base_version" "$(field '"\(.state) \(.behind) \(.ahead) \(.localVersion)"' "$c")"

publish 9.9.1 "Test: a newer notch"
c=$(NOTCH_UPDATE_DIR="$sb/plugin" "$SCRIPT" check)
check "available: one commit behind, with both versions and the new subject" \
  "available 1 $base_version 9.9.1 Test: a newer notch $(origin_sha)" \
  "$(field '"\(.state) \(.behind) \(.localVersion) \(.remoteVersion) \(.subject) \(.remote)"' "$c")"

echo "# local edit" >>"$sb/plugin/README.md"
check "dirty: tracked local edits" "dirty" "$(NOTCH_UPDATE_DIR="$sb/plugin" "$SCRIPT" check | jq -r .state)"
git -C "$sb/plugin" checkout -q README.md

git clone -q "$sb/origin.git" "$sb/ahead"
echo "x" >"$sb/ahead/dev-note.txt" && git -C "$sb/ahead" add dev-note.txt && git -C "$sb/ahead" commit -qm "local"
check "ahead: a local commit origin doesn't have" "ahead 0 1" "$(NOTCH_UPDATE_DIR="$sb/ahead" "$SCRIPT" check | jq -r '"\(.state) \(.behind) \(.ahead)"')"

git clone -q "$sb/origin.git" "$sb/diverged"
git -C "$sb/diverged" reset -q --hard HEAD~1
echo "y" >"$sb/diverged/dev-note.txt" && git -C "$sb/diverged" add dev-note.txt && git -C "$sb/diverged" commit -qm "local"
check "diverged: each side has a commit the other doesn't" "diverged 1 1" "$(NOTCH_UPDATE_DIR="$sb/diverged" "$SCRIPT" check | jq -r '"\(.state) \(.behind) \(.ahead)"')"

mkdir -p "$sb/copy" && cp "$REPO/manifest.json" "$sb/copy/"
check "not-git: a copied install" "not-git" "$(NOTCH_UPDATE_DIR="$sb/copy" "$SCRIPT" check | jq -r .state)"

git clone -q "$sb/origin.git" "$sb/offline" && git -C "$sb/offline" remote set-url origin "$sb/missing.git"
check "offline: origin can't be reached" "offline" "$(NOTCH_UPDATE_DIR="$sb/offline" "$SCRIPT" check | jq -r .state)"

st="$sb/state/update.json"
NOTCH_UPDATE_DIR="$sb/plugin" NOTCH_UPDATE_APPLY="$APPLY" NOTCH_UPDATE_RESTART=none "$SCRIPT" run "$st"; rc=$?
s=$(cat "$st")
check "run: fast-forwards, and the status says done with the new commit and version" \
  "0 done $(origin_sha) 9.9.1 false $(origin_sha)" \
  "$rc $(field '"\(.phase) \(.to) \(.version) \(.seen)"' "$s") $(git -C "$sb/plugin" rev-parse HEAD)"
check "…with its start, finish and the commit it came from" "true" "$(field '.finishedAt >= .startedAt and .startedAt > 0 and (.from | length) == 40 and .from != .to' "$s")"
NOTCH_UPDATE_DIR="$sb/plugin" NOTCH_UPDATE_APPLY="$APPLY" NOTCH_UPDATE_RESTART=none "$SCRIPT" run "$st"
check "run again: done, already up to date" "done Already up to date." "$(jq -r '"\(.phase) \(.message)"' "$st")"
NOTCH_UPDATE_DIR="$sb/plugin" NOTCH_UPDATE_APPLY='echo "fetch failed: network down" >&2; exit 1' NOTCH_UPDATE_RESTART=none "$SCRIPT" run "$st"; rc=$?
check "a failing update: failed, with the updater's last line as the reason" "1 failed fetch failed: network down" "$rc $(jq -r '"\(.phase) \(.message)"' "$st")"
NOTCH_UPDATE_DIR="$sb/plugin" NOTCH_UPDATE_RESTART=none "$SCRIPT" run "$st"; rc=$?
check "pointed at a sandbox without a stand-in updater, it refuses (never the live plugin)" "2 failed" "$rc $(jq -r .phase "$st")"
mkdir -p "$st.lock" && echo $$ >"$st.lock/pid"
out=$(NOTCH_UPDATE_DIR="$sb/plugin" NOTCH_UPDATE_APPLY="$APPLY" NOTCH_UPDATE_RESTART=none "$SCRIPT" run "$st" 2>&1); rc=$?
check "a second run while one holds the lock is refused" "1 an update is already running" "$rc $(sed 's/^notch-update: //' <<<"$out")"
rm -rf "$st.lock"
"$SCRIPT" ack "$st"
check "ack marks the job seen" "true" "$(jq -r .seen "$st")"
"$SCRIPT" snooze "$sb/state/snoozed" "$(origin_sha)"
check "snooze remembers the commit" "$(origin_sha)" "$(cat "$sb/state/snoozed")"

# ---------------------------------------------------------------------------
echo; echo "${BOLD}The pop-down${RESET}"
mkdir -p "$root"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
ui_state="$sb/ui"
start() { # start <apply command> [more env...]
  local apply=$1; shift
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_FORCE_UPDATES=1 \
    NOTCH_UPDATE_DIR="$sb/plugin" NOTCH_UPDATE_STATE_DIR="$ui_state" NOTCH_UPDATE_APPLY="$apply" \
    NOTCH_UPDATE_RESTART=none NOTCH_UPDATE_FIRST_CHECK_MS=300 NOTCH_UPDATE_DONE_MS=1500 \
    NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"bottomRadius":8}' "$@" \
    quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc update status | jq -r .check.state) != unchecked ]] && break; done
  sleep 1.3
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

publish 9.9.2 "Test: pop-down"
start "$APPLY"
u=$(ipc update status); g=$(ipc geometry)
echo "  ${DIM}$(jq -c '{notice, check: (.check | {state, localVersion, remoteVersion, behind})}' <<<"$u"); $(jq -c '{state, target, bar, update: .update.size}' <<<"$g")${RESET}"
check "a newer version pops the notice down" "available notice true" "$(field '.notice' "$u") $(field '"\(.state) \(.update.noticeShown)"' "$g")"
check "the notch's target is the notice's size" "true" "$(field '.target.width == .update.size.width and .target.height == .update.size.height and .update.size.height > 32' "$g")"
check "…and it has arrived there, top edge on the screen edge, square top corners, radius 8" "true" \
  "$(field '(.bar.width - .target.width | fabs) < 0.5 and (.bar.height - .target.height | fabs) < 0.5 and .bar.y == 0 and .radii.topLeft == 0 and .radii.bottomLeft == 8' "$g")"
check "the notice is shown and takes clicks" "1 true" "$(field '"\(.update.host.opacity) \(.update.host.enabled)"' "$g")"
d=$(ipc design)
check "its buttons use the notch's radius" "0" "$(python3 -c '
import json,sys; d=json.loads(sys.argv[1]); r=d["radius"]
bad=[i for i in d["notice"] if i["drawn"] and not i["gradient"] and i["width"]>2 and i["height"]>2 and abs(i["radius"]-max(0,min(r,i["height"]/2,i["width"]/2)))>0.01]
print(len(bad))' "$d")"
ipc expand >/dev/null; sleep 0.9
check "opening the notch covers the notice" "expanded" "$(ipc geometry | jq -r .state)"
ipc collapse >/dev/null; sleep 1.0
check "…and closing it brings the notice back" "notice" "$(ipc geometry | jq -r .state)"

remote=$(origin_sha)
u=$(ipc update later); sleep 1.0
check "Later: the notice goes, the notch rests, and the version is snoozed" " compact $remote" \
  "$(field '.notice' "$u") $(ipc geometry | jq -r .state) $(cat "$ui_state/update-snoozed" 2>/dev/null)"
stop
start "$APPLY"
check "…still snoozed after a restart" "available " "$(ipc update status | jq -r '"\(.check.state) \(.notice)"')"
publish 9.9.3 "Test: a newer one"
ipc update check >/dev/null
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc update status | jq -r .check.remoteVersion) == 9.9.3 ]] && break; done
check "a newer version than the snoozed one pops down again" "available 9.9.3" "$(ipc update status | jq -r '"\(.notice) \(.check.remoteVersion)"')"

u=$(ipc update now)
check "Update: the notice turns to updating at once" "updating" "$(field .notice "$u")"
for _ in $(seq 1 100); do sleep 0.2; [[ $(ipc update status | jq -r .job.phase) == done ]] && break; done
u=$(ipc update status)
check "…the job ran detached and fast-forwarded the checkout" "done $(origin_sha) 9.9.3 $(origin_sha)" \
  "$(field '"\(.job.phase) \(.job.to) \(.job.version)"' "$u") $(git -C "$sb/plugin" rev-parse HEAD)"
check "…and the notice says done" "done" "$(ipc update status | jq -r .notice)"
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc update status | jq -r .notice) == "" ]] && break; done
sleep 1.0
check "…then clears itself, marked seen, and the notch rests" " true compact" \
  "$(ipc update status | jq -r '"\(.notice) \(.job.seen)"') $(ipc geometry | jq -r .state)"
stop

publish 9.9.4 "Test: this one fails"
start 'echo "fetch failed: network down" >&2; exit 1'
ipc update now >/dev/null
for _ in $(seq 1 100); do sleep 0.2; [[ $(ipc update status | jq -r .job.phase) == failed ]] && break; done
u=$(ipc update status)
check "a failing update shows why, and stays" "failed fetch failed: network down notice" "$(field '"\(.notice) \(.job.message)"' "$u") $(ipc geometry | jq -r .state)"
ipc update dismiss >/dev/null; sleep 1.0
check "…until dismissed" " true compact" "$(ipc update status | jq -r '"\(.notice) \(.job.seen)"') $(ipc geometry | jq -r .state)"
stop

NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_UPDATE_STATE_DIR="$ui_state" NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 1.2
check "a notch that doesn't update itself never checks or shows a notice" "false unchecked  compact" \
  "$(ipc update status | jq -r '"\(.enabled) \(.check.state) \(.notice)"') $(ipc geometry | jq -r .state)"
stop

if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$sb/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
