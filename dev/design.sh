#!/bin/bash

# One radius (DESIGN-PHILOSOPHY.md, 5), as numbers.
#
#   ./dev/design.sh
#
# Every button, chip, field, switch, highlight, outline and card in the
# settings panel, the menu and the Plugins page uses the notch's bottom radius,
# capped at half its height, whatever the theme's Hyprland rounding is. Runs the
# real Bar.qml in throwaway notches with several bottomRadius values, walks
# every item with a radius in the settings panel, the menu (all of them, folded
# sections and the closed uninstall dialog included) and the Plugins page (its
# list and its confirmation card) and checks each drawn one:
#
#     radius = min(bottomRadius, height / 2, width / 2)
#
# Slider parts are the one exception (DESIGN-PHILOSOPHY.md: circles stay
# circles): a slider's track, fill and knob are round, radius = height / 2.
# Hairlines (1–2 px separators) and gradient fades are not boxes and are
# skipped.
#
# The Plugins page is checked in a sandbox: an empty plugins folder, `false`
# for every command, and a catalogue pointing at local repos holding only a
# manifest, so the page lists both entries as installable and opens a card,
# and never touches anything live.

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
root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-design.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$root"; }
trap cleanup EXIT
ln -s "$SHELL_PATH/shell/Commons" "$root/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root/Ui"
ln -s "$SHELL_PATH/shell/services" "$root/services"
ln -s "$REPO" "$root/notch"
cp "$REPO/dev/harness/shell.qml" "$root/shell.qml"
mkdir -p "$root/plugins"
for id in $(jq -r '.plugins[].id' "$REPO/plugins/catalogue.json"); do
  git -c init.defaultBranch=main init -q "$root/src"
  jq -n --arg id "$id" '{schemaVersion: 1, id: $id, name: $id, version: "1.0.0", kinds: ["bar-widget"]}' >"$root/src/manifest.json"
  git -C "$root/src" add manifest.json && git -C "$root/src" -c user.name=t -c user.email=t@t.invalid commit -q -m init
  git clone -q --bare "$root/src" "$root/gh/$id.git" && rm -rf "$root/src"
done
jq --arg base "file://$root/gh" '.plugins |= map(.url = "\($base)/\(.id).git")' "$REPO/plugins/catalogue.json" >"$root/catalogue.json"
PLUGIN_HOOKS=(NOTCH_FORCE_PLUGINS=1 NOTCH_PLUGINS_DIR="$root/plugins" NOTCH_PLUGINS_OMARCHY=false NOTCH_PLUGINS_CATALOGUE="$root/catalogue.json"
              NOTCH_PLUGINS_SHELL=false NOTCH_PLUGINS_TERMINAL=false NOTCH_PLUGINS_SESSION_LOCKED=false NOTCH_PLUGINS_STATE_DIR="$root/state"
              NOTCH_PLUGINS_SCRATCH="$root/scratch"
              NOTCH_PLUGINS_DETACH=setsid)

# Setup is drawn from a sandbox too: its own state and status, and a detect
# that can't reach the real config.
mkdir -p "$root/setup-home/.config/hypr" "$root/setup-home/.config/omarchy" "$root/setup-state" "$root/setup-run"
echo '{"bar":{"id":"graveklar.notch","layout":{"left":[],"center":[],"right":[]}}}' >"$root/setup-home/.config/omarchy/shell.json"
SETUP_HOOKS=(NOTCH_FORCE_SETUP=1 NOTCH_SETUP_DETACH=setsid NOTCH_SETUP_HOME="$root/setup-home"
             NOTCH_SETUP_CONFIG_DIR="$root/setup-home/.config" NOTCH_SETUP_TOGGLES_DIR="$root/setup-home/toggles"
             NOTCH_SETUP_STATE_DIR="$root/setup-state" NOTCH_SETUP_STATUS="$root/setup-run/setup.json")

ipc() { quickshell ipc -p "$root" call notch "$@" 2>/dev/null; }
start() {
  env NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 NOTCH_HARNESS_CONFIG="$1" "${PLUGIN_HOOKS[@]}" "${SETUP_HOOKS[@]}" quickshell -p "$root" -n >>"$root/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  for _ in $(seq 1 30); do sleep 0.1; [[ $(ipc geometry | jq -r .menu.rowsLoaded) == true ]] && break; done
  sleep 0.5
}
stop() { kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

echo "${BOLD}One radius${RESET}  ${DIM}Hyprland rounding now: $(hyprctl -j getoption decoration:rounding 2>/dev/null | jq -r .int)${RESET}"

for r in ${RADII:-10 8 3 16}; do
  echo; echo "${BOLD}bottomRadius $r${RESET}"
  start "{\"bottomRadius\":$r,\"batteryPeek\":false}"
  # Open both panels once so every delegate exists at its real size.
  ipc settings >/dev/null; sleep 0.9; ipc settings >/dev/null
  ipc menu root >/dev/null; sleep 1.1
  d=$(ipc design)
  ipc menu root >/dev/null
  # The Plugins page, then its card.
  ipc plugins open >/dev/null
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc plugins status | jq -r '.checkedAt > 0') == true ]] && break; done
  sleep 1.1
  page=$(ipc design | jq -c .plugins)
  ipc pluginsPress install:graveklar.face >/dev/null
  for _ in $(seq 1 50); do sleep 0.1; [[ $(ipc plugins status | jq -r '.preview.id != null') == true ]] && break; done
  sleep 0.4
  cardAudit=$(ipc design | jq -c .plugins)
  carded=$(ipc geometry | jq -r .plugins.card)
  ipc pluginsPress escape >/dev/null; ipc plugins close >/dev/null
  # The Setup page (forced on, so a test notch draws it).
  ipc view setup >/dev/null; sleep 1.0
  setupOpen=$(ipc geometry | jq -r .setup.open)
  setupAudit=$(ipc design | jq -c '.setup // []')
  ipc toggle >/dev/null
  d=$(jq -c --argjson page "$page" --argjson card "$cardAudit" --argjson setup "$setupAudit" \
       '.plugins = $page | .pluginsCard = $card | .setup = $setup' <<<"$d")
  report=$(python3 - "$d" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
r = d["radius"]
def audit(items):
    drawn = [i for i in items if i["drawn"] and i["width"] > 0 and i["height"] > 0]
    bad, round_parts = [], 0
    for i in drawn:
        if i["gradient"]:
            continue  # scroll fades, not boxes
        want = max(0, min(r, i["height"] / 2, i["width"] / 2))
        if abs(i["radius"] - want) <= 0.01:
            continue
        if "PanelSlider" in i["path"] and abs(i["radius"] - i["height"] / 2) <= 0.01:
            round_parts += 1
            continue
        if min(i["width"], i["height"]) <= 2:
            continue  # hairline rules (separators) are lines, not rounded boxes
        bad.append(f'{i["type"]} {i["width"]}x{i["height"]} radius {i["radius"]} (want {want:g}) at {i["path"]}')
    return {"total": len(items), "drawn": len(drawn), "roundParts": round_parts, "bad": bad}
out = {"radius": r, "settings": audit(d["settings"]), "menu": audit(d["menu"]),
       "plugins": audit(d["plugins"]), "pluginsCard": audit(d["pluginsCard"]), "setup": audit(d.get("setup", [])),
       "tooltipOk": abs(d["tooltip"]["radius"] - max(0, min(r, d["tooltip"]["height"] / 2))) <= 0.01}
print(json.dumps(out))
PY
)
  echo "  ${DIM}$(jq -c '{radius, settings: (.settings | {total, drawn, roundParts, bad: (.bad | length)}), menu: (.menu | {total, drawn, roundParts, bad: (.bad | length)}), plugins: (.plugins | {total, drawn, bad: (.bad | length)}), card: (.pluginsCard | {total, drawn, bad: (.bad | length)})}' <<<"$report")${RESET}"
  jq -r '(.settings.bad[:6] + .menu.bad[:14] + .plugins.bad[:6] + .pluginsCard.bad[:6] + .setup.bad[:6])[] | "        \(.)"' <<<"$report"
  check "the notch's radius is bottomRadius ($r)" "$r" "$(jq -r .radius <<<"$d")"
  check "settings: every drawn rounded item has radius min($r, height / 2, width / 2)" "true 0" \
    "$(jq -r '.settings | "\(.drawn > 20) \(.bad | length)"' <<<"$report")"
  check "menu: every drawn rounded item (rows, dialog, buttons) has radius min($r, height / 2, width / 2)" "true 0" \
    "$(jq -r '.menu | "\(.drawn > 0) \(.bad | length)"' <<<"$report")"
  check "plugins page: every drawn rounded item (rows, buttons) has radius min($r, height / 2, width / 2)" "true 0" \
    "$(jq -r '.plugins | "\(.drawn > 3) \(.bad | length)"' <<<"$report")"
  check "plugins card (shown): every drawn rounded item (Cancel, Install) has radius min($r, height / 2, width / 2)" "true true 0" \
    "$carded $(jq -r '.pluginsCard | "\(.drawn >= 2) \(.bad | length)"' <<<"$report")"
  # How many rows the page has depends on what detection found in the sandbox,
  # so this asserts the radii, not the amount of content.
  check "setup page: every drawn rounded item (rows, buttons) has radius min($r, height / 2, width / 2)" "true 0" \
    "$setupOpen $(jq -r '.setup.bad | length' <<<"$report")"
  check "the tooltip bubble has the notch's radius" "true" "$(jq -r .tooltipOk <<<"$report")"
  stop
done

if grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$root/qs.log"; then
  check "no QML errors" "none" "$(grep -E 'TypeError|ReferenceError' "$root/qs.log" | head -1)"
fi

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
