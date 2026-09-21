#!/bin/bash

# Drawing another plugin's panel inside the notch, as numbers.
#
#   ./dev/hosting.sh
#
# PanelHosting.qml against Omarchy's REAL audio widget, loaded from the
# installed shell. The host is a plain black window standing in for the notch's
# panel surface, so what is measured here is the mechanism: what it takes, what
# the plugin is told, that the panel still works where it lands, that the
# plugin's own window never maps while the notch holds its content, and that
# everything is given back the way it was found -- size, state and bindings.
#
# Nothing here touches the live session: the widget is a second copy, loaded
# read-only, with a stand-in `bar`.
#
# **Waiting.** Every check that reads state after asking for something polls for
# the answer it needs (`settle`) instead of sleeping long enough that it usually
# has arrived. A fixed sleep is either too long (35 s of this suite was waiting)
# or too short under load, and a suite that fails differently on each run can
# only be read by running it again -- which is not a test, it is a coin. The one
# place a fixed wait IS the measurement is a check that something did NOT happen
# (`quiet`), where there is no state to poll for.
#
# **What is not here.** The notch's growth curve belongs to dev/motion.sh, which
# samples it against a panel whose size does not move; measured through a guest
# that fills itself in as it opens, it was a weak claim that failed on a loaded
# machine. The notch's top edge and square top corners are dev/geometry.sh's.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

# Poll until the answer is the one the check needs, then stop. The LAST answer
# is what comes back either way, so a check that times out reports what was
# really there rather than an empty string.
settle() { # settle <want> <command...> [-> the last answer]
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

# A deliberate wait, for the checks that claim something did NOT happen. There
# is no state to poll for -- the claim is the absence of a change -- so here the
# waiting is the measurement, and it is written as one.
quiet() { sleep "${1:-0.8}"; }

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
WIDGET=${HOSTING_WIDGET:-$SHELL_PATH/shell/plugins/panels/audio/Panel.qml}
[[ -f $WIDGET ]] || { echo "hosting.sh: no widget at $WIDGET" >&2; exit 1; }

sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-hosting.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

# Every instance here runs from a root with the installed shell's modules
# beside this repo, and its own shell.qml.
mkroot() { # mkroot <dir> <harness qml>
  mkdir -p "$1"
  ln -sfn "$SHELL_PATH/shell/Commons" "$1/Commons"
  ln -sfn "$SHELL_PATH/shell/Ui" "$1/Ui"
  ln -sfn "$SHELL_PATH/shell/services" "$1/services"
  ln -sfn "$REPO" "$1/notch"
  cp "$REPO/dev/harness/$2" "$1/shell.qml"
}

root="$sb/root"
mkroot "$root" hosting-shell.qml

ipc() { quickshell ipc -p "$root" call hosting "$@" 2>/dev/null; }
field() { jq -r "$2" <<<"$1"; }

# Start the probe on a widget, and wait for it to have loaded rather than for a
# second to pass.
probe() { # probe <widget path>
  OMARCHY_SHELL_PATH="$SHELL_PATH/shell" HOSTING_WIDGET="$1" \
    quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  settle yes ipc ready >/dev/null
}
probe_stop() { ipc quit >/dev/null 2>&1; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

# The probe's state, as the one line a check compares.
took() { ipc state | jq -r '"\(.hosting) \(.slotChildren) \(.contentInSlot)"'; }
content_width() { ipc state | jq -r '.contentSize.width'; }
ticking() { ipc state | jq -r '.fixture.ticks >= 1'; }
told() { ipc state | jq -r '.told'; }
own_window() { ipc state | jq -r '"\(.ownPanelOpen) \(.ownWindowVisible)"'; }
fixture() { ipc state | jq -r '"\(.fixture.opens) \(.fixture.closes) \(.fixture.workRan)"'; }

echo "${BOLD}Hosting another plugin's panel${RESET}  ${DIM}$(basename "$(dirname "$WIDGET")")/$(basename "$WIDGET")${RESET}"

probe "$WIDGET"

check "1. the widget loads with nothing but a stand-in bar" "yes" "$(ipc ready)"
check "2. its panel is one the notch can draw" "" "$(ipc hostable)"

# --- taking it -----------------------------------------------------------------

before=$(ipc state)
check "3. nothing is hosted to begin with, and the plugin's own window is not mapped" "false 0 false" \
  "$(field "$before" '.hosting') $(field "$before" '.slotChildren') $(field "$before" '.ownWindowVisible')"

check "4. taking it succeeds" "" "$(ipc take)"
check "5. the panel is now in the notch's slot" "true 1 true" "$(settle "true 1 true" took)"
after=$(ipc state)
echo "  ${DIM}$(jq -c '{hosting, slotChildren, contentSize, told, ownWindowVisible}' <<<"$after")${RESET}"
check "6. …at the host's size" "460x420" \
  "$(field "$after" '.contentSize.width')x$(field "$after" '.contentSize.height')"
check "7. …and the plugin's own window never mapped" "false false" "$(own_window)"
# The window is held down at the one binding that maps it, not by telling the
# plugin its panel is shut. A panel does its work when it opens -- the network
# panel's only wifi scan starts there -- so a panel that is never told is drawn
# and inert, which is a wifi list with no networks in it.
check "8. …while the plugin itself is told its panel is open" "true" "$(told)"

texts=$(ipc texts)
echo "  ${DIM}live text: $texts${RESET}"
check "9. the panel is live where it landed, not a picture of itself" "true" \
  "$(jq -r 'length >= 3' <<<"$texts")"

ipc resizeHost 640 >/dev/null
check "10. it lays out again when the notch resizes" "640" \
  "$(settle 640 content_width)"

check "11. taking it twice is refused rather than losing the first one" "already hosting" "$(ipc take)"

# --- giving it back --------------------------------------------------------------

check "12. giving it back succeeds" "" "$(ipc giveBack)"
check "13. the notch's slot is empty again" "false 0 false" "$(settle "false 0 false" took)"
back=$(ipc state)
check "14. …and the panel is its own size again, not the notch's" "460" \
  "$(field "$back" '.contentSize.width // 460')"
check "15. …the plugin is told it closed, so what it runs while open stops" "false" "$(field "$back" '.told')"
check "16. …and its window is still down, because the close came first" "false" \
  "$(field "$back" '.ownWindowVisible')"

ipc openOwn >/dev/null
check "17. the plugin's own panel opens normally afterwards" "true true" "$(settle "true true" own_window)"
check "18. …and is still live after the round trip" "true" "$(jq -r 'length >= 3' <<<"$(ipc texts)")"
ipc closeOwn >/dev/null

check "19. giving back when nothing is hosted does nothing and says nothing" "" "$(ipc giveBack)"

# --- what the panel is told, as counts ---------------------------------------------
#
# No real panel can report how many times it was opened, so this is the same
# shape built to say so: Omarchy's Panel base, a KeyboardPanel mapped by
# `open: opened`, a PanelKeyCatcher inside it, and counters. What it measures is
# the thing the notch got wrong -- a panel drawn on the notch's surface while
# its own state said "shut", so nothing it runs on open ever ran.

probe_stop
probe "$REPO/dev/fixtures/hosting/PanelWidget.qml"

check "20. the fixture loads and is hostable" "yes·" "$(ipc ready)·$(ipc hostable)"
f=$(ipc state)
check "21. nothing has opened it, and nothing it runs while open is running" "0 0 false" \
  "$(field "$f" '.fixture.opens') $(field "$f" '.fixture.ticks') $(field "$f" '.fixture.workRan')"

ipc take >/dev/null
check "22. taking it opens it exactly once" "1 0 true" "$(settle "1 0 true" fixture)"
echo "  ${DIM}$(ipc state | jq -c '{told, ownWindowVisible, fixture}')${RESET}"
check "23. …its open-time work ran, and what it runs while open is running" "true" \
  "$(settle true ticking)"
check "24. …with its own window still down" "false false" "$(own_window)"

ticks_held=$(ipc state | jq -r '.fixture.ticks')
ipc giveBack >/dev/null
check "25. giving it back closes it exactly once" "1 1 false" "$(settle "1 1 false" fixture)"
# Its timer stops with its own close, so the count it stopped at is the count a
# moment later. Nothing to poll for: the claim is that it did NOT tick again.
stopped=$(ipc state | jq -r '.fixture.ticks')
quiet 0.5
check "26. …and what it ran while open has stopped" "true" \
  "$([[ $(ipc state | jq -r '.fixture.ticks') -eq $stopped && $stopped -ge $ticks_held ]] && echo true || echo false)"

# The binding that maps the plugin's own window was broken to hold it down, so
# the round trip has to put it back -- or the widget's panel never opens again
# in its own window, under this bar or any other.
ipc openOwn >/dev/null
check "27. its own window opens again afterwards: the binding was put back, not left broken" "true true" \
  "$(settle "true true" own_window)"
check "28. …and that is the fixture's second open, not a re-run of its first" "2" \
  "$(ipc state | jq -r '.fixture.opens')"
ipc closeOwn >/dev/null

# --- a widget that cannot be hosted ------------------------------------------------

probe_stop
cat >"$sb/Plain.qml" <<'QML'
import QtQuick
// A bar widget with no pop-out panel at all.
Item {
  property var bar: null
  property string moduleName: ""
  implicitWidth: 20
  implicitHeight: 20
}
QML
probe "$sb/Plain.qml"
check "29. a widget with no panel is declined, in words" "no panel" "$(ipc hostable)"
check "30. …and taking it refuses rather than half-doing it" "no panel" "$(ipc take)"
check "31. …leaving the slot empty" "false 0" \
  "$(field "$(ipc state)" '.hosting') $(field "$(ipc state)" '.slotChildren')"

# ---------------------------------------------------------------------------
# Inside the notch: the same panel, on the notch's surface.
# ---------------------------------------------------------------------------

echo; echo "${BOLD}Inside the notch${RESET}"

probe_stop

notch_root="$sb/notch"
mkroot "$notch_root" hosting-notch-shell.qml

notch() { quickshell ipc -p "$notch_root" call notch "$@" 2>/dev/null; }
harness() { quickshell ipc -p "$notch_root" call harness "$@" 2>/dev/null; }

# The notch's state, as the one line the checks compare.
shown() { notch geometry | jq -r '"\(.state) \(.view) \(.hosted.open)"'; }
own_down() { harness ownWindow | jq -r '"\(.visible) \(.open)"'; }
holding() { notch geometry | jq -r '"\(.hosted.open) \(.hosted.items)"'; }
# Closed: the notch is back at rest holding nothing. `view` is deliberately NOT
# part of this -- it keeps saying "hosted" until something else opens, because
# clearing it would destroy the panel mid-shrink (Bar.qml).
rests() { notch geometry | jq -r '"\(.state) \(.hosted.open) \(.hosted.items)"'; }
notch_ready() { [[ $(notch geometry) == \{* ]] && echo yes || echo no; }
drawing() { notch geometry | jq -r '.widgets.slots >= 1'; }
rested() { notch geometry | jq -r '(.target.height == .hosted.height) and ((.bar.height - .target.height) | fabs) < 0.5'; }
opted() { notch hosting | jq -c '.opted'; }

# Setup reads a sandbox, never this machine's real config.
mkdir -p "$sb/setup-home/.config/omarchy" "$sb/setup-state" "$sb/setup-run"
echo '{"bar":{"id":"kalinewb.notch","layout":{"left":[],"center":[],"right":[]}}}' >"$sb/setup-home/.config/omarchy/shell.json"

OMARCHY_SHELL_PATH="$SHELL_PATH/shell" HOSTING_WIDGET="$WIDGET" \
  NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
  NOTCH_FORCE_SETUP=1 NOTCH_SETUP_HOME="$sb/setup-home" NOTCH_SETUP_CONFIG_DIR="$sb/setup-home/.config" \
  NOTCH_SETUP_TOGGLES_DIR="$sb/setup-home/toggles" NOTCH_SETUP_STATE_DIR="$sb/setup-state" \
  NOTCH_SETUP_STATUS="$sb/setup-run/setup.json" \
  NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"bottomRadius":10}' \
  quickshell -p "$notch_root" -n >>"$sb/qs.log" 2>&1 &
qs_pid=$!
settle yes notch_ready >/dev/null

check "32. the notch is drawing the widget" "true" \
  "$(settle true drawing)"

check "33. the notch takes the panel" "opened" "$(notch hostPanel audio)"
check "34. it is on the notch's surface, in the notch's view" "expanded hosted true" \
  "$(settle "expanded hosted true" shown)"
g=$(notch geometry)
echo "  ${DIM}$(jq -c '{state, view, hosted: {open: .hosted.open, items: .hosted.items, size: [.hosted.width, .hosted.height], wanted: .hosted.report.wanted}}' <<<"$g")${RESET}"
# The panel reads its colours off the bar object it was given. Inside the
# notch those are the notch's -- white on black -- not the theme's.
check "35. …painting with the notch's colours: text, background and urgent are the notch's, not the theme's" "true true true" \
  "$(field "$g" '.colours | "\(.widgets.foreground == .text) \(.widgets.background == .notch) \(.urgent == .text)"')"
check "36. …and the plugin is told it is open, with the keyboard on the target it named" "true true" \
  "$(field "$g" '.hosted.report.told') $(field "$g" '.hosted.report.focused')"
# The guest is the one thing in the notch that reads the theme itself, so the
# hue comes out of what it draws rather than being handed to it. dev/colours.sh
# measures the shader; this is that it is on the slot at all, and only while
# the notch is holding something.
check "37. …with its hue taken out, which is not a preference" "true" \
  "$(field "$g" '.hosted.monoLayer')"
check "38. every item of the panel came, not just the first" "true" \
  "$(field "$g" '.hosted.items >= 1')"

# The size, not the curve that reaches it: the notch grows to what the PLUGIN
# asked its own card for, and rests exactly there. (How it travels is
# dev/motion.sh's.)
check "39. the notch grew to the size the plugin asked its own card for" "true" \
  "$(field "$g" '.hosted.report.wanted.width > 0 and (.hosted.width >= .hosted.report.wanted.width)')"
check "40. …and it came to rest on it, not near it" "true" \
  "$(settle true rested)"

# The guest's own controls keep their own shapes -- Omarchy's toggle is a pill,
# its rules are hairlines, and forcing the notch's radius onto them would make
# them look wrong rather than integrated. What IS the notch's business is that
# the guest does not paint a surface of its own over the notch's black: the
# background belongs to the notch, and the card that used to provide one was
# left behind with the plugin's window.
d=$(notch design)
check "41. the guest paints no background of its own over the notch" "0" "$(python3 -c '
import json,sys
d=json.loads(sys.argv[1])
items=[i for i in d.get("hosted", []) if i["drawn"] and i["width"]>0 and i["height"]>0]
slot=json.loads(sys.argv[2])
full=[i for i in items if i["width"]*i["height"] >= 0.9*slot["width"]*slot["height"]]
print(len(full))' "$d" "$(field "$g" '{width: .hosted.width, height: .hosted.height}')")"

check "42. the notch reports what it is hosting" "true" "$(notch hosting | jq -r '.active')"

# Closing: the panel goes back, and the notch rests.
notch releasePanel >/dev/null
check "43. closing gives the panel back and the notch rests" "compact false 0" \
  "$(settle "compact false 0" rests)"
g=$(notch geometry)
check "44. …the notch is holding nothing, and nothing is drawn through the mono layer" "false 0 false" \
  "$(notch hosting | jq -r '.active') $(field "$g" '.hosted.items') $(field "$g" '.hosted.monoLayer')"
check "45. …and the panel's colours are the theme's again, for its own window" "true true" \
  "$(field "$g" '.colours | "\(.widgets.foreground == .themeText) \(.widgets.background == .themeBarBackground)"')"

# Opening it again after a round trip.
check "46. it can be hosted again afterwards" "opened" "$(notch hostPanel audio)"
check "47. …with the panel back on the notch's surface" "expanded hosted true" \
  "$(settle "expanded hosted true" shown)"

# Every way of closing a panel closes this one too.
notch toggle >/dev/null
check "48. the open keybind closes it, like every other panel" "false 0" "$(settle "false 0" holding)"

check "49. a widget the notch is not drawing is declined, in words" "declined:no such widget" \
  "$(notch hostPanel nosuchwidget)"

# --- opting in, and the plugin's own summon ----------------------------------------

check "50. a widget nobody opted into is not intercepted, and nothing is opted in by default" "false []" \
  "$(notch geometry | jq -r '.hosted.open') $(notch hosting | jq -c '.opted')"

# Settings -> Integrations has to offer it, or nobody can reach it without
# editing shell.json by hand.
check "51. the settings offer the widget, named, as something the notch can draw" "1 Audio false" \
  "$(notch settingsReport 2>/dev/null | jq -r '.hostable | length') $(notch settingsReport 2>/dev/null | jq -r '.hostable[0].name') $(notch settingsReport 2>/dev/null | jq -r '.hostable[0].hosted')"

# The panel lists a cached copy: the walk it needs touches every widget's
# children, which QML cannot bind to. So it has to be refreshed when the panel
# opens, or the user reads whatever was true in the notch's first second --
# which is how clock, weather and camera-test stayed missing from a list that
# had already been rebuilt to include them. Blank the cache, reopen, and it
# has to come back.
listed() { notch settingsReport 2>/dev/null | jq -r '.panelHostable == (.hostable | length) and .panelHostable >= 1'; }
panel_listed() { notch settingsReport 2>/dev/null | jq -r '.panelHostable'; }
notch settings >/dev/null 2>&1
check "52. the open panel is listing that same walk" "true" "$(settle true listed)"
notch settings >/dev/null 2>&1
harness staleSettings >/dev/null
check "53. …a stale cache is what it would show" "0" "$(settle 0 panel_listed)"
notch settings >/dev/null 2>&1
check "54. …and opening it refreshes the list" "true" "$(settle true listed)"
notch settings >/dev/null 2>&1

# A plugin opening its own panel -- its keybind, or `omarchy-shell <id> open` --
# has to land in the notch too, or the integration only half applies.

check "55. nothing is hosted before the summon" "false" "$(notch geometry | jq -r '.hosted.open')"
harness summon >/dev/null
quiet   # nothing should happen: there is no state change to wait for
check "56. summoning a widget nobody opted into leaves the notch alone" "false" \
  "$(notch geometry | jq -r '.hosted.open')"
check "57. …and that plugin opened its own window, as it always did" "true" \
  "$(harness ownWindow | jq -r '.open')"

# Put the plugin's own panel back down first: `open` is already true, and
# setting it true again would fire no change for the notch to act on.
harness dismiss >/dev/null

# Now opt it in, the way the settings switch does, and summon again.
harness setNotch '{"batteryPeek":false,"bottomRadius":10,"hostedPanels":["audio"]}' >/dev/null
check "58. the settings switch is what turns it on" '["audio"]' \
  "$(settle '["audio"]' opted)"
harness summon >/dev/null
check "59. the plugin's own summon now opens inside the notch" "expanded hosted true" \
  "$(settle "expanded hosted true" shown)"
# This shows the window is down once the notch has it. That it never appears at
# all rests on the handler running in the same turn as the plugin's own `open`,
# which is reasoned rather than measured: an IPC round trip is ~50 ms and a
# frame is ~8, so this harness cannot see a single-frame flicker either way.
#
# `open` is false in that same turn; `visible` follows 140 ms later, because a
# KeyboardPanel stays mapped while its card fades out (`open || card.opacity >
# 0`). Reading both at once caught the fade and failed on it.
check "60. …and the plugin's own window was put straight back down" "false false" \
  "$(settle "false false" own_down)"

# The other direction of the same state: a hosted panel's controller is open
# for as long as the notch draws it, so the plugin closing itself -- its own
# Escape, a timeout, `omarchy-shell <plugin> close` -- has to take the notch's
# copy down with it. Before, the notch held a panel whose plugin had gone.
harness dismiss >/dev/null
check "61. the plugin closing its own panel closes the notch's copy of it" "compact false 0" \
  "$(settle "compact false 0" rests)"

harness summon >/dev/null
settle "expanded hosted true" shown >/dev/null
notch releasePanel >/dev/null
check "62. releasing it gives the panel back" "false 0" "$(settle "false 0" holding)"
check "63. …and the plugin was told, so nothing of it is left running" "false" \
  "$(notch hosting | jq -r '.told')"

# Setup has to ask, or nobody finds the switch.
harness setNotch '{"batteryPeek":false,"bottomRadius":10}' >/dev/null
setup_points() { notch setup status "" 2>/dev/null | jq -r '.points | length > 0'; }
notch setup check "" >/dev/null 2>&1
settle true setup_points >/dev/null
# Whether a panel opens in the notch is a preference, set in Settings ->
# Integrations. Setup reports what is wrong, and an unticked preference isn't.
check "64. Setup says nothing about a panel nobody asked to host" "0" \
  "$(notch setup status "" 2>/dev/null | jq -r '[.points[] | select(.id == "hostable-panels")] | length')"

# --- the other shape: a panel behind a Loader ------------------------------------
#
# Omarchy's audio widget *is* its Panel, so its parts are its own children.
# Clock, weather and camera-test have a BarWidget that loads Panel.qml through
# a Loader, and looking only at the direct children answered "no panel" for
# every widget built that way -- which is why they never appeared in Settings →
# Integrations. Same mechanism, one level down.
LOADER_WIDGET=${HOSTING_LOADER_WIDGET:-$SHELL_PATH/shell/plugins/panels/clock/BarWidget.qml}
if [[ -f $LOADER_WIDGET ]]; then
  echo
  echo "  ${DIM}$(basename "$(dirname "$LOADER_WIDGET")")/$(basename "$LOADER_WIDGET") — the panel is behind a Loader${RESET}"
  notch quit >/dev/null 2>&1; kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""

  probe "$LOADER_WIDGET"
  check "65. the widget loads, and its panel is found through the Loader" "yes·" "$(ipc ready)·$(ipc hostable)"
  ipc take >/dev/null
  check "66. taking it works the same way, and the plugin's own window stays down" "true 1 true·false" \
    "$(settle "true 1 true" took)·$(ipc state | jq -r '.ownWindowVisible')"
  check "67. …the plugin is told, through the Loader too" "true" "$(told)"
  ipc giveBack >/dev/null
  check "68. …and giving it back leaves the notch holding nothing" "false 0 false" "$(settle "false 0 false" took)"
  probe_stop
  echo
fi

# One log, one check: every instance in this suite writes to it.
check "69. no QML errors in any of it" "none" \
  "$(grep -aE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-80)$(grep -qaE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
