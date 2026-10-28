#!/bin/bash

# The pixel guard prototype of plan-surface-v2.md (Phase 1), as numbers.
#
#   ./dev/panelstyle.sh            both layers
#   ./dev/panelstyle.sh pure       layer 1 only (node, no display)
#
# 1. Pure. panelstyle.js under node (dev/panelstyle_test.js): the contrast
#    vectors, the one contrast body against Bar.qml and the kit, `lift`, the
#    clip inset, the pixel measurer on synthetic pixels, the walk on fake
#    items, the "laid out" rule and the verdict.
# 2. Live. The real Bar.qml in a throwaway Quickshell instance
#    (dev/harness/platform-shell.qml) with one fixture plugin, acme.guard,
#    whose panel carries a PanelGuard. The guard grabs the panel in the notch's
#    real PanelWindow, reads the pixels back, and is exercised on the fixtures
#    of GuardPanel.qml, with the host closed (what the panel looks like before
#    the reveal: invisible, disabled, opacity 0) and open.
#
# Nothing here is in Bar.qml yet. The notch draws briefly over the live
# screen while this runs, and the numbers it prints are the ones recorded in
# docs/panelstyle-phase1.md.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

# --- 1. pure ------------------------------------------------------------------------

echo "${BOLD}panelstyle.js${RESET}  ${DIM}under node${RESET}"
while IFS=$'\t' read -r desc expected actual; do
  [[ -z $desc ]] && continue
  check "$desc" "$expected" "$actual"
done < <(node "$REPO/dev/panelstyle_test.js" "$REPO" 2>&1)

[[ ${1:-} == pure ]] && { echo; (( failures )) && { echo "$failures of $checks failed"; exit 1; }; echo "$checks checks pass"; exit 0; }

# --- 2. live ------------------------------------------------------------------------

SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-panelstyle.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

PLUGINS="$sb/plugins"
mkdir -p "$PLUGINS" "$sb/state" "$sb/bin"
cp -r "$REPO/dev/fixtures/panelstyle/plugins/acme.guard" "$PLUGINS/"
# The guard and its rule travel with the panel, as the host will have them.
cp "$REPO/PanelGuard.qml" "$REPO/panelstyle.js" "$PLUGINS/acme.guard/"
# The stand-in omarchy-shell: a harness must never reach the live one.
printf '#!/bin/bash\nexit 1\n' >"$sb/bin/omarchy-shell"; chmod +x "$sb/bin/omarchy-shell"

# The notch as Phase 3 will leave its host: the integration panel stays
# `visible` while it is faded out, so the walk can tell a hidden item from a
# drawn one. One line of ExpandedHost, changed in a COPY; this repo's Bar.qml is
# not touched.
mkdir -p "$sb/notch-visible"
tar -C "$REPO" --exclude=./.git --exclude=./dev --exclude=./marketing -cf - . | tar -C "$sb/notch-visible" -xf -
sed -i '/component ExpandedHost: Loader/,/^  }/ s/^    visible: opacity > 0$/    visible: true/' "$sb/notch-visible/Bar.qml"
patched=$(sed -n '/component ExpandedHost: Loader/,/^  }/p' "$sb/notch-visible/Bar.qml" | grep -c '^    visible: true$')

root="$sb/shell"
nipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
harness() { quickshell ipc -p "$root" call harness "$@" 2>/dev/null; }
SCREEN=$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name' 2>/dev/null)
: "${SCREEN:=eDP-1}"
g() { quickshell ipc -p "$root" call "guard.$SCREEN" "$@" 2>/dev/null; }
panel_toggle() { nipc panel acme.guard main >/dev/null; }

boot() { # boot <notch dir>
  rm -rf "$root"; mkdir -p "$root"
  for m in Commons Ui services; do ln -s "$SHELL_PATH/shell/$m" "$root/$m"; done
  ln -s "$1" "$root/notch"
  cp "$REPO/dev/harness/platform-shell.qml" "$root/shell.qml"
  printf 'import QtQuick\nimport qs.Commons\nimport qs.Ui\nItem { }\n' >"$root/Probe.qml"
  env PATH="$sb/bin:$PATH" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_FORCE_PLATFORM=1 NOTCH_PLUGINS_DIR="$PLUGINS" NOTCH_PLATFORM_ENABLED="*" \
    NOTCH_PLATFORM_STATE_DIR="$sb/state" NOTCH_PLATFORM_WIDGETS='{}' \
    NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' \
    quickshell -p "$root" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 60); do sleep 0.1; [[ $(nipc geometry) == \{* ]] && break; done
  for _ in $(seq 1 60); do sleep 0.1; [[ $(nipc integrations | jq -r '.scannedAt > 0') == true ]] && break; done
  sleep 0.4
  # the panel's IPC target exists once the panel has been opened
  panel_toggle
  for _ in $(seq 1 40); do sleep 0.1; [[ $(g fixtures) == good* ]] && break; done
}
shutdown() {
  harness quit >/dev/null 2>&1; sleep 0.5
  kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""
}

host() { g host | jq -c '.target | [.visible, .enabled, .opacity]'; }
open_host() {
  [[ $(g host | jq -r .open) == false ]] && panel_toggle
  for _ in $(seq 1 40); do sleep 0.1; [[ $(g host | jq -r '.open and .target.opacity == 1') == true ]] && break; done
}
close_host() {
  [[ $(g host | jq -r .open) == true ]] && panel_toggle
  for _ in $(seq 1 40); do sleep 0.1; [[ $(g host | jq -r '(.open | not) and .target.opacity == 0') == true ]] && break; done
}

# The regime a measurement is wanted in; measure() puts the host back in it if
# the notch closed the panel by itself.
WANT=open
regime() { WANT=$1; [[ $1 == open ]] && open_host || close_host; }

# Run one fixture and wait for its verdict; the JSON comes back in $R.
R=""
measure() { # measure <fixture> [opts json]
  [[ $(g host | jq -r .open) != "$([[ $WANT == open ]] && echo true || echo false)" ]] && regime "$WANT"
  local seq; seq=$(g result | jq -r .sequence)
  local opts=${2:-}; [[ -z $opts ]] && opts='{}'
  g start "$1" "$opts" >/dev/null
  local deadline=$((SECONDS + ${MEASURE_SECONDS:-12}))
  while :; do
    R=$(g result)
    [[ $(jq -r ".done and .sequence > $seq" <<<"$R") == true ]] && break
    (( SECONDS >= deadline )) && break
    sleep 0.05
  done
}
f() { jq -r "$1" <<<"$R"; }
# a measured ratio within <pct> percent of a number
near() { # near <measured> <expected> <percent> -> true|false
  jq -nr --argjson m "$1" --argjson e "$2" --argjson p "$3" '(($m - $e) | fabs) <= ($e * $p / 100)'
}
ratio() { f ".result.rects[] | select(.name == \"$1\" and .role == \"$2\") | .ratio"; }

echo; echo "${BOLD}Instance A: the real Bar.qml${RESET}  ${DIM}sandbox $sb, screen $SCREEN${RESET}"
boot "$REPO"
check "L1. the fixture plugin is accepted and its panel loads" "true ready" \
  "$(nipc integrations | jq -r '.list[] | select(.id == "acme.guard") | "\(.accepted) \(.loadStatus)"')"

# --- gate 1: a pixel read inside the real harness ------------------------------------------

echo; echo "${BOLD}Gate 1: pixel readback under the notch's PanelWindow${RESET}"
for state in open closed; do
  regime $state
  check "G1. host $state: visible, enabled, opacity" "$([[ $state == open ]] && echo '[true,true,1]' || echo '[false,false,0]')" "$(host)"
  for sw in s1 s2 s3 s4 s5 s6; do
    g readback $sw >/dev/null
    for _ in $(seq 1 30); do sleep 0.1; [[ $(g readbackResult) == \{* ]] && break; done
    P=$(g readbackResult)
    check "G1. $state host, swatch $sw: orange and blue read back exactly, in device pixels (item x window ratio)" \
      "255,136,0,255 51,102,153,255 true" \
      "$(jq -r '"\(.a | join(",")) \(.b | join(",")) \(.source[0] == (120 * .windowDpr | round) and .source[1] == (60 * .windowDpr | round))"' <<<"$P")"
  done
done
echo "  ${DIM}$(jq -c '{windowDpr, screenDpr: .dpr, canvasBitmapWidthFor600: .bitmapWidth, source, grabMs, readMs}' <<<"$P")${RESET}"

# --- the fixtures ------------------------------------------------------------------------------

fixtures_for() { # fixtures_for <label> <trusted: true|false>
  local st=$1
  measure good '{"audit":true}'
  check "$st good: pass, six rects, all painted, nothing outside them moved; the walk can $([[ $2 == true ]] || echo not )trust the panel's visibility" \
    "pass 6 6 0 $2" "$(f '.result | "\(.state) \(.found) \(.painted) \(.outsideDiff) \(.trusted)"')"
  check "$st good: a filled mark reads as its fill (3.73:1)" "true" "$(near "$(ratio Enrol ui)" 3.727 1)"
  check "$st good: a label on a button reads against the button (5.51:1), not the black behind" "true" "$(near "$(ratio Enrol text)" 5.509 4)"

  measure lowText '{"audit":true}'
  check "$st lowText: fail, and it names the hint" "fail Hint text" "$(f '.result | "\(.state) \(.failing.name)"')"
  check "$st lowText: the hint reads 2.8:1 (within 5 %)" "true" "$(near "$(ratio 'Hint text' text)" 2.817 5)"

  measure outline '{"audit":true}'
  check "$st outline: pass; the focusable decoy is not a mark (5 rects found)" "pass 5 0" "$(f '.result | "\(.state) \(.found) \(.outsideDiff)"')"
  check "$st outline: an outline reads as its border (6.08:1), 1 px and 2 px alike" "true true" \
    "$(near "$(ratio Retry ui)" 6.083 1) $(near "$(ratio Skip ui)" 6.083 1)"

  measure outlineBad '{"audit":true}'
  check "$st outlineBad: fail on the mark, 1.5:1 against 3" "fail Retry ui" "$(f '.result | "\(.state) \(.failing.name) \(.failing.role)"')"

  measure translucent '{"audit":true}'
  check "$st translucent: pass, judged as it lands on the notch's black" "pass 0" "$(f '.result | "\(.state) \(.outsideDiff)"')"
  check "$st translucent: a 70 % text on a 12 % card, and a 60 % opacity text, read as composited (8.69, 6.74 within 3 %)" "true true" \
    "$(near "$(ratio Translucent text)" 8.689 3) $(near "$(ratio Faded text)" 6.741 3)"

  measure gradient '{"audit":true}'
  check "$st gradient: the worst pixel of the text's rect decides: fail, 2.1:1" "fail Across the gradient" "$(f '.result | "\(.state) \(.failing.name)"')"

  measure antialias '{"audit":true}'
  check "$st antialias: every regular and bold #757575 (4.558 on paper) clears the floor on the tolerance" "true" \
    "$(f '[.result.rects[] | select(.name | test("^aa [0-9]+b? #757575$")) | (.ratio + 0.4 >= 4.5)] | all')"
  check "$st antialias: #747474 (4.493) at 12 px is not told apart from #757575 (within 7 %)" "true" \
    "$(near "$(ratio 'aa 12 #747474' text)" "$(ratio 'aa 12 #757575' text)" 7)"
  echo "  ${DIM}$st antialias sweep: $(f '[.result.rects[] | "\(.name | sub("aa ";"") | sub(" #75.*";"")):\(.ratio * 100 | round / 100)"] | join("  ")')${RESET}"

  measure big '{"audit":true}'
  check "$st big: a 290 x 160 card is read sparsely (stride >= 2); its outline and its 40 px headline still read as themselves" \
    "pass true true true" \
    "$(f '.result | "\(.state)"') $(f '[.result.rects[] | select(.name == "Card") | .stride >= 2] | all') $(near "$(ratio Card ui)" 6.083 1) $(near "$(ratio Headline text)" 14.4 5)"

  measure many '{"audit":true}'
  check "$st many: 120 labels are 120 rects, all painted, and they pass" "pass 120 120 false" "$(f '.result | "\(.state) \(.found) \(.painted) \(.capped)"')"
  measure many '{"maxRects":40}'
  check "$st many with a cap of 40: the walk keeps 40, says it saw more, and what it measured is still judged" "pass 40 true true" \
    "$(f '.result | "\(.state) \(.found) \(.capped) \(.seen > .found)"')"
  echo "  ${DIM}$st 120 labels: walk $(f '.result.ms.walk | . * 100 | round / 100') ms per pass, $(f '.result.parts.slices') slices${RESET}"

  measure late '{"audit":true}'
  if [[ $2 == true ]]; then
    check "$st late: it waits for the panel to fill in (>= 250 ms), then fails on the hint" "fail Late hint true" \
      "$(f '.result | "\(.state) \(.failing.name) \(.ms.settle >= 250)"')"
  else
    check "$st late: with the panel invisible nothing painted is not a pass, however long it waits: unsettled" "false unsettled" "$(f '.result | "\(.pass) \(.state)"')"
    echo "  ${DIM}$st late: $(f '.result | "\(.why) retries=\(.retries) after \(.ms.total) ms"')${RESET}"
  fi

  measure regress '{"audit":true}'
  check "$st regress: fine at first, so it passes" "pass" "$(f '.result.state')"
  sleep 0.8
  g again >/dev/null
  for _ in $(seq 1 60); do sleep 0.1; [[ $(g result | jq -r '.runs | length') == 2 && $(g result | jq -r .done) == true ]] && break; done
  R=$(g result)
  check "$st regress: ...and the recheck catches what appeared later" "fail Regressed" "$(f '.result | "\(.state) \(.failing.name)"')"

  g start none '{}' >/dev/null; sleep 0.3
  measure regress '{"recheck":true}'
  sleep 4.5
  R=$(g result); g stop >/dev/null
  check "$st regress with the 2 s timer: pass first, then the timer flips it, after several rechecks" "pass fail true" \
    "$(f '.history[0].state') $(f '.history[-1].state') $(f '(.history | length) >= 3')"
}

numbers() { # numbers <label> <fixture>
  measure "$2" '{"repeat":40}'
  echo "  $1 $(printf '%-9s' "$2") rects=$(f '.result | "\(.found) (\(.painted) painted, \(.parts.pixels) px read, \(.parts.slices) slices)"')"
  echo "    total $(stats .total)   settle $(stats .settle)   grab A $(stats .grabA)   grab B $(stats .grabB)"
  echo "    read A $(stats .readA)   read B $(stats .readB)   arithmetic $(stats .work)   to verdict after B $(stats .compute)   longest stall $(stats .stall)   hidden frames $(f '[.runs[].blink] | max')"
}
stats() { # stats <jq path in .runs[].ms>
  f "[.runs[].ms$1] | sort | \"\(.[(length / 2) | floor]) / \(.[(length * 0.95) | floor]) / \(.[-1])\""
}

echo; echo "${BOLD}Fixtures, host open${RESET}"
regime open
fixtures_for open true

echo; echo "${BOLD}Round-2 notes${RESET}"
measure good '{"audit":true,"hideBy":"opacity"}'
op=$(f '.result.outsideDiff')
measure good '{"audit":true,"hideBy":"visible"}'
vis=$(f '.result.outsideDiff'); visState=$(f '.result.state')
check "hiding B by opacity 0 moves nothing outside the found rects; hiding by visible: false re-flows the Column" "0 true" "$op $([[ $vis -gt 0 ]] && echo true || echo false)"
echo "  ${DIM}visible:false moved $vis pixels outside the rects, and the verdict became '$visState' ($(f '.result.detail'))${RESET}"

measure good '{"mode":"full","audit":true}'
fullGood=$(f '[.result.rects[] | select(.role == "text") | .ratio] | map(. * 10 | round / 10) | tostring')
frames=$(f '.result.blinkFrames')
measure good '{"mode":"light"}'
lightGood=$(f '[.result.rects[] | .ratio] | map(. * 10 | round / 10) | tostring')
check "a grab with the texts hidden is on screen for a frame when the panel is open; the light mode (grab A, ring backdrop) hides nothing" "1 0" "$frames $(f '.result.blinkFrames')"
check "...and on a panel with a plain backdrop the light mode reads the texts as the full mode does" "$fullGood" "$lightGood"
measure translucent '{"mode":"light"}'
check "light mode, translucent and gradient backdrops: the same verdicts and the same ratios (within 2 %)" "pass true" \
  "$(f '.result.state') $(near "$(ratio Translucent text)" 8.505 2)"
measure gradient '{"mode":"light"}'
check "light mode, gradient: fail, 2.1:1" "fail true" "$(f '.result.state') $(near "$(ratio 'Across the gradient' text)" 2.09 3)"
measure antialias '{"mode":"light"}'
echo "  ${DIM}light mode on stacked 1 px-apart lines (antialias): $(f '.result.rects | map(.ratio * 100 | round / 100) | tostring')  <- the ring is polluted by the next line; not usable there${RESET}"

# a grab that does not answer in time: the guard says so and the panel is put back
unavail=0
for _ in 1 2 3 4 5 6; do
  measure good '{"timeout":1}'
  [[ $(f '.result.state') == unavailable ]] && unavail=$((unavail + 1))
done
check "a 1 ms grab timeout trips (at least once in six) as 'unavailable', not a verdict" "true" "$([[ $unavail -ge 1 ]] && echo true || echo false)"
measure good '{}'
check "...and the next measurement is clean: the text was put back, the guard is not stuck" "pass" "$(f '.result.state')"
echo "  ${DIM}1 ms timeout: $unavail of 6 measurements ended unavailable${RESET}"

echo; echo "${BOLD}Numbers, host open${RESET}  ${DIM}40 measurements each, milliseconds, median / p95 / max${RESET}"
for fx in good outline antialias big many; do numbers open "$fx"; done

# --- the real host, closed ------------------------------------------------------------------------

echo; echo "${BOLD}Host closed, as Bar.qml has it today${RESET}  ${DIM}(invisible, disabled, opacity 0)${RESET}"
regime closed
measure good '{"audit":true}'
check "closed-real good: the readback works and the verdict is right, but the walk says it could not trust the panel's visibility" "pass false" "$(f '.result | "\(.state) \(.trusted)"')"
measure lowText '{}'
check "closed-real lowText: fail on the hint" "fail Hint text" "$(f '.result | "\(.state) \(.failing.name)"')"
measure late '{}'
check "closed-real late: nothing painted is not a pass, however long it waits: unsettled" "false unsettled" "$(f '.result | "\(.pass) \(.state)"')"
echo "  ${DIM}closed-real late: $(f '.result | "\(.why) retries=\(.retries) after \(.ms.total) ms"')${RESET}"
shutdown

# --- instance B: the host the guard needs ------------------------------------------------------------

echo; echo "${BOLD}Instance B: the same Bar.qml with ExpandedHost kept visible while faded out${RESET}  ${DIM}(copy; $patched line changed)${RESET}"
check "B0. the copy has exactly the one ExpandedHost line changed" "1" "$patched"
boot "$sb/notch-visible"
regime closed
check "B1. host closed: visible, enabled (still disabled), opacity 0" "[true,false,0]" "$(host)"
fixtures_for closed-visible true
echo; echo "${BOLD}Numbers, host closed and visible${RESET}  ${DIM}40 measurements each, milliseconds, median / p95 / max${RESET}"
for fx in good antialias many; do numbers closed-visible "$fx"; done
shutdown

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
