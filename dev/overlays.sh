#!/bin/bash

# Drawing a window-based plugin's card inside the notch, as numbers.
#
#   ./dev/overlays.sh
#
# Four parts, each a different question:
#
#   A. OverlayHosting.qml against Omarchy's REAL pickers -- the emoji picker, the
#      reminder flow, the image picker and the clipboard history -- loaded from the
#      installed shell: what it takes, that the picker's own full-screen window
#      never maps, that the card is live where it lands, and that everything is
#      given back.
#   B. The whole route, through the real notch: the companion's go-between
#      (companion/kalinewb.notch-*/Facade.qml) in front of the real emoji picker,
#      as Omarchy would summon it -- and the ways back.
#   C. The same route against a fixture whose window is small enough to let map:
#      what happens when the notch declines, that the hold is truly let go, and
#      that a picker nobody asked the notch to draw is left exactly as it was.
#   D. What ships: the companions' manifests, their one shared go-between, and
#      the places that must know their names.
#
# Nothing here touches the live session's settings or plugins. The clipboard is
# loaded from a sandboxed copy (the real file reaps the live session's clipboard
# watchers when it loads, and writes its history), and the image picker reads a
# folder of generated pictures and a sandboxed cache. No picker is ever asked to
# apply anything: a pick is a keypress, and nothing here sends one.
#
# The pickers' windows are full-screen overlays that take the keyboard, so every
# check that opens a real one does it with the hold on; a check that finds one
# mapped has failed, and the suite closes the picker straight away.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

# Poll until the answer is the one the check needs; the LAST answer comes back
# either way, so a timed-out check reports what was really there.
settle() { # settle <want> <command...>
  local want=$1; shift
  local got="" deadline=$((SECONDS + ${SETTLE_SECONDS:-8}))
  while :; do
    got=$("$@" 2>/dev/null)
    [[ $got == "$want" ]] && break
    (( SECONDS >= deadline )) && break
    sleep 0.05
  done
  printf '%s' "$got"
}
quiet() { sleep "${1:-0.8}"; }

# Log lines that mean something broke. The shell's own start-up noise (the portal
# registering an app id, the QML scanner's module names) is not this suite's.
errors_in() { grep -i 'error\|binding loop\|TypeError\|ReferenceError' "$1" | grep -vi 'portal\|qmlscanner' ; }

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
PLUGINS=$SHELL_PATH/shell/plugins
for stock in emojis/Emojis.qml reminders/ReminderFlow.qml image-picker/ImagePicker.qml clipboard/Clipboard.qml; do
  [[ -f $PLUGINS/$stock ]] || { echo "overlays.sh: no $PLUGINS/$stock" >&2; exit 1; }
done

sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-overlays.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

field() { jq -r "$2" <<<"$1"; }

# --- sandboxes -------------------------------------------------------------------

# The clipboard, minus the two things that reach outside: the pkill of the live
# watchers it does when it loads, and the history file under the real $HOME.
mkdir -p "$sb/clip"
cp -a "$PLUGINS/clipboard/." "$sb/clip/"
sed -i -e 's#Component.onCompleted: initProc.running = true#Component.onCompleted: { }#' \
       -e "s#property string historyPath: .*#property string historyPath: \"$sb/clip-history.json\"#" "$sb/clip/Clipboard.qml"
sandboxed_ok=$(grep -c 'Component.onCompleted: { }' "$sb/clip/Clipboard.qml")
echo '[{"type":"text","text":"a line of history"}]' >"$sb/clip-history.json"

# Pictures for the image picker, written by hand so nothing is needed to make them.
mkdir -p "$sb/images" "$sb/cache"
python3 - "$sb/images" <<'PY'
import sys, zlib, struct
def png(path, rgb, w=96, h=64):
    raw = b"".join(b"\x00" + bytes(rgb) * w for _ in range(h))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
for i, rgb in enumerate([(200, 60, 60), (60, 200, 60), (60, 60, 200)]): png(f"{sys.argv[1]}/p{i}.png", rgb)
PY

mkroot() { # mkroot <dir> <harness qml>
  mkdir -p "$1"
  ln -sfn "$SHELL_PATH/shell/Commons" "$1/Commons"
  ln -sfn "$SHELL_PATH/shell/Ui" "$1/Ui"
  ln -sfn "$SHELL_PATH/shell/services" "$1/services"
  ln -sfn "$REPO" "$1/notch"
  cp "$REPO/dev/harness/$2" "$1/shell.qml"
}

# ===================================================================================
# A. The mechanism, against the real pickers
# ===================================================================================

echo "${BOLD}A. Taking a picker's card out of its window${RESET}"

root="$sb/mech"
mkroot "$root" overlay-shell.qml
ipc() { quickshell ipc -p "$root" call overlay "$@" 2>/dev/null; }
state() { ipc state; }
# The picker's own window must never be seen mapped. Closes the picker at once if
# it was: a real one is full-screen and holds the keyboard.
guard() {
  if [[ $(state | jq -r '.windowVisible') == true ]]; then ipc closeInner >/dev/null; echo "MAPPED"; else echo "down"; fi
}

probe() { # probe <stock file> <payload json>
  XDG_CACHE_HOME="$sb/cache" OVERLAY_STOCK="$1" OVERLAY_PAYLOAD="$2" \
    quickshell -p "$root" -n >>"$sb/qs-a.log" 2>&1 &
  qs_pid=$!
  settle yes ipc ready >/dev/null
}
probe_stop() { ipc quit >/dev/null 2>&1; wait "$qs_pid" 2>/dev/null; qs_pid=""; }
shown_in_slot() { state | jq -r '"\(.hosting) \(.slotChildren) \(.contentInSlot)"'; }
told() { state | jq -r '.told'; }
texts_live() { ipc texts | jq -r 'length >= 1'; }

# Every picker answers the same questions. $1 names it, $2 is its stock file and
# $3 its payload; $4 is the number of items left behind in the window (its scrim
# and its click-outside catcher), which is what the filter must not take.
mechanism() { # mechanism <name> <stock> <payload> <left behind> <items taken>
  local name=$1 stock=$2 payload=$3 left=$4 items=${5:-1}
  echo; echo "  ${BOLD}$name${RESET}  ${DIM}$(basename "$stock")${RESET}"
  probe "$stock" "$payload"

  check "$name: it loads, with a window in it the notch can find" "yes yes" "$(ipc ready) $(ipc windowFound)"
  check "$name: it can be drawn in the notch" "" "$(ipc hostable)"
  local before; before=$(state)
  check "$name: nothing held, its window down" "false false" "$(field "$before" '.armed') $(field "$before" '.windowVisible')"

  check "$name: arming it succeeds" "" "$(ipc arm)"
  ipc open >/dev/null
  # The image picker scans a folder before it opens; the others open at once.
  check "$name: it opens, and is told so" "true" "$(settle true told)"
  check "$name: …and its own window never mapped" "down" "$(guard)"
  check "$name: taking its card succeeds" "" "$(ipc take)"
  check "$name: the card is in the notch's slot" "true $items true" "$(settle "true $items true" shown_in_slot)"
  local after; after=$(state)
  echo "  ${DIM}$(jq -c '{contentSize, windowChildren, focusTarget, monochrome, wanted}' <<<"$after")${RESET}"
  check "$name: only the card came; the scrim and the click-outside catcher stayed" "$left" "$(field "$after" '.windowChildren')"
  check "$name: the card has a size to grow the notch to" "true" "$(field "$after" '.wanted.width > 0 and .wanted.height > 0')"
  check "$name: …which is the card's own, not the notch's" "true" \
    "$(field "$after" '.wanted.width == .contentSize.width and .wanted.height == .contentSize.height')"
  check "$name: it keeps its own colours (a picker is its content)" "false" "$(field "$after" '.monochrome')"
  check "$name: the keyboard has a target in the card" "true" "$(field "$after" '.focusTarget != ""')"
  check "$name: it asks for focus where it landed" "ok" "$(ipc focus)"
  check "$name: the card is live where it landed, not a picture of itself" "true" "$(texts_live)"
  check "$name: its window is still down" "down" "$(guard)"

  check "$name: taking it twice is refused rather than losing the first" "already hosting" "$(ipc take)"

  check "$name: giving it back succeeds" "" "$(ipc giveBack)"
  check "$name: the slot is empty again" "false 0 false" "$(settle "false 0 false" shown_in_slot)"
  local back; back=$(state)
  check "$name: …the picker was told it closed, so what it runs while open stops" "false" "$(field "$back" '.told')"
  check "$name: …its window never mapped on the way out either" "down" "$(guard)"
  check "$name: …and the hold is over, with its window the size it had" \
    "false $(field "$before" '.windowSize.width')x$(field "$before" '.windowSize.height')" \
    "$(field "$back" '.armed') $(field "$back" '.windowSize.width')x$(field "$back" '.windowSize.height')"
  check "$name: giving back when nothing is held says nothing" "" "$(ipc giveBack)"
  probe_stop
}

mechanism "emoji picker" "$PLUGINS/emojis/Emojis.qml" '{}' 2 1
mechanism "reminders" "$PLUGINS/reminders/ReminderFlow.qml" '{}' 2 1
mechanism "image picker" "$PLUGINS/image-picker/ImagePicker.qml" \
  "{\"imageDirs\":\"$sb/images\",\"doneFile\":\"$sb/images.done\"}" 1 2
check "clipboard: the sandboxed copy has its two reaches outside cut" "1" "$sandboxed_ok"
mechanism "clipboard" "$sb/clip/Clipboard.qml" '{}' 2 1

# ===================================================================================
# B. The whole route, through the real notch
# ===================================================================================

echo; echo "${BOLD}B. Through the notch, from a summons${RESET}"

# Laid out like the plugins folder, so the go-between finds the notch's bridge at
# the path it uses live, with no override.
nroot="$sb/notch-root"
mkdir -p "$nroot"
for dir in Commons Ui services; do ln -sfn "$SHELL_PATH/shell/$dir" "$nroot/$dir"; done
ln -sfn "$REPO" "$nroot/kalinewb.notch"
ln -sfn "$REPO/companion/kalinewb.notch-clipboard" "$nroot/kalinewb.notch-clipboard"
cp "$REPO/dev/harness/overlay-notch-shell.qml" "$nroot/shell.qml"

notch() { quickshell ipc -p "$nroot" call notch "$@" 2>/dev/null; }
harness() { quickshell ipc -p "$nroot" call harness "$@" 2>/dev/null; }
hstate() { harness state; }

mkdir -p "$sb/setup-home/.config/omarchy" "$sb/setup-state" "$sb/setup-run"
echo '{"bar":{"id":"kalinewb.notch","layout":{"left":[],"center":[],"right":[]}}}' >"$sb/setup-home/.config/omarchy/shell.json"

start_notch() { # start_notch <log name> <cloned from> [env...]
  local log=$1 from=$2; shift 2
  env OMARCHY_SHELL_PATH="$SHELL_PATH/shell" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_FORCE_SETUP=1 NOTCH_SETUP_HOME="$sb/setup-home" NOTCH_SETUP_CONFIG_DIR="$sb/setup-home/.config" \
    NOTCH_SETUP_TOGGLES_DIR="$sb/setup-home/toggles" NOTCH_SETUP_STATE_DIR="$sb/setup-state" \
    NOTCH_SETUP_STATUS="$sb/setup-run/setup.json" NOTCH_SETUP_PLUGINS_STATE=true \
    NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"bottomRadius":10}' OVERLAY_CLONED_FROM="$from" "$@" \
    quickshell -p "$nroot" -n >>"$sb/$log" 2>&1 &
  qs_pid=$!
  settle yes notch_ready >/dev/null
}
stop_notch() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }
notch_ready() { [[ $(notch geometry) == \{* ]] && echo yes || echo no; }
# The notch's state, and the picker's, as the one line a check compares.
rest() { notch geometry | jq -r '"\(.state) \(.hosted.open) \(.hosted.items)"'; }
route() { hstate | jq -r '"\(.route) \(.opened) \(.windowVisible)"'; }
wants() { notch overlays | jq -c '.wanted'; }
# The notch closes a panel when the compositor's focus moves (its focus grab), and
# this suite shares a session with whatever else is running, so a summons that did
# not stay is asked again a few times before it counts as failed. Nothing below
# counts opens: a retry would change the count, so the plugin's own books are
# read as a balance (opens less closes) that a retry leaves alone.
host_up() {
  local try
  for try in 1 2 3; do
    harness open >/dev/null
    [[ $(settle "expanded true 1" rest) == "expanded true 1" ]] && return 0
    harness close >/dev/null; sleep 0.4
  done
  return 1
}

start_notch qs-b.log omarchy.emojis
s=$(hstate)
check "the go-between loaded and found the notch's bridge at the live relative path" "true true true true" \
  "$(field "$s" .loaded) $(field "$s" .bridge) $(field "$s" .target) $(field "$s" .notch)"
check "…and loaded Omarchy's own emoji picker, for the id its manifest names" "true omarchy.emojis" \
  "$(field "$s" .stock) $(field "$s" .sourceId)"
check "nothing is asked for yet: the setting is off by default" "[]" "$(wants)"
check "the notch reports every picker it can host, and none else" '["omarchy.clipboard","omarchy.emojis","omarchy.image-picker","omarchy.reminders"]' \
  "$(notch overlays | jq -c .hostable)"
check "…and one companion for each, bridged" "true true true true" \
  "$(notch overlays | jq -r '[.companions[].bridged] | map(tostring) | join(" ")')"

# Off: the picker is exactly Omarchy's. Its own window would map full-screen, so
# the route is read, not exercised, here -- part C does it with a small window.
check "off: the notch does not want the picker" "false" "$(notch overlays | jq -r '.wanted | index("omarchy.emojis") != null')"

check "turning it on is one setting" "ok" "$(harness setNotch '{"hostedPanels":["omarchy.emojis","omarchy.clipboard","nonsense"]}')"
check "…the notch keeps the ones it can host and drops the rest" '["omarchy.emojis","omarchy.clipboard"]' "$(settle '["omarchy.emojis","omarchy.clipboard"]' wants)"

# The summons.
host_up
check "a summons: the go-between opens it, and the notch takes it" "notch true false" "$(settle "notch true false" route)"
check "…the picker's own window never maps, and the notch is expanded on it" "expanded true 1" "$(settle "expanded true 1" rest)"
g=$(notch geometry)
echo "  ${DIM}$(jq -c '{state, view, hosted: {open: .hosted.open, items: .hosted.items, size: [.hosted.width, .hosted.height], wanted: .hosted.report.wanted, mono: .hosted.monoLayer}}' <<<"$g")${RESET}"
check "…grown to the card the picker chose, not past the screen" "true" \
  "$(field "$g" '.hosted.report.wanted.width > 0 and (.hosted.width >= .hosted.report.wanted.width) and (.hosted.height >= .hosted.report.wanted.height)')"
check "…with the card's own colours, not the notch's monochrome" "false" "$(field "$g" '.hosted.monoLayer')"
check "…and the card paints no surface of its own over the notch's black" "true" "$(notch overlays | jq -r '.hosting.flat')"
# back-one's rule: nothing of a guest sits in the strip's zone, which is the top of
# the notch, and the notch grows by the inset so the card keeps its own size.
check "…the card starts below the back strip's zone" "true" "$(field "$g" '.hosted.contentTop >= 32')"
check "…and the notch grew by that inset, so the card is not squeezed" "true" \
  "$(field "$g" '.hosted.height >= .hosted.report.wanted.height + .hosted.contentTop')"
check "…and nothing of the card sits in the strip's zone (notch backZone: a zone, no hit)" "32 0" \
  "$(notch backZone | jq -r '"\(.zone.height) \(.hits | length)"')"
check "…it is told it is open, and the keyboard is where it asked" "true true" \
  "$(notch overlays | jq -r '"\(.hosting.told) \(.hosting.focused)"')"
check "the notch's back control is offered on it" "true" "$(notch backReport | jq -r '.offered')"

# A second summons while it is open: the picker resets, the notch keeps showing it.
check "asked for again while open: it stays, it does not toggle shut" "notch true false" "$(harness open >/dev/null; sleep 0.3; route)"
check "…still one card in the notch" "expanded true 1" "$(rest)"

# The ways back.
check "the back strip closes it" "closed" "$(notch back)"
check "…the notch rests, holding nothing" "compact false 0" "$(settle "compact false 0" rest)"
check "…the picker is closed, so it stops what it runs while open" "notch false false" "$(settle "notch false false" route)"
check "…and the notch holds nothing" "false false" "$(notch overlays | jq -r '"\(.hosting.active) \(.hosting.armed)"')"

host_up
check "open again after a round trip" "expanded true 1" "$(settle "expanded true 1" rest)"
harness dismiss >/dev/null
check "the picker closing itself (its Escape) takes the notch's copy down" "compact false 0" "$(settle "compact false 0" rest)"
check "…and leaves the picker closed, not re-opened by the notch" "notch false false" "$(settle "notch false false" route)"

host_up
harness close >/dev/null
check "the summons that closes it (hide / toggle) takes the notch's copy down" "compact false 0" "$(settle "compact false 0" rest)"

# Back returns to where it was opened from, not just closes.
notch_state() { notch geometry | jq -r '"\(.state) \(.view)"'; }
notch menu root >/dev/null
check "from the menu: the menu is open" "expanded menu" "$(settle "expanded menu" notch_state)"
harness open >/dev/null
check "…a picker opened over it takes the notch" "expanded hosted" "$(settle "expanded hosted" notch_state)"
check "…one step behind it, the menu" "1" "$(notch backReport | jq -r '.depth')"
check "…back returns to the menu" "back" "$(notch back)"
check "…which is open again" "expanded menu" "$(settle "expanded menu" notch_state)"
check "…and the picker was closed on the way" "notch false false" "$(settle "notch false false" route)"
notch back >/dev/null
settle "compact false 0" rest >/dev/null

check "no QML errors in the notch, the go-between or the picker" "0" "$(errors_in "$sb/qs-b.log" | wc -l)"
errors_in "$sb/qs-b.log" | head -3 | sed "s/^/  ${DIM}/; s/\$/${RESET}/"
stop_notch

# ===================================================================================
# C. Declined, and the hold let go (a fixture small enough to let map)
# ===================================================================================

echo; echo "${BOLD}C. When the notch does not take it${RESET}"

FIXTURE="file://$REPO/dev/fixtures/overlay/Picker.qml"
start_notch qs-c.log omarchy.emojis NOTCH_OVERLAY_STOCK_URL="$FIXTURE"
fstate() { hstate | jq -r '"\(.route) \(.opened) \(.windowVisible) \(.opens - .closes)"'; }

check "the fixture loads behind the go-between" "true true" "$(field "$(hstate)" .stock) $(field "$(hstate)" .notch)"

# Setting off: Omarchy's picker, untouched.
harness open >/dev/null
check "setting off: the picker opens its own window, as ever" "stock true true 1" "$(settle "stock true true 1" fstate)"
check "…and the notch did not take it" "compact false 0" "$(rest)"
harness close >/dev/null
check "…closing it closes its window" "stock false false 0" "$(settle "stock false false 0" fstate)"

# Setting on: held, taken, and counted exactly once each way.
harness setNotch '{"hostedPanels":["omarchy.emojis"]}' >/dev/null
settle '["omarchy.emojis"]' wants >/dev/null
host_up
check "setting on: the notch takes it, its window never maps, the picker believes it is open once" "notch true false 1" "$(settle "notch true false 1" fstate)"
check "…its card is in the notch" "expanded true 1" "$(settle "expanded true 1" rest)"
notch back >/dev/null
check "back closes it, once: the picker's books balance" "notch false false 0" "$(settle "notch false false 0" fstate)"

# The hold is let go: the picker's own window binding was put back, not broken.
harness setNotch '{"hostedPanels":[]}' >/dev/null
settle '[]' wants >/dev/null
harness open >/dev/null
check "setting off again: its own window opens again -- the binding was put back, not left broken" "stock true true 1" \
  "$(settle "stock true true 1" fstate)"
harness close >/dev/null
settle "stock false false 0" fstate >/dev/null

# Declined at the moment of asking: the picker is never lost.
harness setNotch '{"hostedPanels":["omarchy.emojis"]}' >/dev/null
settle '["omarchy.emojis"]' wants >/dev/null
# Away is a hold (quiet): the notch has stepped out of the way and draws nothing.
notch quiet on probe:overlay >/dev/null
harness open >/dev/null
sleep 0.4
check "the notch is away (quiet): the picker is not lost, it opens as itself" "stock true true" "$(route)"
harness close >/dev/null
notch quiet off probe:overlay >/dev/null

check "no QML errors in the notch, the go-between or the fixture" "0" "$(errors_in "$sb/qs-c.log" | wc -l)"
errors_in "$sb/qs-c.log" | head -3 | sed "s/^/  ${DIM}/; s/\$/${RESET}/"
stop_notch

# ===================================================================================
# D. What ships
# ===================================================================================

echo; echo "${BOLD}D. The companions${RESET}"

names=(clipboard emojis image-picker reminders)
valid=0; same=0; cloned=0
for n in "${names[@]}"; do
  d="$REPO/companion/kalinewb.notch-$n"
  omarchy plugin validate "$d" >/dev/null 2>&1 && valid=$((valid + 1))
  cmp -s "$d/Facade.qml" "$REPO/companion/kalinewb.notch-clipboard/Facade.qml" && same=$((same + 1))
  src=$(jq -r '.omarchy.clonedFrom' "$d/manifest.json")
  [[ $(jq -r '.id' "$d/manifest.json") == "kalinewb.notch-$n" && $src == omarchy.$n ]] && cloned=$((cloned + 1))
done
check "all four companions pass Omarchy's plugin validation" "4" "$valid"
check "…the one go-between is the same file in all four" "4" "$same"
check "…each is named for the picker it stands in for" "4" "$cloned"
check "…each is a keepLoaded overlay, so the picker's own state outlives a summons" "4" \
  "$(for n in "${names[@]}"; do jq -r '(.keepLoaded == true) and (.kinds == ["overlay"]) and (.entryPoints.overlay == "Facade.qml")' "$REPO/companion/kalinewb.notch-$n/manifest.json"; done | grep -c true)"
check "…the notch syncs them on update, like its other companions" "4" \
  "$(for n in "${names[@]}"; do grep -c "kalinewb.notch-$n:omarchy.$n" "$REPO/install.sh"; done | awk '{ n += $1 } END { print n }')"
check "…and the go-between only ever names stock files for the four the notch lists" "4" \
  "$(for n in Clipboard.qml Emojis.qml ImagePicker.qml ReminderFlow.qml; do grep -c "/$n\"" "$REPO/companion/kalinewb.notch-clipboard/Facade.qml"; done | awk '{ n += $1 } END { print n }')"

echo
if (( failures )); then echo "${RED}${failures} of ${checks} checks failed${RESET}"; exit 1; fi
echo "${GREEN}${checks} checks pass${RESET}"
