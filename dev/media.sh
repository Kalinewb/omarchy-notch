#!/bin/bash

# The notch's one media source, as numbers.
#
#   ./dev/media.sh
#
# The glance (now playing, and the track-change peek) must show omarchy.media's
# activePlayer through the host facade -- the same player the stock media
# widget in the row shows -- and nothing when there is no facade or no active
# player. Runs the real Bar.qml and the real stock media BarWidget.qml against a
# fake facade whose players and activePlayer are scripted over IPC.

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
WIDGET="$SHELL_PATH/shell/plugins/services/media/BarWidget.qml"
[[ -f $WIDGET ]] || { echo "media: no stock media widget at $WIDGET" >&2; exit 1; }

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-media.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/media-shell.qml" "$root/shell.qml"

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
test_ipc() { quickshell ipc -p "$root" call notchtest "$@" 2>/dev/null; }
media() { ipc geometry | jq -c '{state, media}'; }
start() { # start <facade 1|0>
  NOTCH_HARNESS=1 NOTCH_FAKE_FACADE="$1" NOTCH_MEDIA_WIDGET="$WIDGET" NOTCH_HARNESS_CONFIG='{"compact":["media"],"openWith":["click"],"batteryPeek":false}' \
    quickshell -p "$root" -n >"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  sleep 2.3   # past the notch's 2 s "a track already playing at start is not news" window
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

echo "${BOLD}Media source${RESET}  ${DIM}plugin: $REPO${RESET}"
echo

direct=$(git -C "$REPO" grep -c 'Quickshell.Services.Mpris' -- '*.qml' ':!dev/**' 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')
check "no plugin QML imports Quickshell.Services.Mpris (one media source)" "0" "$direct"

# --- a background player that is paused, and one that is playing -----------------
start 1
test_ipc player org.mpris.MediaPlayer2.bgpaused "Paused in another workspace" false >/dev/null
test_ipc player org.mpris.MediaPlayer2.spotify "Actually playing" true >/dev/null
set_to=$(test_ipc active org.mpris.MediaPlayer2.spotify)
check "the scripted facade accepted the players and the active one" "org.mpris.MediaPlayer2.spotify" "$set_to"
sleep 0.8
a=$(media)
echo "  ${DIM}paused player listed first, activePlayer = the playing one: $a${RESET}"
check "the glance shows the active (playing) player" "org.mpris.MediaPlayer2.spotify|Actually playing" "$(jq -r '"\(.media.glance.key)|\(.media.glance.title)"' <<<"$a")"
check "…not the paused background player listed before it" "true" "$(jq -r '.media.glance.key != "org.mpris.MediaPlayer2.bgpaused"' <<<"$a")"
check "the stock media widget in the row shows the same player" "org.mpris.MediaPlayer2.spotify" "$(jq -r '.media.widgets[0].key' <<<"$a")"

# --- the active player changes ----------------------------------------------------
same=0; samples=""
for step in bgpaused spotify bgpaused; do
  test_ipc player org.mpris.MediaPlayer2.bgpaused "Paused in another workspace" "$([[ $step == bgpaused ]] && echo true || echo false)" >/dev/null
  test_ipc player org.mpris.MediaPlayer2.spotify "Actually playing" "$([[ $step == spotify ]] && echo true || echo false)" >/dev/null
  test_ipc active "org.mpris.MediaPlayer2.$step" >/dev/null
  sleep 0.6
  m=$(media)
  g=$(jq -r .media.glance.key <<<"$m"); w=$(jq -r '.media.widgets[0].key' <<<"$m")
  samples+=" $step→glance:${g##*.}/widget:${w##*.}"
  [[ $g == "$w" && $g == "org.mpris.MediaPlayer2.$step" ]] && same=$((same + 1))
done
echo "  ${DIM}player changes:$samples${RESET}"
check "across three player changes the glance and the row widget report the same player each time" "3" "$same"

# --- a track change on the active player peeks; one on another player does not ---
# The loop above left bgpaused active and playing, and its player switches
# peeked; wait those out (3.5 s) so each check below starts with no peek.
mediapeek() { ipc geometry | jq -r .media.mediaPeek; }
sleep 3.8
check "starting with no media peek showing" "false" "$(mediapeek)"
test_ipc retitle org.mpris.MediaPlayer2.spotify "Another song, on the player that is not active" >/dev/null
sleep 0.5
check "a new title on a player that is not active claims nothing (no media peek)" "false" "$(mediapeek)"
test_ipc retitle org.mpris.MediaPlayer2.bgpaused "Next song on the active player" >/dev/null
sleep 0.5
check "a new title on the active, playing player makes a media peek" "true" "$(mediapeek)"
sleep 3.8
check "…which ends after the peek duration" "false" "$(mediapeek)"

# --- activePlayer null while players exist -------------------------------------------
test_ipc active "" >/dev/null
sleep 0.6
n=$(media)
echo "  ${DIM}activePlayer null, two players still listed: $n${RESET}"
check "null activePlayer: the glance has no media and no width" "false 0 " "$(jq -r '"\(.media.glance.hasMedia) \(.media.glance.width) \(.media.glance.key)"' <<<"$n")"
check "…and the active player going away (playing → null) makes no media peek" "false" "$(jq -r .media.mediaPeek <<<"$n")"
check "…and the row widget has none either" "" "$(jq -r '.media.widgets[0].key' <<<"$n")"
test_ipc player org.mpris.MediaPlayer2.spotify "Playing again, but not active" true >/dev/null
test_ipc retitle org.mpris.MediaPlayer2.spotify "A title change nobody is showing" >/dev/null
sleep 0.6
check "…and a playing, listed player changing title claims nothing (no media peek)" "false" "$(mediapeek)"
if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi
stop

# --- no facade at all ---------------------------------------------------------------
start 0
test_ipc player org.mpris.MediaPlayer2.spotify "Playing with no facade" true >/dev/null
test_ipc active org.mpris.MediaPlayer2.spotify >/dev/null
test_ipc retitle org.mpris.MediaPlayer2.spotify "Changed with no facade" >/dev/null
sleep 0.8
f=$(media)
echo "  ${DIM}no omarchy.media facade: $f${RESET}"
check "no facade: the notch reports none" "false" "$(jq -r .media.facade <<<"$f")"
check "…the glance is empty" "false 0" "$(jq -r '"\(.media.glance.hasMedia) \(.media.glance.width)"' <<<"$f")"
check "…and nothing claims the notch (no media peek)" "false" "$(jq -r .media.mediaPeek <<<"$f")"
stop

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
