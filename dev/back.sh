#!/bin/bash

# The way back -- the strip at the top centre of an open panel -- as numbers.
#
#   ./dev/back.sh
#
# 1. The press itself, in a bare Qt test (qmltestrunner, offscreen): the strip
#    under a parent that handles taps like the notch's island. A press must
#    step back once and must not also reach the island's own click.
# 2. The logic, on a throwaway notch over IPC: when the strip is offered, what
#    one press does at each depth, and that the menu goes up one level before it
#    leaves. `notch back` is the call the strip makes.
# 3. A plugin's panel with pages of its own (dev/fixtures/back): the first
#    press goes back inside it, the one at its home closes it, and a panel with
#    no such members is closed at once, as before.

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

work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-back.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

echo "${BOLD}The press on the strip${RESET}  ${DIM}BackStrip.qml, qmltestrunner offscreen${RESET}"
RUNNER=/usr/lib/qt6/bin/qmltestrunner
if [[ -x $RUNNER ]]; then
  mkdir -p "$work/t"
  sed -e "s#@REPO@#$REPO#g" "$REPO/dev/harness/back-strip/tst_back.qml.in" >"$work/t/tst_back.qml"
  out=$(cd "$work/t" && QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$work}" timeout 60 "$RUNNER" -input "$work/t" 2>&1)
  while IFS= read -r line; do
    name=${line#* : BackStrip::}; name=${name%%(*}
    case $line in
      PASS*) check "${name#test_}" pass pass ;;
      FAIL*) check "${name#test_}" pass "FAIL: $(grep -A3 -F "$line" <<<"$out" | grep -E 'Actual|Expected' | tr -s ' ' | tr '\n' ' ')" ;;
    esac
  done < <(grep -E '^(PASS|FAIL).*::test_' <<<"$out")
  check "the test ran all four cases" "4" "$(grep -cE '^(PASS|FAIL).*::test_' <<<"$out")"
else
  check "qmltestrunner is installed" "yes" "no"
fi

echo; echo "${BOLD}The way back, over IPC${RESET}"
root="$work/root"; mkdir -p "$root"
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
rep() { ipc backReport | jq -r '"\(.offered) \(.depth) \(.panel) \(.menu)"'; }
settle() { sleep 0.9; }

NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' \
  quickshell -p "$root" -n >"$work/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
for _ in $(seq 1 30); do sleep 0.1; [[ $(ipc geometry | jq -r .menu.rowsLoaded) == true ]] && break; done
sleep 0.8

check "nothing open: nothing to press" "false 0 false " "$(rep)"
ipc view settings >/dev/null; settle
check "the settings, opened from rest: the strip is offered" "true 0 true " "$(rep)"
check "…one press closes them: there was nothing further back" "closed compact" "$(ipc back) $(settle; ipc geometry | jq -r .state)"
ipc view settings >/dev/null; settle
ipc view setup >/dev/null; settle
check "Setup, one step in: offered, one step behind" "true 1 true " "$(rep)"
check "…a press goes back to the settings" "back true" "$(ipc back) $(settle; ipc geometry | jq -r .settingsOpen)"
check "…and another closes, because that was the way in" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .settingsOpen)"

ipc menu root >/dev/null; settle
check "the menu at its top: offered" "true 0 true root" "$(rep)"
check "…a press closes it" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .menu.open)"
ipc menu system >/dev/null; settle
check "the menu inside a submenu" "true 0 true system" "$(rep)"
check "…a press goes up one level and leaves the menu open" "back true root" "$(ipc back) $(settle; ipc geometry | jq -r '.menu.open') $(rep | cut -d' ' -f4)"
check "…the next closes it" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .menu.open)"

ipc view settings >/dev/null; settle
ipc menu system >/dev/null; settle
check "a submenu opened from the settings: two steps to take" "true 1 true system" "$(rep)"
check "…the first goes up the menu, still on the menu" "back root 1" "$(ipc back) $(settle; rep | cut -d' ' -f4) $(rep | cut -d' ' -f2)"
check "…the second goes back to the settings" "back true" "$(ipc back) $(settle; ipc geometry | jq -r .settingsOpen)"
ipc collapse >/dev/null; settle

check "no QML errors in the run" "none" "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs.log" || echo none)"

kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""

# --- 3. a plugin's panel with pages of its own ------------------------------------------

echo; echo "${BOLD}A plugin's panel with pages of its own${RESET}  ${DIM}dev/fixtures/back, SURFACE-HOSTING.md section 4${RESET}"
plugins="$work/plugins"; mkdir -p "$plugins" "$work/state" "$work/markers" "$work/bin"
cp -r "$REPO/dev/fixtures/back/plugins/acme.pages" "$plugins/acme.pages"
cp -r "$REPO/dev/fixtures/platform/plugins/acme.demo" "$plugins/acme.demo"
root2="$work/root2"; mkdir -p "$root2"
ln -s "$SHELL_PATH/shell/Commons" "$root2/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root2/Ui"
ln -s "$SHELL_PATH/shell/services" "$root2/services"
ln -s "$REPO" "$root2/notch"
cp "$REPO/dev/harness/platform-shell.qml" "$root2/shell.qml"
printf 'import QtQuick\nimport qs.Commons\nimport qs.Ui\nItem { }\n' >"$root2/Probe.qml"
printf '#!/bin/bash\necho "$*" >> "%s/omarchy-shell.log"\necho "Target not found." >&2\nexit 1\n' "$work" >"$work/bin/omarchy-shell"
chmod +x "$work/bin/omarchy-shell"
ipc() { quickshell ipc -p "$root2" call notch "$@" 2>/dev/null; }
rep() { ipc backReport | jq -r '"\(.offered) \(.depth) \(.panel) [\(.inner)]"'; }
pages() { grep -a 'PAGES ' "$work/qs2.log" | tail -n 1 | sed 's/.*PAGES //'; }

env PATH="$work/bin:$PATH" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
  NOTCH_FORCE_PLATFORM=1 NOTCH_PLUGINS_DIR="$plugins" NOTCH_PLATFORM_ENABLED="*" \
  NOTCH_PLATFORM_STATE_DIR="$work/state" NOTCH_FIXTURE_MARKER_DIR="$work/markers" \
  NOTCH_PLATFORM_WIDGETS='{}' NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' \
  quickshell -p "$root2" -n >"$work/qs2.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc integrations | jq -r '.scannedAt > 0') == true ]] && break; done
sleep 0.5
check "both fixture panels are accepted" "acme.demo,acme.pages" \
  "$(ipc integrations | jq -r '[.list[] | select(.accepted) | .id] | join(",")')"
check "the notch says it can ask a panel to go back (the feature word)" "true" \
  "$(ipc integrations | jq -r '.features | index("panelBack") != null')"

# The pages, three deep.
check "opened three pages deep" "opened" "$(ipc panel acme.pages deep:2)"; settle
check "…the panel is on its last page" "home/p1/p2" "$(pages)"
check "the strip is offered, and the report names the panel that will take the press" "true 0 true [acme.pages]" "$(rep)"
check "press 1 goes back one page inside the panel and leaves the notch open" "inside home/p1 true" \
  "$(ipc back) $(settle; pages) $(ipc geometry | jq -r .integration.open)"
check "press 2 goes back to the home page, still open" "inside home true" \
  "$(ipc back) $(settle; pages) $(ipc geometry | jq -r .integration.open)"
check "at the home the panel has nothing to give: not named in the report" "true 0 true []" "$(rep)"
check "press 3 closes the notch's panel" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .integration.open)"

# The same panel at its home from the start.
ipc panel acme.pages main >/dev/null; settle
check "opened at the home: the first press closes, as before" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .integration.open)"

# The panel's pages come before the notch's own history.
ipc panel acme.demo main >/dev/null; settle
ipc panel acme.pages deep:1 >/dev/null; settle
check "a panel opened over another: a page inside it and one step behind it" "true 1 true [acme.pages] home/p1" "$(rep) $(pages)"
check "press 1 goes back inside the panel, the notch's history untouched" "inside home acme.pages 1" \
  "$(ipc back) $(settle; pages) $(ipc geometry | jq -r .integration.id) $(rep | cut -d' ' -f2)"
check "press 2 goes back to the panel under it, as it always did" "back acme.demo 0" \
  "$(ipc back) $(settle; ipc geometry | jq -r .integration.id) $(rep | cut -d' ' -f2)"
check "press 3 closes them" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .integration.open)"

# A panel that cannot say whether it moved, or that fails, never traps the press.
ipc panel acme.pages mute:2 >/dev/null; settle
check "a panel that answers nothing: its page moved, and the press is not claimed (the notch closes)" "closed home/p1 false" \
  "$(ipc back) $(settle; pages) $(ipc geometry | jq -r .integration.open)"
ipc panel acme.pages raises:2 >/dev/null; settle
check "a panel whose goBackInside throws: the press still closes the notch" "closed false" \
  "$(ipc back) $(settle; ipc geometry | jq -r .integration.open)"
check "…and the failure is in the log, not a crash" "1" "$(grep -ac "goBackInside failed" "$work/qs2.log")"

# A panel with neither member.
ipc panel acme.demo main >/dev/null; settle
check "a panel with no members: offered, and no inner back named" "true 0 true []" "$(rep)"
check "…the first press closes it, as before" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .integration.open)"

# --- opened from one of the notch's own pages: back goes there, not to nothing ------------

echo; echo "${BOLD}A panel opened from the settings, the menu or Plugins${RESET}"
# The notch's own page is what a panel was opened from, so it is what Back
# returns to once the panel's own pages are used up (the open used to clear the
# page first and then take its snapshot, which was empty).
ipc view settings >/dev/null; settle
ipc panel acme.pages deep:2 >/dev/null; settle
check "from the settings: two pages deep, one step behind" "true 1 true [acme.pages] home/p1/p2" "$(rep) $(pages)"
check "…press 1 goes back a page inside the panel" "inside home/p1" "$(ipc back) $(settle; pages)"
check "…press 2 goes back to its home, the settings still behind it" "inside home 1" "$(ipc back) $(settle; pages) $(rep | cut -d' ' -f2)"
check "…press 3 lands on the settings: the panel is closed, the notch is not" "back true false" \
  "$(ipc back) $(settle; ipc geometry | jq -r '"\(.settingsOpen) \(.integration.open)"')"
check "…press 4 closes them: that was the way in" "closed false compact" \
  "$(ipc back) $(settle; ipc geometry | jq -r '"\(.settingsOpen) \(.state)"')"

ipc menu root >/dev/null; settle
ipc panel acme.demo main >/dev/null; settle
check "from the menu: the panel is open, the menu one step behind" "true 1 true [] true" \
  "$(rep) $(ipc geometry | jq -r .integration.open)"
check "…Back returns to the menu" "back true false" \
  "$(ipc back) $(settle; ipc geometry | jq -r '"\(.menu.open) \(.integration.open)"')"
check "…and the next one closes it" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .menu.open)"

ipc plugins open >/dev/null; settle
ipc panel acme.pages deep:1 >/dev/null; settle
check "from the Plugins page: a page deep, the Plugins page one step behind" "true 1 true [acme.pages] home/p1" "$(rep) $(pages)"
check "…press 1 goes back inside the panel" "inside home" "$(ipc back) $(settle; pages)"
check "…press 2 returns to the Plugins page" "back true false" \
  "$(ipc back) $(settle; ipc geometry | jq -r '"\(.plugins.open) \(.integration.open)"')"
check "…press 3 closes it" "closed false" "$(ipc back) $(settle; ipc geometry | jq -r .plugins.open)"

# One panel over another over the settings: each step is kept.
ipc view settings >/dev/null; settle
ipc panel acme.demo main >/dev/null; settle
ipc panel acme.pages main >/dev/null; settle
check "a panel over a panel over the settings: two steps behind" "true 2 true [] acme.pages" "$(rep) $(ipc geometry | jq -r .integration.id)"
check "…Back goes to the first panel, then the settings, then closes" "back acme.demo back true closed false" \
  "$(ipc back) $(settle; ipc geometry | jq -r .integration.id) $(ipc back) $(settle; ipc geometry | jq -r .settingsOpen) $(ipc back) $(settle; ipc geometry | jq -r .settingsOpen)"

# Opened from the resting notch the last press closes, and a step taken in
# another visit leaves nothing behind to jump to.
ipc view settings >/dev/null; settle
ipc panel acme.demo main >/dev/null; settle
ipc panel acme.demo main >/dev/null; settle
check "the same panel asked for again closes it, and the settings under it with it" "false 0 compact" \
  "$(ipc geometry | jq -r .integration.open) $(rep | cut -d' ' -f2) $(ipc geometry | jq -r .state)"
ipc panel acme.pages main >/dev/null; settle
check "…and the next panel, opened from rest, has no history: depth 0" "true 0 true [] closed" \
  "$(rep) $(ipc back)"
settle


check "no QML errors in the run" "none" "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs2.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$work/qs2.log" || echo none)"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
