#!/bin/bash

# What the notch costs when nobody is touching it, per scenario.
#
#   ./dev/perf.sh                 every scenario
#   ./dev/perf.sh media hidden    just the ones whose name contains these
#   SAMPLE=10 ./dev/perf.sh       sample each one for 10 s instead of 6
#
# A notch nobody is touching has to cost what an idle Quickshell costs. That is
# the zero line this measures against, and it is measured, not assumed: the
# first row is a Quickshell with nothing in it at all.
#
# Why per scenario. The cost is never in the drawing; it is in whether anything
# is MOVING, because anything that moves repaints the notch's surface at 60 Hz
# for as long as it moves, and the compositor composites every one of those
# frames. Which things move depends entirely on the configuration -- what is in
# the glance, whether something is playing, whether a plugin sits in the row --
# so one number for "the notch" is not a number for anything. A live shell
# cannot answer it either: it has the user's whole plugin set in it and a
# pointer moving over it.
#
# This is a bench, not a suite: it takes about a minute and a half, the numbers
# move with the machine, and it is not part of ./dev/check.sh. Read it as
# "which rows are far above the zero line", never as an absolute.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; YELLOW=$'\e[33m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
SAMPLE=${SAMPLE:-6}

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
MEDIA_WIDGET="$SHELL_PATH/shell/plugins/services/media/BarWidget.qml"
EMPTY_WIDGET="$REPO/dev/fixtures/perf/EmptyWidget.qml"
[[ -f $MEDIA_WIDGET ]] || MEDIA_WIDGET=$EMPTY_WIDGET

root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-perf.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/media-shell.qml" "$root/shell.qml"
cp "$REPO/dev/harness/idle-shell.qml" "$root/idle.qml"

ipc() { quickshell ipc -p "$root" call "$@" 2>/dev/null; }
hz=$(getconf CLK_TCK)

# CPU of one process over SAMPLE seconds, as a percentage of one core, from
# /proc: utime + stime over wall time. `ps` reports an average over the
# process's whole life, which for a shell that has just started is mostly its
# own startup.
cpu_of() { # cpu_of <pid>
  local a b c d t0 t1
  read -r a b < <(awk '{print $14, $15}' "/proc/$1/stat" 2>/dev/null) || { echo "gone"; return; }
  t0=$(date +%s%N); sleep "$SAMPLE"
  read -r c d < <(awk '{print $14, $15}' "/proc/$1/stat" 2>/dev/null) || { echo "gone"; return; }
  t1=$(date +%s%N)
  awk -v u=$((c - a)) -v s=$((d - b)) -v hz="$hz" -v ns=$((t1 - t0)) \
    'BEGIN { printf "%.2f", (u + s) / hz / (ns / 1e9) * 100 }'
}

zero=""
row() { # row <name> <cpu> <note>
  local flag="$GREEN" verdict="at the zero line"
  if [[ -n $zero ]]; then
    over=$(awk -v c="$2" -v z="$zero" 'BEGIN { printf "%.2f", c - z }')
    if awk -v o="$over" 'BEGIN { exit !(o > 4) }'; then flag=$RED; verdict="+${over} over"
    elif awk -v o="$over" 'BEGIN { exit !(o > 1) }'; then flag=$YELLOW; verdict="+${over} over"
    else verdict="+${over}"; fi
  fi
  printf "  %s%6s%%%s  %-38s %s%s%s\n" "$flag" "$2" "$RESET" "$1" "$DIM" "${3:-$verdict}" "$RESET"
}

# Start a notch, let it settle, sample it, stop it.
#
# `player` is "" for no media at all, or "<title>|playing" / "<title>|paused".
# `expand` opens the notch over IPC before sampling, for the scenarios that
# measure a view the user has actually opened.
scenario() { # scenario <name> <config json> <widget> <player> [expand]
  local name=$1 config=$2 widget=$3 player=$4 expand=${5:-}
  [[ -n ${FILTER:-} ]] && [[ $name != *$FILTER* ]] && return
  NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_MEDIA_WIDGET="$widget" NOTCH_HARNESS_CONFIG="$config" \
    quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc notch geometry) == \{* ]] && break; done
  if [[ -n $player ]]; then
    ipc notchtest player perf "${player%%|*}" "$([[ ${player##*|} == playing ]] && echo true || echo false)" >/dev/null
    ipc notchtest active perf >/dev/null
  fi
  [[ -n $expand ]] && ipc notch "$expand" >/dev/null
  sleep 1.2   # let the open animation and the first layout finish
  local state cpu
  state=$(ipc notch geometry | jq -r '.state + "/" + .view' 2>/dev/null)
  cpu=$(cpu_of "$qs_pid")
  kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
  row "$name" "$cpu" "$state"
}

FILTER=${1:-}
echo "${BOLD}What the notch costs while nobody touches it${RESET}  ${DIM}${SAMPLE}s per scenario, % of one core${RESET}"
echo

# The zero line, measured the same way as everything else.
quickshell -p "$root/idle.qml" -n >>"$root/qs.log" 2>&1 &
qs_pid=$!
sleep 1.5
zero_cpu=$(cpu_of "$qs_pid")
kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
row "a Quickshell with nothing in it" "$zero_cpu" "the zero line"
zero=$zero_cpu
echo

E=$EMPTY_WIDGET
M=$MEDIA_WIDGET

# The notch itself, resting, with nothing in the row.
scenario "resting, empty glance"              '{"compact":[],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}'                      "$E" ""
scenario "resting, clock in the glance"       '{"compact":["clock"],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}'               "$E" ""
scenario "resting, media in the glance, paused"  '{"compact":["media"],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}'            "$E" "Track|paused"
scenario "resting, media in the glance, playing" '{"compact":["media"],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}'            "$E" "Track|playing"
# The glance the user cannot see: media configured for hover only, resting.
scenario "resting, media on hover only, playing" '{"compact":[],"hoverItems":["media"],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}' "$E" "Track|playing"
# Hidden in the edge, which is the cheapest the notch can possibly be.
scenario "auto-hidden, media playing"         '{"autoHide":true,"compact":["media"],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}' "$E" "Track|playing"

echo
# The same notch with a real plugin in the row. The row is not drawn while the
# notch rests -- so anything this costs above the rows above is a plugin moving
# where nobody can see it, which the notch pays for in repaints.
scenario "resting, media WIDGET in the row, paused"  '{"compact":[],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}'               "$M" "Track|paused"
scenario "resting, media WIDGET in the row, playing" '{"compact":[],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}'               "$M" "Track|playing"

echo
# Open, which is allowed to cost more: someone is looking at it.
scenario "open on the widget row, playing"    '{"compact":[],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}'                      "$M" "Track|playing" expand
scenario "open on the settings panel"         '{"compact":[],"openWith":["click"],"batteryPeek":false,"peekOnTrackChange":false}'                      "$E" ""            settings

echo
echo "  ${DIM}Idle rows belong at the zero line. Anything moving costs a repaint of the${RESET}"
echo "  ${DIM}notch's surface at 60 Hz, and the compositor pays it again.${RESET}"
