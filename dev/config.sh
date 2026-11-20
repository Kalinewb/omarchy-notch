#!/bin/bash

# Exporting and importing the notch's settings, as numbers (plan-export.md).
#
#   ./dev/config.sh
#
# Drives bin/notch-config against a sandbox: a fake home with its own shell.json
# and state folder, a stub for every command, a copy of the notch's manifest and
# catalogue. Nothing here touches the live session. Sections 1 to 7 only read,
# decode and plan (and say so: the calls they made are counted); 8 to 13 apply
# through bin/notch-setup's `config-import` fix on the sandbox's shell.json, with
# the real write path and a stub that only answers `reloadConfig`. The test closes
# by checking that the real shell.json is as it was.
#
#   1   export: the code's shape; the same twice and with shell.json reordered;
#       no sentinel, withheld key, widget option or path; verbatim, never clamped
#   2   the key table is the keys Bar.qml reads, and the panel's
#   3   code, file and standard input give the same staged document; 130 ids
#       are too long for a code, and a file still works
#   4   every rejection exits 2 with its reason and changes nothing; the bomb
#       and a flood on standard input are read to a cap; wrapped codes pass
#   5   clamps to the ceilings, drops with reasons, same colour, plugin ids
#   6   the layout: reordering only, paired by occurrence, options kept
#   7   replace semantics and the preview's words
#   8   apply: a snapshot first, one write, checked; Undo, and the conflict after an edit
#   9   failure: each way it can go wrong ends with the file as it was, and the reloads are counted
#  10   the guard and the staged document: a test notch never writes, nothing outside the staged folder
#  13   lists with several ids, and nothing outside the notch's block or the layout order moves
#  12   static: no privilege, no network, no installer, nothing left in notch-setup
#  14   the words: row ids and labels are the panel's, the tips fit

set -uo pipefail
export LC_ALL=C

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

SCRIPT="$REPO/bin/notch-config"
SETUP="$REPO/bin/notch-setup"
sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-config.XXXXXX")
trap 'rm -rf "$sb"' EXIT

# What the real session holds now; checked again at the end.
REAL_SHELL_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/omarchy/shell.json"
REAL_STAGED="${XDG_STATE_HOME:-$HOME/.local/state}/kalinewb.notch/setup/staged"
real_before=$(sha256sum "$REAL_SHELL_JSON" 2>/dev/null | cut -d' ' -f1)
real_staged_before=$(ls -A "$REAL_STAGED" 2>/dev/null | wc -l)

# --- the sandbox ---------------------------------------------------------------------

HOME_SB="$sb/home"
CONFIG_SB="$HOME_SB/.config"
SHELL_SB="$CONFIG_SB/omarchy/shell.json"
STATE_SB="$HOME_SB/.local/state/kalinewb.notch/setup"
NOTCH_SB="$sb/notch"
BIN="$sb/bin"
CALLS="$sb/calls"
mkdir -p "$CONFIG_SB/omarchy" "$STATE_SB" "$sb/omarchy" "$NOTCH_SB/plugins" "$BIN"
mkdir -p "$NOTCH_SB/bin"
cp "$REPO/bin/notch-config" "$REPO/bin/notch-lib.sh" "$REPO/bin/notch-setup" "$REPO/bin/notch-setup-binds.lua" "$NOTCH_SB/bin/"
jq '.version = "9.9.9-fixture"' "$REPO/manifest.json" >"$NOTCH_SB/manifest.json"
cp "$REPO/plugins/catalogue.json" "$NOTCH_SB/plugins/catalogue.json"

# Every command it can run is a stub that records the call.
cat >"$BIN/omarchy" <<EOF
#!/bin/bash
printf '%s\n' "omarchy \$*" >>"$CALLS"
[[ "\$*" == "plugin list --json" ]] && cat "$sb/plugins.json"
exit 0
EOF
# The shell answers only `reloadConfig` (the write itself is the script's, through the
# real commit_shell). SB_STALE=1 makes it write the old file back after a reload, as a
# shell that held stale memory would; SB_EDIT=<file> makes the plugin list change
# shell.json while a plan is being made.
cat >"$BIN/omarchy-shell" <<EOF
#!/bin/bash
printf '%s\n' "omarchy-shell \$*" >>"$CALLS"
if [[ "\$*" == *reloadConfig* ]]; then
  [[ \${SB_STALE:-} == 1 ]] && cp "$sb/stale.json" "$SHELL_SB"
  echo ok
fi
exit 0
EOF
cat >"$BIN/omarchy" <<EOF
#!/bin/bash
printf '%s\n' "omarchy \$*" >>"$CALLS"
if [[ "\$*" == "plugin list --json" ]]; then
  [[ -n \${SB_EDIT:-} ]] && cp "\$SB_EDIT" "$SHELL_SB"
  cat "$sb/plugins.json"
fi
exit 0
EOF
for stub in hyprctl omarchy-toggle-bar qs fakekill restart-shell busctl; do
  printf '#!/bin/bash\nprintf "%%s\\n" "%s \$*" >>"%s"\nexit 0\n' "$stub" "$CALLS" >"$BIN/$stub"
done
printf '#!/bin/bash\nexit ${SB_LOCKED:-1}\n' >"$BIN/session-locked"
printf '#!/bin/bash\necho 4.0.3-fixture\n' >"$BIN/omarchy-version"
chmod +x "$BIN"/*
cat >"$sb/plugins.json" <<'JSON'
[{"id": "kalinewb.notch"}, {"id": "omarchy.menu"}, {"id": "omarchy.clock"}, {"id": "omarchy.spacer"},
 {"id": "omarchy.audio"}, {"id": "omarchy.tray"}]
JSON

env_common=(
  NOTCH_SETUP_HOME="$HOME_SB" NOTCH_SETUP_CONFIG_DIR="$CONFIG_SB" NOTCH_SETUP_TOGGLES_DIR="$HOME_SB/.local/state/omarchy/toggles"
  NOTCH_SETUP_STATE_DIR="$STATE_SB" NOTCH_SETUP_STATUS="$sb/run/setup.json" NOTCH_SETUP_OMARCHY_PATH="$sb/omarchy"
  NOTCH_SETUP_PLUGINS_DIR="$CONFIG_SB/omarchy/plugins" NOTCH_SETUP_NOTCH_DIR="$NOTCH_SB"
  NOTCH_SETUP_OMARCHY="$BIN/omarchy" NOTCH_SETUP_OMARCHY_SHELL="$BIN/omarchy-shell" NOTCH_SETUP_OMARCHY_VERSION="$BIN/omarchy-version"
  NOTCH_SETUP_HYPRCTL="$BIN/hyprctl" NOTCH_SETUP_TOGGLE_BAR="$BIN/omarchy-toggle-bar" NOTCH_SETUP_QS="$BIN/qs"
  NOTCH_SETUP_KILL="$BIN/fakekill" NOTCH_SETUP_SESSION_LOCKED="$BIN/session-locked" NOTCH_SETUP_RESTART_SHELL="$BIN/restart-shell"
  NOTCH_SETUP_BUSCTL="$BIN/busctl"
)
nc() { env "${env_common[@]}" "$SCRIPT" "$@"; }
calls() { cat "$CALLS" 2>/dev/null; }
shell_hash() { sha256sum "$SHELL_SB" | cut -d' ' -f1; }
state_files() { find "$STATE_SB" -type f 2>/dev/null | wc -l; }

# A sender with every one of the 50 keys set, the three withheld, sentinels, a
# clock format, two spacers; and a receiver that has hardly any.
SENDER='{
  "bar": {
    "id": "kalinewb.notch", "position": "top", "centerAnchor": "omarchy.clock", "bar-sentinel": "SENTINEL-BAR",
    "layout": {
      "left": [{"id": "omarchy.menu"}],
      "center": [{"id": "omarchy.clock", "format": "SENTINEL-FORMAT d MMM"}, "omarchy.spacer", {"id": "omarchy.spacer"}],
      "right": [{"id": "omarchy.audio", "barMode": "Icon"}, {"id": "omarchy.tray"}]
    },
    "notch": {
      "compact": ["clock"], "autoHide": true, "batteryGlow": false, "glowStyle": "bottom",
      "openWith": ["click", "doubleClick"], "openAction": "plugin", "openPlugin": "omarchy.audio",
      "notifications": true, "notificationLight": "top", "compactWidth": 700,
      "hoverItems": ["clock", "date"], "hoverPlugins": ["omarchy.audio"], "hiddenPlugins": ["omarchy.spacer", "omarchy.tray"],
      "expanded": ["battery"], "hostedPanels": ["omarchy.audio", "omarchy.clock", "kalinewb.face"],
      "disabledIntegrations": ["omarchy.tray"], "bottomRadius": 8, "filletRadius": 12,
      "notificationStay": false, "notificationSeconds": 10, "notificationLightColours": "blue",
      "peekOnTrackChange": false, "batteryPeek": true, "glowScale": 0.5, "greenAbove": 80, "lowBattery": 25,
      "openKey": "ALT + X", "settingsKey": "ALT + C", "autoHideKey": "ALT + Z", "stayOpenKey": "ALT + B",
      "stayOpen": false, "windowsToTop": true, "updateCheck": false,
      "settingsWith": ["longRightClick"], "menuWith": ["rightClick"], "menuKey": "ALT + M", "stateKey": "ALT + Q",
      "compactHeight": 40, "criticalBattery": 12,
      "color": "#101010", "foreground": "#EEEEEE", "chargingColor": "#FFB340", "fullColor": "#30D158", "lowColor": "#FF453A",
      "hoverDelay": 80, "collapseDelay": 400, "peekDuration": 5000,
      "hoverAction": "widgets", "hoverPlugin": "omarchy.audio", "expandOn": "click",
      "replaceMenu": true, "replaceOsd": true, "suppressNativeToast": true, "hostedMono": "SENTINEL-MONO", "futureThing": 1
    }
  },
  "plugins": [{"id": "sentinel.plugin", "token": "SENTINEL-PLUGIN"}], "disabledPlugins": ["sentinel.off"], "cloneSourceRestores": ["sentinel.clone"]
}'
RECEIVER='{
  "bar": { "id": "kalinewb.notch", "position": "top",
    "layout": {"left": [{"id": "omarchy.menu"}], "center": [{"id": "omarchy.clock", "format": "HH:mm"}, "omarchy.spacer", {"id": "omarchy.spacer"}],
               "right": [{"id": "omarchy.audio"}, {"id": "omarchy.tray"}]},
    "notch": {"autoHide": false, "bottomRadius": 10, "replaceMenu": false, "hostedMono": true}},
  "plugins": [{"id": "sentinel.plugin"}], "disabledPlugins": ["sentinel.off"], "cloneSourceRestores": ["sentinel.clone"] }'
put() { printf '%s\n' "$1" >"$SHELL_SB"; }

# The same encoding, written out again here, so a test can build any document.
payload_of() { jq -S -c . <<<"$1" | gzip -9 -n | base64 -w0 | tr '+/' '-_' | tr -d '='; }
mkcode() { local p; p=$(payload_of "$1"); printf 'notch1.%s.%s' "$(printf '%s' "$p" | sha256sum | cut -c1-8)" "$p"; }
decode() { local p=${1##*.}; p=${p//-/+}; p=${p//_//}; while (( ${#p} % 4 )); do p+="="; done; printf '%s' "$p" | base64 -d | gzip -dc; }
doc() { jq -nc --argjson s "$1" '{format: "kalinewb.notch-config", version: 1, settings: $s}'; }
docl() { jq -nc --argjson s "$1" --argjson l "$2" '{format: "kalinewb.notch-config", version: 1, settings: $s, layout: $l}'; }
plan() { nc import "$1" --stage 2>/dev/null; }          # plan <code or file>
planf() { printf '%s\n' "$1" >"$sb/in.json"; plan "$sb/in.json"; }

echo "${BOLD}bin/notch-config${RESET}  ${DIM}sandbox $sb${RESET}"

# ---------------------------------------------------------------------------------
# 1  Export
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}1  Export${RESET}"
put "$SENDER"
code=$(nc export)
check "1. a code is notch1.<8 hex>.<url-safe payload>" "true" "$([[ $code =~ ^notch1\.[0-9a-f]{8}\.[A-Za-z0-9_-]+$ ]] && echo true || echo false)"
check "1a. the same twice" "$code" "$(nc export)"
reordered=$(jq '.bar.notch |= (to_entries | reverse | from_entries) | . |= (to_entries | reverse | from_entries)' "$SHELL_SB")
put "$reordered"
check "1b. the same with shell.json's keys in another order" "$code" "$(nc export)"
put "$SENDER"
dec=$(decode "$code")
check "1c. the document: format, version, the notch's own version" "kalinewb.notch-config 1 9.9.9-fixture" \
  "$(jq -r '"\(.format) \(.version) \(.notch)"' <<<"$dec")"
check "1d. all 50 keys that were set, and the widget order as ids" "50 center,left,right 3" \
  "$(jq -r '"\(.settings | length) \(.layout | keys | join(",")) \(.layout.center | length)"' <<<"$dec")"
check "1e. no sentinel, no withheld key, no widget option, no path" "0 0 0 0" \
  "$(grep -c 'SENTINEL' <<<"$dec") $(jq '[.settings | keys[] | select(IN("replaceMenu", "replaceOsd", "suppressNativeToast", "hostedMono", "futureThing"))] | length' <<<"$dec") $(jq '[.layout[][] | select(type != "string")] | length' <<<"$dec") $(jq '[.. | strings | select(test("[/\\\\~]"))] | length' <<<"$dec")"
put "$(jq '.bar.notch.compactWidth = 9999 | .bar.notch.hoverDelay = 1e9' <<<"$SENDER")"
check "1f. verbatim: export never clamps (9999 stays 9999, 1e9 stays 1e9)" "true" \
  "$(jq '.settings.compactWidth == 9999 and .settings.hoverDelay == 1000000000' <<<"$(decode "$(nc export)")")"
put "$(jq 'del(.bar.layout) | .bar.notch = {menuKey: "", autoHide: null, openKey: "ALT + X"}' <<<"$SENDER")"
check "1g. null and empty read as unset: only openKey is exported, and no layout" "openKey false" \
  "$(jq -r '"\(.settings | keys | join(",")) \(has("layout"))"' <<<"$(decode "$(nc export)")")"
out="$sb/out/notch-config.json"; mkdir -p "$sb/out"
put "$SENDER"
nc export --file "$out"; rc=$?
check "1h. --file writes the same document, 644, no stray temp file" "0 $(jq -S -c . <<<"$dec") 644 1" \
  "$rc $(jq -S -c . "$out") $(stat -c %a "$out") $(ls -A "$sb/out" | wc -l)"
echo '{"not": "ours"}' >"$sb/out/other.json"
nc export --file "$sb/out/other.json" 2>/dev/null; rc1=$?
nc export --file "$SHELL_SB" 2>/dev/null; rc2=$?
nc export --file "$sb/out" 2>/dev/null; rc3=$?
check "1i. --file refuses a file that is not a notch-config one, shell.json, and a folder" "2 2 2 true" \
  "$rc1 $rc2 $rc3 $([[ $(cat "$sb/out/other.json") == '{"not": "ours"}' && $(shell_hash) == $(printf '%s\n' "$SENDER" | sha256sum | cut -d' ' -f1) ]] && echo true || echo false)"
nc export --file "$out"; rc=$?
check "1j. --file over its own earlier file is allowed" "0" "$rc"

# ---------------------------------------------------------------------------------
# 2  The key table
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}2  The key table${RESET}"
table=$(nc table)
check "2. the table has 50 keys and 3 withheld, none twice, none both" "50 3 0" \
  "$(jq -r '"\(.keys | length) \(.withheld | length) \([.keys | keys[] | select(IN($t.withheld | keys[]))] | length)"' --argjson t "$table" <<<"$table")"
bar_keys=$(grep -ohE 'notch(Setting|Number|Items|Triggers)\("[A-Za-z]+"' "$REPO/Bar.qml" | sed 's/.*("//; s/"//' | sort -u)
panel_keys=$( { grep -ohE '(notchSetting|set)\("[A-Za-z]+"' "$REPO/NotchSettings.qml" | sed 's/.*("//; s/"//'
                grep -ohE 'keys: \[[^]]*\]' "$REPO/NotchSettings.qml" | grep -oE '"[A-Za-z]+"' | tr -d '"'; } | sort -u)
known_keys=$(jq -r '(.keys | keys) + (.withheld | keys) | sort | .[]' <<<"$table")
# The glow's two keys are in the panel and the table, and Bar.qml reads them when the glow plan lands.
pending="notificationLight notificationLightColours"
check "2a. Bar.qml reads $(wc -l <<<"$bar_keys") keys, every one in the table or withheld" "" \
  "$(comm -23 <(echo "$bar_keys") <(echo "$known_keys") | paste -sd' ')"
check "2b. the table has nothing Bar.qml does not read, but the pending glow keys" "$pending" \
  "$(comm -13 <(echo "$bar_keys") <(echo "$known_keys") | paste -sd' ')"
check "2c. 51 keys on master, 53 once the glow keys are read" "true" \
  "$([[ $(wc -l <<<"$bar_keys") == 51 || $(wc -l <<<"$bar_keys") == 53 ]] && echo true || echo false)"
check "2d. every key the panel names is in the table or withheld" "" \
  "$(comm -23 <(echo "$panel_keys") <(echo "$known_keys") | paste -sd' ')"
check "2e. every table key with a row is among that row's keys in the panel" "" "$(python3 - "$REPO/NotchSettings.qml" "$table" <<'PY'
import json, re, sys
src, table = open(sys.argv[1]).read(), json.loads(sys.argv[2])
rows = {}
for m in re.finditer(r'rid: "(\w+)";[^\n]*?keys: \[([^\]]*)\]', src):
    rows[m.group(1)] = re.findall(r'"(\w+)"', m.group(2))
rows["keybinds"] = ["openKey", "settingsKey", "autoHideKey", "stayOpenKey"]
bad = [f'{k}: {s["row"]}' for k, s in table["keys"].items() if "row" in s and k not in rows.get(s["row"], [])]
print("; ".join(bad))
PY
)"

# ---------------------------------------------------------------------------------
# 3  Round trip
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}3  Round trip${RESET}"
put "$SENDER"; code=$(nc export); nc export --file "$sb/sent.json"
put "$RECEIVER"
a=$(nc import "$code" --stage); path_a=$(jq -r .staged <<<"$a")
cp "$path_a" "$sb/staged-code.json"
b=$(nc import "$sb/sent.json" --stage); path_b=$(jq -r .staged <<<"$b")
c=$(printf '%s' "$code" | nc import - --stage)
pa=$(jq -S -c 'del(.staged)' <<<"$a"); pb=$(jq -S -c 'del(.staged)' <<<"$b"); pc=$(jq -S -c 'del(.staged)' <<<"$c")
check "3. the code, the file and standard input give one staged document and one plan" "same same" \
  "$(cmp -s "$sb/staged-code.json" "$path_b" && echo same || echo DIFFERENT) $([[ $pa == "$pb" && $pa == "$pc" ]] && echo same || echo DIFFERENT)"
check "3a. the staged file is the decoded document, as the original export" "$(jq -S -c . "$sb/sent.json")" \
  "$(jq -S -c 'del(.notch)' "$sb/staged-code.json" | jq -S -c '. + {notch: "9.9.9-fixture"}')"
check "3b. staged: the folder 700, the file 600, named for the plan's hash" "700 600 true" \
  "$(stat -c %a "$STATE_SB/staged") $(stat -c %a "$path_a") $([[ $path_a == "$STATE_SB/staged/$(jq -r .hash <<<"$a").json" ]] && echo true || echo false)"
check "3c. plan <staged> says what import said" "$(jq -S -c 'del(.staged)' <<<"$a")" "$(nc plan "$path_a" | jq -S -c .)"
check "3d. the fields --stage prints" "before,changes,hash,layout,moves,notch,skipped,staged" "$(jq -r 'keys | join(",")' <<<"$a")"
check "3e. a plan is a preview: the same receiver, the same plan" "$(jq -r .hash <<<"$a")" "$(nc import "$code" --stage | jq -r .hash)"
ids=$(for i in $(seq 1 130); do head -c 96 /dev/urandom | base64 -w0 | tr '+/' 'A_' | cut -c1-128; done | jq -R . | jq -sc .)
put "$(jq --argjson ids "$ids" '.bar.notch.hiddenPlugins = $ids' <<<"$SENDER")"
out=$(nc export 2>"$sb/err"); rc=$?
check "3f. 130 long ids are too long for a code: exit 2, too-long, nothing printed" "2 too-long empty" \
  "$rc $(sed 's/.*: //' "$sb/err") $([[ -z $out ]] && echo empty || echo printed)"
nc export --file "$sb/big.json"; rc=$?
check "3g. …and --file still works" "0 130" "$rc $(jq '.settings.hiddenPlugins | length' "$sb/big.json")"
check "3h. nothing to change: your own export, on your own config" "Nothing to change 0" \
  "$(put "$SENDER"; nc import "$(nc export)") $(ls -A "$STATE_SB/staged" | grep -c '^\.partial')"

# ---------------------------------------------------------------------------------
# 4  Rejections
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}4  Rejections${RESET}"
put "$RECEIVER"; h=$(shell_hash); rm -rf "$STATE_SB/staged"
# rejected <arg>: "<exit code> <reason> <shell.json unchanged> <nothing staged>"
rejected() {
  local out rc
  out=$(nc import "$1" --stage 2>"$sb/err"); rc=$?
  echo "$rc $(sed 's/.*: //' "$sb/err" | tail -1) $([[ $(shell_hash) == "$h" ]] && echo same || echo CHANGED) $([[ -d $STATE_SB/staged ]] && echo staged || echo none) $(jq -r '.reason // ""' <<<"$out")"
}
good=$(mkcode "$(doc '{"autoHide": true}')")
flip() { local s=$1 i=$2; local c=${s:$i:1}; local r=A; [[ $c == A ]] && r=B; printf '%s%s%s' "${s:0:$i}" "$r" "${s:$((i + 1))}"; }
check "4. hello: not-code" "2 not-code same none not-code" "$(rejected hello)"
check "4a. empty: empty" "2 empty same none empty" "$(rejected '')"
check "4b. notch1.: not-code" "2 not-code same none not-code" "$(rejected 'notch1.')"
check "4c. a truncated code: damaged" "2 damaged same none damaged" "$(rejected "${good:0:$((${#good} - 8))}")"
check "4d. one payload character flipped: damaged" "2 damaged same none damaged" "$(rejected "$(flip "$good" $((${#good} - 5)))")"
check "4e. one check character flipped: damaged" "2 damaged same none damaged" "$(rejected "$(flip "$good" 8)")"
check "4f. notch2. with a valid check: newer" "2 newer same none newer" "$(rejected "notch2.${good#notch1.}")"
for v in '2' '0' '"1"' 'null'; do
  check "4g. version $v inside: $([[ $v == 2 ]] && echo newer || echo not-code)" "2 $([[ $v == 2 ]] && echo newer || echo not-code) same none $([[ $v == 2 ]] && echo newer || echo not-code)" \
    "$(rejected "$(mkcode "$(jq -nc --argjson v "$v" '{format: "kalinewb.notch-config", version: $v, settings: {}}')")")"
done
check "4h. version missing: not-code" "2 not-code same none not-code" "$(rejected "$(mkcode '{"format": "kalinewb.notch-config", "settings": {}}')")"
check "4i. the wrong format: not-code" "2 not-code same none not-code" "$(rejected "$(mkcode '{"format": "other", "version": 1, "settings": {}}')")"
check "4j. no settings: not-code" "2 not-code same none not-code" "$(rejected "$(mkcode '{"format": "kalinewb.notch-config", "version": 1}')")"
check "4k. settings that are not an object: not-code" "2 not-code same none not-code" "$(rejected "$(mkcode '{"format": "kalinewb.notch-config", "version": 1, "settings": [1]}')")"
check "4l. a code over 12,000 characters: too-long, before decoding" "2 too-long same none too-long" "$(rejected "notch1.00000000.$(head -c 12000 /dev/zero | tr '\0' A)")"
head -c 65537 /dev/zero | tr '\0' ' ' >"$sb/huge.json"
check "4m. a file over 65,536 bytes: too-long" "2 too-long same none too-long" "$(rejected "$sb/huge.json")"
printf '{"format": "kalinewb.notch-config", "version": 1, "settings": {"x": ' >"$sb/cut.json"
check "4n. a JSON file that stops short: damaged" "2 damaged same none damaged" "$(rejected "$sb/cut.json")"
check "4o. a path that is not a file: not-code" "2 not-code same none not-code" "$(rejected "$sb/no-such-file")"

# The bomb: 9 MB of zeros is a short code. Measured at the decoder's output, through a
# `head` that writes down what it passed on.
cat >"$BIN/head" <<EOF
#!/bin/bash
out=\$(mktemp "$sb/head.XXXXXX")
/usr/bin/head "\$@" >"\$out"; rc=\$?
wc -c <"\$out" >>"$sb/head.log"
cat "\$out"; rm -f "\$out"
exit \$rc
EOF
chmod +x "$BIN/head"
bomb=$(head -c 9000000 /dev/zero | gzip -9 -n | base64 -w0 | tr '+/' '-_' | tr -d '=')
bomb="notch1.$(printf '%s' "$bomb" | sha256sum | cut -c1-8).$bomb"
: >"$sb/head.log"
res=$(PATH="$BIN:$PATH" rejected "$bomb")
check "4p. the bomb ($(( ${#bomb} )) characters, 9 MB inside): damaged, under pipefail" "2 damaged same none damaged" "$res"
check "4q. …and the decoder's output was cut at 65,537 bytes, not more" "65537 true" \
  "$(sort -n "$sb/head.log" | tail -1) $([[ $(sort -n "$sb/head.log" | tail -1) -le 65537 ]] && echo true || echo false)"
cat >"$BIN/wl-paste" <<EOF
#!/bin/bash
head -c 1000000 /dev/zero | tr '\0' A
EOF
chmod +x "$BIN/wl-paste"
: >"$sb/head.log"
PATH="$BIN:$PATH" bash -c 'timeout 2 wl-paste -n | head -c 12001 | tee "$2" | "$0" import - --stage 2>"$1"' "$SCRIPT" "$sb/err" "$sb/clip" >/dev/null 2>&1
check "4r. a clipboard of 1 MB is read for 12,001 bytes, and that is too-long" "12001 too-long same" \
  "$(wc -c <"$sb/clip") $(sed 's/.*: //' "$sb/err" | tail -1) $([[ $(shell_hash) == "$h" ]] && echo same || echo CHANGED)"
rm -f "$BIN/head" "$BIN/wl-paste"
flood=$(head -c 1000000 /dev/zero | tr '\0' A | PATH="$BIN:$PATH" nc import - --stage 2>&1 >/dev/null | tail -1 | sed 's/.*: //')
check "4s. a flood on standard input is refused after 64 KB: too-long" "too-long" "$flood"
doc_ok=$(doc '{"autoHide": true}')
wrapped_ok=0
c4=$(mkcode "$doc_ok")
for form in "$(fold -w 40 <<<"$c4")" "\"$c4\"" "'$c4'" "\`$c4\`" "$c4." "$c4)." "$c4," "  $c4  " "$c4;"; do
  [[ $(nc import "$form" --stage 2>/dev/null | jq -r '.changes[0].label' 2>/dev/null) == Auto-hide ]] && wrapped_ok=$((wrapped_ok + 1))
done
check "4t. wrapped, quoted, backticked, full-stopped and bracketed-after codes all pass (9 forms)" "9" "$wrapped_ok"
check "4u. so does the same text on standard input" "Auto-hide" "$(fold -w 30 <<<"\"$c4\".  " | nc import - --stage 2>/dev/null | jq -r '.changes[0].label')"
check "4v. a code saved in a text file passes" "Auto-hide" "$(printf '%s\n' "$c4" >"$sb/code.txt"; nc import "$sb/code.txt" --stage 2>/dev/null | jq -r '.changes[0].label')"
check "4w. --yes on a code that is no code: exit 2 and nothing changed" "2 same" "$(nc import hello --yes >/dev/null 2>&1; echo -n "$? "; [[ $(shell_hash) == "$h" ]] && echo same || echo CHANGED)"

# ---------------------------------------------------------------------------------
# 5  Clamps and drops
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}5  Clamps and drops${RESET}"
put "$(jq '.bar.notch = {autoHide: true, color: "#0A0A0A", openKey: "ALT + K", hoverPlugins: ["omarchy.audio"]}' <<<"$RECEIVER")"
p=$(planf "$(doc '{"compactWidth": -5, "compactHeight": 5000, "bottomRadius": 500, "hoverDelay": 1e9, "collapseDelay": 1e9, "peekDuration": 100, "glowScale": 9, "greenAbove": 150, "lowBattery": 400, "filletRadius": 12}')")
check "5. clamped: width 0, height 120, radius 96, hover 2000, close 10000, peek 500, glow 2.5, green 100, low 100" \
  "0 120 96 2000 10000 500 2.5 100 100 12" "$(jq -r '.notch | "\(.compactWidth) \(.compactHeight) \(.bottomRadius) \(.hoverDelay) \(.collapseDelay) \(.peekDuration) \(.glowScale) \(.greenAbove) \(.lowBattery) \(.filletRadius)"' <<<"$p")"
check "5a. each is in skipped with its label and capped or raised (and 12 is not)" \
  "Close delay:capped Corners:capped Glow size:capped Green from:capped Height:capped Hover delay:capped Low battery at:capped Peek time:raised Width:raised" \
  "$(jq -r '[.skipped[] | "\(.label):\(.reason)"] | sort | join(" ")' <<<"$p")"
p=$(planf "$(doc '{"compactWidth": 700, "notificationSeconds": 7.4, "peekDuration": 700}')")
check "5b. 700 is untouched and says nothing; 7.4 seconds rounds to 7" "700 7 700 0" \
  "$(jq -r '"\(.notch.compactWidth) \(.notch.notificationSeconds) \(.notch.peekDuration) \(.skipped | length)"' <<<"$p")"
p=$(planf "$(doc '{"autoHide": "yes", "color": "red", "openKey": "alt x!", "futureKey": 1, "glowStyle": "sideways", "hoverItems": "clock", "notificationStay": 1}')")
check "5c. wrong type, bad colour, bad key, unknown, wrong choice: each dropped with its reason" \
  "Auto-hide:invalid Charging glow:invalid Colour:invalid Keybinds:invalid Notification time:invalid On hover:invalid futureKey:unknown" \
  "$(jq -r '[.skipped[] | "\(.label):\(.reason)"] | sort | join(" ")' <<<"$p")"
check "5d. …and the receiver's value is kept: autoHide true, colour, key" "true #0A0A0A ALT + K" \
  "$(jq -r '"\(.notch.autoHide) \(.notch.color) \(.notch.openKey)"' <<<"$p")"
check "5e. …a key the file lacks goes back to default: the hover plugin is gone" "false" "$(jq '.notch | has("hoverPlugins")' <<<"$p")"
p=$(planf "$(doc '{"color": "#112233", "foreground": "#112233FF"}')")
check "5f. the same colour twice: both dropped, the receiver's colour kept" "same-colour same-colour #0A0A0A false" \
  "$(jq -r '[.skipped[] | .reason | gsub(" "; "-")] | join(" ")' <<<"$p") $(jq -r '.notch.color' <<<"$p") $(jq '.notch | has("foreground")' <<<"$p")"
p=$(planf "$(doc '{"color": "#112233", "foreground": "#112234"}')")
check "5g. two different colours both pass" "#112233 #112234 0" "$(jq -r '"\(.notch.color) \(.notch.foreground) \(.skipped | length)"' <<<"$p")"
p=$(planf "$(doc '{"foreground": "#0a0a0a"}')")
check "5h. a colour equal to the receiver's other one (case ignored): dropped" "same colour" "$(jq -r '.skipped[0].reason' <<<"$p")"
long_id=$(printf 'x%.0s' $(seq 1 200))
p=$(planf "$(doc "$(jq -nc --arg l "$long_id" '{hiddenPlugins: ["../x", $l, "uninstalled.plugin", "omarchy.spacer", "graveklar.face", "omarchy.spacer", "has space"]}')")")
check "5i. ../x, 200 characters, a space and an uninstalled id are left out; graveklar.face becomes kalinewb.face; no duplicates" \
  "omarchy.spacer,kalinewb.face invalid:3 not installed:1" \
  "$(jq -r '.notch.hiddenPlugins | join(",")' <<<"$p") $(jq -r '[.skipped[] | "\(.reason):\(.count)"] | join(" ")' <<<"$p" | sed 's/ not/ not/')"
p=$(planf "$(doc '{"openPlugin": "../x", "hoverPlugin": "nobody.home", "hostedPanels": ["omarchy.audio", "omarchy.clock"], "disabledIntegrations": ["notch.media"]}')")
check "5j. single plugin ids are checked too; installed and built-in ids pass" "false false omarchy.audio,omarchy.clock notch.media" \
  "$(jq -r '.notch | "\(has("openPlugin")) \(has("hoverPlugin")) \(.hostedPanels | join(",")) \(.disabledIntegrations | join(","))"' <<<"$p")"
many=$(jq -nc '[range(150) | "omarchy.audio"] + ["omarchy.clock"]')
p=$(planf "$(doc "$(jq -nc --argjson m "$many" '{hiddenPlugins: $m}')")")
check "5k. at most 100 entries in a list" "too many" "$(jq -r '[.skipped[] | .reason] | join(",")' <<<"$p" | cut -c1-8)"
p=$(planf "$(doc '{"replaceMenu": true, "replaceOsd": true, "suppressNativeToast": true}')")
check "5l. the three withheld keys in a file are not taken, and the receiver's are never touched" "Menu,Volume and brightness,Notifications false" \
  "$(jq -r '[.skipped[].label] | join(",")' <<<"$p") $(jq '.notch | has("replaceMenu")' <<<"$p")"
p=$(planf "$(doc "$(jq -nc '[range(40)] | map({key: "k\(.)", value: 1}) | from_entries')")")
check "5m. forty unknown keys: ten listed" "10" "$(jq '.skipped | length' <<<"$p")"

# ---------------------------------------------------------------------------------
# 6  The layout
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}6  The layout${RESET}"
put "$RECEIVER"
before_ids() { jq -c '[.. | objects | select(has("id")) | .id] | sort' <<<"$1"; }
p=$(planf "$(docl '{}' '{"center": ["omarchy.spacer", "omarchy.clock", "omarchy.spacer"], "right": ["omarchy.tray", "omarchy.audio"]}')")
check "6. the ids are the same before and after; the right region is reordered" "$(before_ids "$(jq .before.layout <<<"$p")") 2 omarchy.tray,omarchy.audio" \
  "$(jq -c '[.layout | .. | objects | select(has("id")) | .id] | sort' <<<"$p" | sed 's/^$//') $(jq '.moves | length' <<<"$p") $(jq -r '[.layout.right[] | if type == "object" then .id else . end] | join(",")' <<<"$p")"
p=$(planf "$(docl '{}' '{"center": ["omarchy.clock", "omarchy.spacer"]}')")
check "6a. the file names one spacer: the other stays, after it" "omarchy.clock,omarchy.spacer,omarchy.spacer" \
  "$(jq -r '[.layout.center[] | if type == "object" then .id else . end] | join(",")' <<<"$p")"
p=$(planf "$(docl '{}' '{"center": ["omarchy.spacer", "omarchy.spacer", "omarchy.spacer", "nobody.here", "../x", "omarchy.clock"]}')")
check "6b. a third spacer, an id this bar lacks and a bad one are skipped; nothing is added" "3 3 omarchy.spacer,omarchy.spacer,omarchy.clock" \
  "$(jq '[.skipped[] | select(.key == "layout")] | length' <<<"$p") $(jq '.layout.center | length' <<<"$p") $(jq -r '[.layout.center[] | if type == "object" then .id else . end] | join(",")' <<<"$p")"
check "6c. the clock keeps its own format" "HH:mm" "$(jq -r '.layout.center[] | select(type == "object" and .id == "omarchy.clock") | .format' <<<"$p")"
p=$(planf "$(docl '{}' '{"left": ["omarchy.audio"]}')")
check "6d. a region the file omits is left alone: the audio widget stays on the right; the file's copy is skipped" "omarchy.audio,omarchy.tray 1" \
  "$(jq -r '[.layout.right[] | if type == "object" then .id else . end] | join(",")' <<<"$p") $(jq '[.skipped[] | select(.key == "layout")] | length' <<<"$p")"
p=$(planf "$(docl '{}' '{"left": ["omarchy.tray"], "right": ["omarchy.audio"]}')")
check "6e. a widget moves between regions, and the plan counts it" "omarchy.tray,omarchy.menu omarchy.audio true 1" \
  "$(jq -r '[.layout.left[] | if type == "object" then .id else . end] | join(",")' <<<"$p") $(jq -r '[.layout.right[] | if type == "object" then .id else . end] | join(",")' <<<"$p") $(jq '(.moves | map(.id) | index("omarchy.tray")) != null' <<<"$p") $(jq '.moves | length' <<<"$p")"
p=$(planf "$(docl '{}' '{"center": ["omarchy.clock"]}')")
check "6f. one widget in front of two others is one move, not three" "1" "$(planf "$(docl '{}' '{"center": ["omarchy.spacer", "omarchy.spacer", "omarchy.clock"]}')" | jq '.moves | length')"
check "6g. the same order is no move and no change" "Nothing to change" "$(nc import "$(printf '%s\n' "$(docl '{}' '{"center": ["omarchy.clock", "omarchy.spacer", "omarchy.spacer"]}')" >"$sb/same.json"; echo "$sb/same.json")")"
put "$(jq 'del(.bar.layout)' <<<"$RECEIVER")"
p=$(planf "$(docl '{"autoHide": true}' '{"center": ["omarchy.clock"]}')")
check "6h. a receiver with no layout: none is made" "null 0" "$(jq -r '"\(.layout) \(.moves | length)"' <<<"$p")"

# ---------------------------------------------------------------------------------
# 7  Replace, and the words
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}7  Replace and the preview's words${RESET}"
put "$(jq '.bar.notch = {autoHide: true, bottomRadius: 8, filletRadius: 12, hiddenPlugins: ["omarchy.spacer"], openKey: "ALT + X"}' <<<"$RECEIVER")"
p=$(planf "$(doc '{"bottomRadius": 12, "filletRadius": 12}')")
check "7. a key the code lacks goes back to default: Hidden widgets  1 hidden → None, Auto-hide  On → Off" "Hidden widgets  1 hidden → None|Auto-hide  On → Off" \
  "$(nc import "$sb/in.json" | grep -E 'Auto-hide|Hidden' | sed 's/^ *//' | paste -sd'|')"
check "7a. the corners say 8 / 12 px → 12 px" "8 / 12 px 12 px" "$(jq -r '.changes[] | select(.row == "corners") | "\(.from) \(.to)"' <<<"$p")"
check "7b. keybind and plugin-id changes are danger, and come first" "Keybinds Hidden widgets" \
  "$(jq -r '[.changes[] | select(.danger) | .label] | sort | reverse | join(" ")' <<<"$p")"
check "7c. replace: the withheld key and a sentinel in the block are never touched" "true" \
  "$(put "$(jq '.bar.notch.replaceMenu = true | .bar.notch.hostedMono = "S" | .bar.notch.stray = 1' <<<"$RECEIVER")"; planf "$(doc '{"autoHide": true}')" | jq '.notch.replaceMenu == true and .notch.hostedMono == "S" and .notch.stray == 1')"

put "$(jq '.bar.notch = {autoHide: true, bottomRadius: 8, filletRadius: 12, hiddenPlugins: ["omarchy.spacer", "omarchy.tray", "omarchy.audio"], openKey: "ALT + X", hoverPlugins: ["omarchy.audio"]}' <<<"$RECEIVER")"
many_doc=$(doc '{"bottomRadius": 12, "filletRadius": 12, "compactWidth": 220, "glowStyle": "bottom", "batteryGlow": true, "openKey": "ALT + Y", "settingsKey": "ALT + C",
  "hiddenPlugins": ["omarchy.spacer", "omarchy.tray", "omarchy.menu"], "hoverPlugins": ["omarchy.tray"], "autoHide": false, "notifications": false,
  "openWith": ["click"], "peekOnTrackChange": false, "batteryPeek": false, "stayOpen": true, "updateCheck": false}')
p=$(planf "$many_doc")
check "7d. a dozen changes: the three that change keys or plugins come first, marked danger" "true" \
  "$(jq '(.changes | length) as $n | ([.changes[:3][] | .danger] | all) and ([.changes[3:][] | .danger] | any | not) and $n > 10' <<<"$p")"
check "7e. the lines use the panel's words and no key names" "" "$(nc import "$sb/in.json" | grep -E 'bottomRadius|filletRadius|compactWidth|hiddenPlugins|autoHide|openKey|glowStyle|batteryGlow' | paste -sd'|')"
check "7f. Width  180 px → 220 px and Track and charger pop-ups  On → Off read in the panel's words" "Width  180 px → 220 px|Track and charger pop-ups  On → Off" \
  "$(nc import "$sb/in.json" | grep -E '^  (Width|Track)' | sed 's/^ *//' | paste -sd'|')"

# ---------------------------------------------------------------------------------
# 5h  The ceiling clamps what changes, not what is already there
# ---------------------------------------------------------------------------------
put "$(jq '.bar.notch.compactWidth = 2600' <<<"$RECEIVER")"
p=$(planf "$(doc '{"compactWidth": 2600}')")
check "5h. a width the receiver already has, over the ceiling, is left alone: your own export is nothing to change" "2600 0 0" \
  "$(jq -r '"\(.notch.compactWidth) \(.skipped | length) \(.changes | length)"' <<<"$p")"
p=$(planf "$(doc '{"compactWidth": 2700}')")
check "5i. …and a different one is capped, and said so" "2400 Width:capped" "$(jq -r '"\(.notch.compactWidth) \(.skipped[0].label):\(.skipped[0].reason)"' <<<"$p")"

# ---------------------------------------------------------------------------------
# What the read-only half did
# ---------------------------------------------------------------------------------
check "r. up to here nothing was applied: only the plugin list was asked, no shell call and no reload" "omarchy plugin list --json 0" \
  "$(calls | sort -u | paste -sd'|') $(calls | grep -c '^omarchy-shell')"

# ---------------------------------------------------------------------------------
# 8  Apply: a snapshot first, one write, checked; Undo
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}8  Apply, and Undo${RESET}"
canon() { jq -S -c . "$SHELL_SB" | sha256sum | cut -d' ' -f1; }
reloads() { calls | grep -c 'omarchy-shell shell reloadConfig'; }
reset_calls() { : >"$CALLS"; }
setup() { env "${env_common[@]}" "$SETUP" "$@"; }
snaps() { ls -d "$STATE_SB"/snapshots/[0-9]*-config-import* 2>/dev/null; }
status() { jq -r ".$1" "$sb/run/setup.json" 2>/dev/null; }
staged_left() { ls -A "$STATE_SB/staged" 2>/dev/null | grep -c . ; }
strays() { find "$CONFIG_SB/omarchy" -name 'shell.json.*' | wc -l; }

put "$SENDER"; code=$(nc export)
put "$RECEIVER"; before=$(canon); rm -rf "$STATE_SB/snapshots" "$STATE_SB/staged"; reset_calls
off=$(nc import "$code" 2>&1); rc_off=$?
check "8. without --yes and off a terminal: the preview, a hint, and nothing written" "0 true $before" \
  "$rc_off $([[ $off == *'Run again with --yes'* && $off == *changes* ]] && echo true || echo false) $(canon)"
reset_calls
out=$(nc import "$code" --yes 2>&1); rc=$?
snap=$(snaps | head -1)
check "8a. --yes applies: exit 0, phase done, the snapshot verified, one snapshot" "0 done verified 1" \
  "$rc $(status phase) $(jq -r .state "$snap/meta.json") $(snaps | wc -l)"
check "8b. the snapshot came first: titled, kind ipc, holding the pre-import canonical hash" "Imported notch settings ipc $before" \
  "$(jq -r '"\(.title) \(.kind) \(.files[0].canonical)"' "$snap/meta.json")"
check "8c. exactly one reloadConfig, and no notch set, moveBarWidget, putBarWidget, rescanPlugins or plugin enable/disable" "1 0" \
  "$(reloads) $(calls | grep -cE 'notch set|moveBarWidget|putBarWidget|rescanPlugins|plugin (enable|disable)')"
check "8d. the notch block is the file's, the layout is reordered only, the withheld key and the sentinel stay" "700 ALT + X false true" \
  "$(jq -r '.bar.notch | "\(.compactWidth) \(.openKey) \(.replaceMenu) \(.hostedMono)"' "$SHELL_SB")"
check "8e. the staged document is gone, and no temp file is left" "0 0" "$(staged_left) $(strays)"
ids_after=$(jq -c '[.bar.layout[][] | if type == "object" then .id else . end] | sort' "$SHELL_SB")
check "8f. no widget was added or removed" "$(jq -c '[.bar.layout[][] | if type == "object" then .id else . end] | sort' <<<"$RECEIVER")" "$ids_after"
check "8g. the same code again: Nothing to change, no second snapshot" "Nothing to change 0 1" "$(nc import "$code" --yes 2>&1) $? $(snaps | wc -l)"
reset_calls
setup restore "$(basename "$snap")" >/dev/null 2>&1; rc=$?
check "8h. Undo: exit 0, the canonical hash is the one from before, removed keys are back to absent" "0 $before restored" "$rc $(canon) $(jq -r .state "$snap/meta.json")"
check "8i. …through one reloadConfig, again through the same write" "1" "$(reloads)"
put "$SENDER"; code2=$(nc export); put "$RECEIVER"
nc import "$code2" --yes >/dev/null 2>&1
snap2=$(snaps | tail -1); jq '.bar.position = "bottom"' "$SHELL_SB" >"$sb/t" && cp "$sb/t" "$SHELL_SB"; edited=$(canon)
setup restore "$(basename "$snap2")" >/dev/null 2>&1; rc=$?
check "8j. after an unrelated edit Undo is a conflict, exit 3, and writes nothing" "3 $edited" "$rc $(canon)"
ids=$(setup detect --json --all 2>/dev/null | jq -r '"\(.points | length) \([.points[].id] | index("config-import"))"')
check "8k. detect still lists its 23 points and never config-import" "23 null" "$ids"

# ---------------------------------------------------------------------------------
# 9  Failure: the file is as it was, and the reloads are counted
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}9  Failure${RESET}"
# fails <label> <expected reloads> <command...>: runs it on a fresh receiver
fresh() { put "$RECEIVER"; before=$(canon); cp "$SHELL_SB" "$sb/stale.json"; rm -rf "$STATE_SB/snapshots" "$STATE_SB/staged"; reset_calls; }
fresh; NOTCH_SETUP_FAIL_AT=snapshot nc import "$code" --yes >/dev/null 2>&1; rc=$?
check "9. no snapshot: exit 1, the file as it was, no reload, nothing staged" "1 $before 0 0 0" "$rc $(canon) $(reloads) $(staged_left) $(strays)"
fresh; NOTCH_SETUP_FAIL_AT=verify nc import "$code" --yes >/dev/null 2>&1; rc=$?
check "9a. verification fails: exit 1, rolled back, the file as it was, a second reload for the rollback" "1 $before rolled-back 2 0 0" \
  "$rc $(canon) $(status phase) $(reloads) $(staged_left) $(strays)"
fresh; SB_STALE=1 nc import "$code" --yes >/dev/null 2>&1; rc=$?
check "9b. a shell that writes its stale file back after the reload: verify's five tries fail, rolled back" "1 $before rolled-back 2" \
  "$rc $(canon) $(status phase) $(reloads)"
fresh; staged=$(nc import "$code" --stage | jq -r .staged)
jq '.bar.notch.autoHide = true' "$SHELL_SB" >"$sb/t" && cp "$sb/t" "$SHELL_SB"; edited=$(canon); reset_calls
setup fix config-import --arg "$staged" >/dev/null 2>&1; rc=$?
check "9c. a slider moved while the preview was open: the plan has changed, nothing is applied, one reload (the rollback's)" "1 $edited 1 0" \
  "$rc $(canon) $(reloads) $(staged_left)"
fresh; staged=$(nc import "$code" --stage | jq -r .staged)
jq '.bar.notch.compactHeight = 50 | .bar.layout.left += ["omarchy.spacer"]' "$SHELL_SB" >"$sb/edit.json"; reset_calls
SB_EDIT="$sb/edit.json" setup fix config-import --arg "$staged" >/dev/null 2>&1; rc=$?
check "9d. the file changes between the plan and the write: the program refuses, exit 1, the file as it was" "1 $before 0" "$rc $(canon) $(staged_left)"
fresh; sleep 30 & held=$!; mkdir -p "$STATE_SB/lock"; echo "$held" >"$STATE_SB/lock/pid"
nc import "$code" --yes >/dev/null 2>&1; rc=$?
kill "$held" 2>/dev/null; rm -rf "$STATE_SB/lock"
check "9e. another job holds the lock: exit 5, nothing changed" "5 $before 0" "$rc $(canon) $(reloads)"
fresh; SB_LOCKED=0 nc import "$code" --yes >/dev/null 2>&1; rc=$?
check "9f. a locked session: exit 2, nothing changed" "2 $before 0" "$rc $(canon) $(reloads)"

# ---------------------------------------------------------------------------------
# 10  Nothing outside the staged folder, nothing from a hand-edited stage
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}10  Staging${RESET}"
fresh; staged=$(nc import "$code" --stage | jq -r .staged)
check "10. the staged folder is 700, the document 600, named by the plan's hash" "700 600 true" \
  "$(stat -c %a "$STATE_SB/staged") $(stat -c %a "$staged") $([[ $(basename "$staged" .json) == $(nc plan "$staged" | jq -r .hash) ]] && echo true || echo false)"
printf '%s\n' "$(doc '{"autoHide": true}')" >"$sb/outside.json"
setup fix config-import --arg "$sb/outside.json" >/dev/null 2>&1; rc1=$?
ln -s "$sb/outside.json" "$STATE_SB/staged/aaaaaaaa.json"
setup fix config-import --arg "$STATE_SB/staged/aaaaaaaa.json" >/dev/null 2>&1; rc2=$?
setup fix config-import --arg "$STATE_SB/staged/../snapshots" >/dev/null 2>&1; rc3=$?
rm -f "$STATE_SB/staged/aaaaaaaa.json"
check "10a. a path outside the staged folder, a symlink in it and a folder are refused: exit 2, file untouched, the outside file kept" "2 2 2 $before true" \
  "$rc1 $rc2 $rc3 $(canon) $([[ -f $sb/outside.json ]] && echo true || echo false)"
# A stage edited by hand, then named by the hash `plan` gives it: it is normalised again at apply.
jq '.settings.replaceMenu = true | .settings.bogus = 1 | .settings.compactWidth = 99999 | .settings.autoHide = "yes"' "$staged" >"$sb/hand.json"
hash=$(nc plan "$sb/hand.json" | jq -r .hash); cp "$sb/hand.json" "$STATE_SB/staged/$hash.json"; chmod 600 "$STATE_SB/staged/$hash.json"
setup fix config-import --arg "$STATE_SB/staged/$hash.json" >/dev/null 2>&1; rc=$?
check "10b. a hand-edited stage cannot widen the whitelist: no withheld key, no unknown key, the ceiling, no wrong type" "0 false null 2400 false" \
  "$rc $(jq -r '.bar.notch.replaceMenu' "$SHELL_SB") $(jq -r '.bar.notch.bogus' "$SHELL_SB") $(jq -r '.bar.notch.compactWidth' "$SHELL_SB") $(jq '.bar.notch.autoHide == "yes"' "$SHELL_SB")"
fresh; nc import "$code" --stage >/dev/null; touch -d '2 hours ago' "$STATE_SB/staged/"*.json
nc import "$code" --stage >/dev/null
check "10c. a staged document older than an hour is pruned by the next run" "1" "$(staged_left)"

# ---------------------------------------------------------------------------------
# 13  Lists with several ids, and nothing outside the notch's block moves
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}13  Lists, and the rest of shell.json${RESET}"
fresh
lists=$(doc '{"hostedPanels": ["omarchy.audio", "omarchy.clock", "kalinewb.face"], "disabledIntegrations": ["omarchy.tray", "omarchy.audio"],
  "hiddenPlugins": ["omarchy.spacer", "omarchy.tray"], "hoverPlugins": ["omarchy.audio", "omarchy.tray"], "bottomRadius": 12, "filletRadius": 12}')
keys=$(nc table | jq -c '.keys | keys')
rest() { jq -S -c --argjson k "$keys" 'del(.bar.layout) | .bar.notch |= with_entries(select(.key | IN($k[]) | not))' "$SHELL_SB"; }
rest_before=$(rest)
printf '%s\n' "$lists" >"$sb/lists.json"; nc import "$sb/lists.json" --yes >/dev/null 2>&1; rc=$?
check "13. three hosted panels, two off integrations, two hidden and two hover widgets: applied, verified" "0 done" "$rc $(status phase)"
check "13a. the file holds those exact arrays" '["omarchy.audio","omarchy.clock","kalinewb.face"] ["omarchy.tray","omarchy.audio"] ["omarchy.spacer","omarchy.tray"] ["omarchy.audio","omarchy.tray"]' \
  "$(jq -c '.bar.notch | "\(.hostedPanels) \(.disabledIntegrations) \(.hiddenPlugins) \(.hoverPlugins)"' -r "$SHELL_SB")"
check "13b. outside the 50 keys and the layout: shell.json is as it was (sentinels, withheld keys, plugins, bar.id included)" "$rest_before" "$(rest)"
setup restore "$(basename "$(snaps | tail -1)")" >/dev/null 2>&1; rc=$?
check "13c. Undo puts back the canonical hash" "0 $before" "$rc $(canon)"

# ---------------------------------------------------------------------------------
# 12  Static
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}12  Static${RESET}"
# The words are written in two halves so this file does not hold them either.
words=("su""do" "pk""exec" "system""ctl" "systemd""-run" "cu""rl" "wg""et" "git"" clone" "pac""man" "ev""al")
hits=""
for f in bin/notch-config bin/notch-lib.sh dev/config.sh; do
  for w in "${words[@]}"; do
    grep -qwE -- "$w" "$REPO/$f" && hits+="$f:$w "
  done
done
check "12. notch-config, notch-lib.sh and this file hold none of the words the scanner reads as a capability" "" "${hits% }"
bad_names=$(for f in bin/notch-config bin/notch-lib.sh dev/config.sh; do
  [[ $(basename "$f") =~ (^|[-_])(install|installer|setup|uninstall)([-_.]|$) ]] && echo "$f"; done | paste -sd' ')
check "12a. no basename matches the scanner's installer pattern" "" "$bad_names"
moved="split now_ms now_s stamp sha canonical_sha have runnable guard_triggered default_for paths_sandboxed commands_stubbed check_guard json_or shell_config commit_shell plugin_list layout_ids catalogue_ids"
still=""; absent=""
for fn in $moved; do
  grep -qE "^$fn\(\)" "$REPO/bin/notch-setup" && still+="$fn "
  grep -qE "^$fn\(\)" "$REPO/bin/notch-lib.sh" || absent+="$fn "
done
check "12b. notch-setup defines none of the functions that moved to notch-lib.sh" "" "${still% }"
check "12c. …and notch-lib.sh defines all of them" "" "${absent% }"
check "12d. notch-config defines none of them either (it sources them)" "" \
  "$(for fn in $moved; do grep -qE "^$fn\(\)" "$REPO/bin/notch-config" && echo "$fn"; done | paste -sd' ')"
check "12e. notch-lib.sh is sourced, not run: not executable" "644" "$(stat -c %a "$REPO/bin/notch-lib.sh")"

# ---------------------------------------------------------------------------------
# 14  The words
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}14  The words${RESET}"
check "14. every row in the table is a row of the panel, with the panel's own label" "" "$(python3 - "$REPO/NotchSettings.qml" "$table" <<'PY'
import json, re, sys
src, table = open(sys.argv[1]).read(), json.loads(sys.argv[2])
panel = dict(re.findall(r'rid: "(\w+)"; label: "([^"]*)"', src))
used = {s["row"] for s in table["keys"].values() if "row" in s} | set(table["withheld"].values())
bad = [f'{r["id"]}: {r["label"]!r} vs {panel.get(r["id"])!r}' for r in table["rows"] if r["id"] in used and panel.get(r["id"]) != r["label"]]
bad += [f'{r}: not a table row' for r in used if r not in [x["id"] for x in table["rows"]]]
print("; ".join(bad))
PY
)"
check "14a. the keys with no row are the ones settings-tips.js lists as rowless (17), nouns all different" "" "$(python3 - "$REPO/settings-tips.js" "$table" <<'PY'
import json, re, sys
src, table = open(sys.argv[1]).read(), json.loads(sys.argv[2])
norow = re.findall(r'"(\w+)"', re.search(r"var noRow = \[(.*?)\]", src, re.S).group(1))
nouns = {k: s["noun"] for k, s in table["keys"].items() if "noun" in s}
bad = sorted(set(norow) ^ set(nouns))
if len(set(nouns.values())) != len(nouns): bad.append("a noun twice")
if len(nouns) != 17: bad.append(f"{len(nouns)} nouns")
print(" ".join(bad))
PY
)"
check "14b. the row tips Share and Import: at most 60 characters, one sentence, no full stop, never their label" "" "$(python3 - "$REPO/settings-tips.js" "$table" <<'PY'
import json, re, sys
src, table = open(sys.argv[1]).read(), json.loads(sys.argv[2])
tips = dict(re.findall(r'^\s+(\w+):\s+"(.*)",?\s*$', re.search(r"var t = \{(.*?)\n\}", src, re.S).group(1), re.M))
labels = {"share": "Share settings", "importer": "Use someone's settings"}
bad = []
for i, label in labels.items():
    t = tips.get(i, "")
    if not t: bad.append(f"{i}: no tip"); continue
    if len(t) > 60: bad.append(f"{i}: {len(t)} characters")
    if "." in t: bad.append(f"{i}: a full stop")
    if label.lower() in t.lower(): bad.append(f"{i}: repeats its label")
print("; ".join(bad))
PY
)"
check "14c. every table row id has a tip in settings-tips.js (the rows it can show)" "" "$(python3 - "$REPO/settings-tips.js" "$table" <<'PY'
import json, re, sys
src, table = open(sys.argv[1]).read(), json.loads(sys.argv[2])
tips = set(re.findall(r'^\s+(\w+):\s+"', re.search(r"var t = \{(.*?)\n\}", src, re.S).group(1), re.M))
print(" ".join(sorted({s["row"] for s in table["keys"].values() if "row" in s} - tips)))
PY
)"

# ---------------------------------------------------------------------------------
# The guard, and the real session
# ---------------------------------------------------------------------------------
echo; echo "${BOLD}The guard and the real session${RESET}"
fake="$sb/fakehome"; mkdir -p "$fake/.config/omarchy"
printf '%s\n' "$SENDER" >"$fake/.config/omarchy/shell.json"
printf '%s\n' "$(mkcode "$(doc '{"autoHide": true}')")" >"$fake/code.txt"
fake_hash=$(find "$fake" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)
guard() { env HOME="$fake" XDG_CONFIG_HOME="$fake/.config" XDG_STATE_HOME="$fake/.local/state" XDG_RUNTIME_DIR="$fake/run" \
  NOTCH_HARNESS=1 NOTCH_SETUP_OMARCHY="$BIN/omarchy" NOTCH_SETUP_OMARCHY_SHELL="$BIN/omarchy-shell" "$SCRIPT" "$@"; }
rc1=0; rc2=0; rc3=0
guard export --file "$fake/exported.json" >/dev/null 2>&1 || rc1=$?
guard import "$fake/code.txt" --stage >/dev/null 2>&1 || rc2=$?
guard import "$fake/code.txt" --yes >/dev/null 2>&1 || rc3=$?
check "10d. a test notch (NOTCH_HARNESS) with the real paths: --file, --stage and --yes exit 2, and the fake home survives" "2 2 2 $fake_hash" \
  "$rc1 $rc2 $rc3 $(find "$fake" -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -d' ' -f1)"
check "10b. reading is not writing: export prints a code even then" "true" \
  "$(guard export 2>/dev/null | grep -qE '^notch1\.' && echo true || echo false)"
check "r1. the real shell.json is as it was, and nothing was staged for real" "$real_before $real_staged_before" \
  "$(sha256sum "$REAL_SHELL_JSON" 2>/dev/null | cut -d' ' -f1) $(ls -A "$REAL_STAGED" 2>/dev/null | wc -l)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
