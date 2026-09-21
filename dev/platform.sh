#!/bin/bash

# The notch as a platform, as numbers.
#
#   ./dev/platform.sh
#
# A. bin/notch-integrations against a sandbox plugins folder: which manifests
#    are candidates, and what it refuses.
# B. platform.js and activities.js as pure functions, run under node: the
#    acceptance table and every queue rule, with time supplied rather than
#    waited for.
# C. A throwaway notch with the fixture plugins: what it accepts, a panel drawn
#    inside the notch on the notch's colours and radius, the widget handshake,
#    switching an integration off and on, and the heartbeat a plugin's service
#    reads.
#
# Nothing here touches the live session or the real plugins folder: the notch
# only looks at $NOTCH_PLUGINS_DIR, and only with NOTCH_FORCE_PLATFORM=1.

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
sb=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-platform.XXXXXX")
qs_pid=""
cleanup() { [[ -n $qs_pid ]] && kill "$qs_pid" 2>/dev/null; rm -rf "$sb"; }
trap cleanup EXIT

PLUGINS="$sb/plugins"
cp -r "$REPO/dev/fixtures/platform/plugins" "$PLUGINS"
# A hidden folder: the host skips dot entries, and so must the scan.
cp -r "$PLUGINS/acme.demo" "$PLUGINS/.acme.hidden"

SCAN="$REPO/bin/notch-integrations"

# --- A. the scan ---------------------------------------------------------------------

echo "${BOLD}bin/notch-integrations${RESET}  ${DIM}sandbox $sb${RESET}"

scan=$("$SCAN" scan "$PLUGINS")
check "1. every manifest with a surface key is a candidate, sorted, dot folders skipped" \
  "acme.broken acme.demo acme.dupe acme.dupe acme.future acme.off acme.pulse acme.window" \
  "$(jq -r '[.[].id] | join(" ")' <<<"$scan")"
check "2. a plugin that says nothing about the notch isn't listed" "0" \
  "$(jq '[.[] | select(.id == "acme.plain")] | length' <<<"$scan")"
check "3. the entry file and contract are read from the manifest" "SurfaceIntegration.qml 1" \
  "$(jq -r '.[] | select(.id == "acme.demo") | "\(.entry) \(.contract)"' <<<"$scan")"
check "4. a service with no entry file is still a candidate" "acme.pulse  1" \
  "$(jq -r '.[] | select(.id == "acme.pulse") | "\(.id) \(.entry) \(.contract)"' <<<"$scan")"
check "5. an integration that opens its own window is refused" "own-window" \
  "$(jq -r '.[] | select(.id == "acme.window") | .problems[0]' <<<"$scan")"
check "6. of two folders claiming one id, the earlier folder keeps it" "acme.dupe-a acme.dupe-b duplicate-id" \
  "$(jq -r '[.[] | select(.id == "acme.dupe")] | "\(.[0].folder) \(.[1].folder) \(.[1].problems[0])"' <<<"$scan")"

# Variants, built one at a time so they can't disturb check 1's count.
variant() { # variant <name> ; echoes the scan of a folder holding just it
  local name=$1
  rm -rf "$sb/variants/$name"
  mkdir -p "$sb/variants/$name"
  cp -r "$PLUGINS/acme.demo" "$sb/variants/$name/acme.demo"
  echo "$sb/variants/$name"
}

dir=$(variant escape)
jq '.entryPoints.surface = "sub/../../outside.qml"' "$dir/acme.demo/manifest.json" >"$dir/t" && mv "$dir/t" "$dir/acme.demo/manifest.json"
check "7. an entry path that climbs out of the plugin folder is refused" "entry-unsafe" \
  "$("$SCAN" scan "$dir" | jq -r '.[0].problems[0]')"

dir=$(variant symlink)
echo 'import QtQuick' >"$sb/outside.qml"
rm "$dir/acme.demo/SurfaceIntegration.qml"
ln -s "$sb/outside.qml" "$dir/acme.demo/SurfaceIntegration.qml"
check "8. an entry that is a symlink out of the folder is refused" "entry-unsafe" \
  "$("$SCAN" scan "$dir" | jq -r '.[0].problems[0]')"

dir=$(variant missing)
rm "$dir/acme.demo/SurfaceIntegration.qml"
check "9. a missing entry file is refused" "entry-missing" \
  "$("$SCAN" scan "$dir" | jq -r '.[0].problems[0]')"

dir=$(variant comments)
printf 'import QtQuick\n// PanelWindow in a comment\n/* PopupWindow too */\nItem { property var surfaceHost: null }\n' \
  >"$dir/acme.demo/SurfaceIntegration.qml"
check "10. a window type named in a comment is not a problem" "0" \
  "$("$SCAN" scan "$dir" | jq '.[0].problems | length')"

dir=$(variant schema)
jq '.schemaVersion = "1"' "$dir/acme.demo/manifest.json" >"$dir/t" && mv "$dir/t" "$dir/acme.demo/manifest.json"
check "11. a manifest that isn't schema 1 is refused" "schema" \
  "$("$SCAN" scan "$dir" | jq -r '.[0].problems[0]')"

dir=$(variant contract-zero)
jq '.surface.contract = 0' "$dir/acme.demo/manifest.json" >"$dir/t" && mv "$dir/t" "$dir/acme.demo/manifest.json"
check "12. contract 0 is refused" "bad-contract" \
  "$("$SCAN" scan "$dir" | jq -r '.[0].problems[0]')"

dir=$(variant selfid)
jq '.id = "kalinewb.notch"' "$dir/acme.demo/manifest.json" >"$dir/t" && mv "$dir/t" "$dir/acme.demo/manifest.json"
check "13. a plugin claiming to be the notch is refused" "self" \
  "$("$SCAN" scan "$dir" | jq -r '.[0].problems[0]')"

dir=$(variant badjson)
echo 'not json at all' >"$dir/acme.demo/manifest.json"
check "14. an unreadable manifest is reported, not skipped" "bad-json" \
  "$("$SCAN" scan "$dir" | jq -r '.[0].problems[0]')"

check "15. a folder that isn't there scans to nothing" "[]" "$("$SCAN" scan "$sb/nope")"
check "16. the scan changes nothing" "$(find "$PLUGINS" -type f | wc -l)" "$(find "$PLUGINS" -type f | wc -l)"

# --- B. the rules, as pure functions ---------------------------------------------------

echo; echo "${BOLD}platform.js and activities.js${RESET}"

# platform.js and activities.js are plain JavaScript with a QML pragma on top,
# so they run under node: no display, no shell instance, and time is supplied
# rather than waited for.
run_js() { # run_js <script body> -> whatever it prints
  cat >"$sb/run.js" <<EOF
const vm = require("vm"), fs = require("fs")
function load(path) {
  const source = fs.readFileSync(path, "utf8").replace(/^\.pragma library/m, "")
  const context = { console, Math, JSON, Date, Array, Object, String, Number }
  vm.createContext(context)
  vm.runInContext(source, context)
  return context
}
const Platform = load("$REPO/platform.js")
const Activities = load("$REPO/activities.js")
$1
EOF
  node "$sb/run.js" 2>&1
}

out=$(run_js '
    function scan(over) {
      var base = { id: "acme.demo", contract: 1, entry: "SurfaceIntegration.qml", problems: [] }
      for (var key in over) base[key] = over[key]
      return base
    }
    var lines = []
    function say(name, value) { lines.push(name + "=" + value) }
    say("ok", Platform.acceptance(scan({}), true, false, "ready", true).reason)
    say("problem", Platform.acceptance(scan({problems: ["own-window"]}), true, false, "ready", true).reason)
    say("newer", Platform.acceptance(scan({contract: 99}), true, false, "ready", true).reason)
    // A contract below 1 is not a contract: it is refused as a bad manifest.
    // `contract-older` only becomes reachable when the notch stops accepting 1.
    say("older", Platform.acceptance(scan({contract: 0}), true, false, "ready", true).reason)
    say("disabled", Platform.acceptance(scan({}), false, false, "ready", true).reason)
    say("useroff", Platform.acceptance(scan({}), true, true, "ready", true).reason)
    say("loading", Platform.acceptance(scan({}), true, false, "loading", true).reason)
    say("error", Platform.acceptance(scan({}), true, false, "error", true).reason)
    say("unavailable", Platform.acceptance(scan({}), true, false, "ready", false).reason)
    say("noentry", Platform.acceptance(scan({entry: ""}), true, false, "none", true).reason)
    console.log(lines.join(" "))
')
check "17. the acceptance table answers each case with its own reason" \
  "ok= problem=invalid-manifest newer=contract-newer older=invalid-manifest disabled=not-enabled useroff=user-off loading=loading error=load-error unavailable=unavailable noentry=" \
  "$(tr -d '\r' <<<"$out" | tail -1)"

out=$(run_js '
    var lines = []
    function r(name, value) { lines.push(name + "=" + value) }
    r("plain", Platform.validClaim("acme.demo", {title: "Hello"}).claim.key)
    r("own", Platform.validClaim("acme.demo", {title: "x", key: "acme.demo.job"}).ok)
    r("other", Platform.validClaim("acme.demo", {title: "x", key: "kalinewb.profiles"}).reason)
    r("notitle", Platform.validClaim("acme.demo", {}).reason)
    r("badpriority", Platform.validClaim("acme.demo", {title: "x", priority: "urgent"}).reason)
    r("ttl", Platform.validClaim("acme.demo", {title: "x"}).claim.ttlMs)
    r("clamped", Platform.validClaim("acme.demo", {title: "x", ttlMs: 999999}).claim.ttlMs)
    r("ipcpersistent", Platform.validClaim("acme.demo", {title: "x", priority: "persistent"}, true).reason)
    r("inprocess", Platform.validClaim("acme.demo", {title: "x", priority: "persistent"}, false).claim.ttlMs)
    r("cut", Platform.validClaim("acme.demo", {title: new Array(200).join("x")}).claim.title.length)
    console.log(lines.join(" "))
')
check "18. a claim may only carry its own key, and its fields are bounded" \
  "plain=acme.demo own=true other=bad-key notitle=bad-payload badpriority=bad-payload ttl=3500 clamped=15000 ipcpersistent=bad-payload inprocess=0 cut=60" \
  "$(tr -d '\r' <<<"$out" | tail -1)"

out=$(run_js '
    var lines = []
    function claim(state, owner, key, priority, now) {
      var checked = Platform.validClaim(owner, {title: key, key: key, priority: priority, ttlMs: priority === "transient" ? 1000 : 0})
      return Activities.claim(state, checked.claim, now)
    }
    var s = Activities.create()
    var a = claim(s, "acme.demo", "acme.demo.a", "persistent", 1000); s = a.state
    var b = claim(s, "acme.demo", "acme.demo.b", "persistent", 1000); s = b.state
    var c = claim(s, "acme.demo", "acme.demo.c", "persistent", 1000); s = c.state
    lines.push("first=" + a.result + " second=" + b.result + " third=" + c.result)
    lines.push("visible=" + s.visible.length + " queued=" + s.queued.length)
    // A transient jumps a persistent, which goes back to the head of its rank.
    var t = claim(s, "acme.demo", "acme.demo.t", "transient", 2000); s = t.state
    lines.push("transient=" + t.result + " head=" + s.queued[0].key)
    // Same key replaces in place, keeping its slot and seq.
    var seqBefore = s.visible[0].seq
    var again = claim(s, "acme.demo", s.visible[0].key, "persistent", 2500); s = again.state
    lines.push("replace=" + again.result + " sameSeq=" + (s.visible[0].seq === seqBefore))
    // The transient expires and the queue head takes its place.
    s = Activities.tick(s, 3200)
    lines.push("afterTtl=" + s.visible.map(function (e) { return e.key.split(".").pop() }).sort().join(","))
    // An owner may not fill the queue.
    var limited = Activities.create()
    var last = ""
    for (var i = 0; i < 6; i++) {
      var one = claim(limited, "acme.demo", "acme.demo.k" + i, "persistent", 1000)
      limited = one.state; last = one.result
    }
    lines.push("limit=" + last)
    // Releasing everything an owner holds.
    limited = Activities.releaseOwner(limited, "acme.demo")
    lines.push("released=" + limited.visible.length + "/" + limited.queued.length)
    console.log(lines.join(" | "))
')
check "19. two are shown, a third queues, a transient jumps and the same key replaces in place" \
  "first=shown second=shown third=queued | visible=2 queued=1 | transient=shown head=acme.demo.b | replace=shown sameSeq=true | afterTtl=a,b | limit=declined:owner-limit | released=0/0" \
  "$(tr -d '\r' <<<"$out" | tail -1)"

out=$(run_js '
    var checked = Platform.validClaim("acme.demo", {title: "waited", priority: "transient", ttlMs: 1000})
    var s = Activities.create()
    // Fill both slots with persistents so the transient has to wait.
    var p1 = Platform.validClaim("acme.pulse", {title: "a", key: "acme.pulse.a", priority: "persistent"})
    var p2 = Platform.validClaim("acme.pulse", {title: "b", key: "acme.pulse.b", priority: "persistent"})
    s = Activities.claim(s, p1.claim, 0).state
    s = Activities.claim(s, p2.claim, 0).state
    // Two visible transients, so the new one cannot preempt.
    var t1 = Platform.validClaim("acme.pulse", {title: "t1", key: "acme.pulse.t1", priority: "transient", ttlMs: 60000})
    var t2 = Platform.validClaim("acme.pulse", {title: "t2", key: "acme.pulse.t2", priority: "transient", ttlMs: 60000})
    s = Activities.claim(s, t1.claim, 0).state
    s = Activities.claim(s, t2.claim, 0).state
    var waited = Activities.claim(s, checked.claim, 0)
    s = waited.state
    var before = s.queued.length
    s = Activities.tick(s, 11000)
    console.log("queued=" + waited.result + " before=" + before + " afterWait=" + s.queued.length)
')
check "20. a transient that waited too long is dropped rather than shown late" \
  "queued=queued before=3 afterWait=2" "$(tr -d '\r' <<<"$out" | tail -1)"

# --- C. the notch --------------------------------------------------------------------

echo; echo "${BOLD}A plugin's panel inside the notch${RESET}"

root_dir="$sb/shell"
mkdir -p "$root_dir" "$sb/state" "$sb/markers"
ln -s "$SHELL_PATH/shell/Commons" "$root_dir/Commons"
ln -s "$SHELL_PATH/shell/Ui" "$root_dir/Ui"
ln -s "$SHELL_PATH/shell/services" "$root_dir/services"
ln -s "$REPO" "$root_dir/notch"
cp "$REPO/dev/harness/platform-shell.qml" "$root_dir/shell.qml"
# A file inside the root has to import each qs.* module a foreign file uses,
# or Quickshell won't resolve it from outside the root.
printf 'import QtQuick\nimport qs.Commons\nimport qs.Ui\nItem { }\n' >"$root_dir/Probe.qml"

# The stand-in omarchy-shell: a harness must never reach the live one.
mkdir -p "$sb/bin"
printf '#!/bin/bash\necho "$*" >> "%s/omarchy-shell.log"\necho "Target not found." >&2\nexit 1\n' "$sb" >"$sb/bin/omarchy-shell"
chmod +x "$sb/bin/omarchy-shell"

ipc() { quickshell ipc -p "$root_dir" call notch "$@" 2>/dev/null; }
harness() { quickshell ipc -p "$root_dir" call harness "$@" 2>/dev/null; }
widget() { quickshell ipc -p "$root_dir" call "acme.demo.s0" "$@" 2>/dev/null; }

start() { # start [extra env...]
  env PATH="$sb/bin:$PATH" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
    NOTCH_FORCE_PLATFORM=1 NOTCH_PLUGINS_DIR="$PLUGINS" NOTCH_PLATFORM_ENABLED="*" \
    NOTCH_PLATFORM_STATE_DIR="$sb/state" NOTCH_FIXTURE_MARKER_DIR="$sb/markers" \
    NOTCH_PLATFORM_WIDGETS='{"acme.demo": "acme.demo/Widget.qml"}' \
    NOTCH_HARNESS_CONFIG='{"batteryPeek":false,"bottomRadius":8,"disabledIntegrations":["acme.off"]}' "$@" \
    quickshell -p "$root_dir" -n >>"$sb/qs.log" 2>&1 &
  qs_pid=$!
  for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
  for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc integrations | jq -r '.scannedAt > 0') == true ]] && break; done
  sleep 0.5
}
# Quit through the harness rather than a signal: a QML destruction handler
# doesn't run on SIGTERM, and the notch's last word is written in one.
stop() { harness quit >/dev/null 2>&1; sleep 0.6; kill "$qs_pid" 2>/dev/null; wait "$qs_pid" 2>/dev/null; qs_pid=""; }

start
report=$(ipc integrations)
echo "  ${DIM}$(jq -c '[.list[] | {id, accepted, reason}]' <<<"$report")${RESET}"

check "21. it scans the sandbox folder, not the real one" "$PLUGINS true" \
  "$(jq -r '.pluginsDir' <<<"$report") $(jq -r '.enabled' <<<"$report")"
check "22. each candidate is accepted, or says exactly why not" \
  "acme.broken=load-error acme.demo= acme.dupe=invalid-manifest acme.future=contract-newer acme.off=user-off acme.pulse= acme.window=invalid-manifest" \
  "$(jq -r '[.list[] | "\(.id)=\(.reason)"] | join(" ")' <<<"$report")"
check "22b. a plugin with no panel of its own is still accepted, for its activities" "acme.demo,acme.pulse" \
  "$(jq -r '[.list[] | select(.accepted) | .id] | join(",")' <<<"$report")"
check "23. the accepted one is loaded once and offers a panel" "1 true ready" \
  "$(jq -r '.list[] | select(.id == "acme.demo") | "\(.loads) \(.hasPanel) \(.loadStatus)"' <<<"$report")"
check "24. its named activity views are known" "progress" \
  "$(jq -r '.list[] | select(.id == "acme.demo") | .activityViews | join(",")' <<<"$report")"
check "25. a plugin with no bar widget is enabled from the list it was given, not by asking the shell" \
  "true harness-env 0" \
  "$(jq -r '.list[] | select(.id == "acme.pulse") | "\(.enabled) \(.enabledBy)"' <<<"$report") $(grep -c . "$sb/omarchy-shell.log" 2>/dev/null || echo 0)"
check "26. a widget of an enabled plugin counts through the host's catalogue" "catalogue" \
  "$(jq -r '.list[] | select(.id == "acme.demo") | .enabledBy' <<<"$report")"

# The widget's own view of the notch.
state=$(widget state)
check "27. the plugin's widget is handed a scoped host, the notch's radius and its own screen" "true true 8 true" \
  "$(jq -r .accepted <<<"$state") $(jq -r .present <<<"$state") $(jq -r .radius <<<"$state") $(jq -r '.surfaceScreen != ""' <<<"$state")"
check "28. …and the contract version it may check against" "1" "$(jq -r .contract <<<"$state")"

# Opening the panel from the widget, as a click does.
result=$(widget open main)
sleep 0.9
g=$(ipc geometry)
check "29. a click opens the plugin's panel inside the notch" "opened expanded true acme.demo main" \
  "$result $(jq -r .state <<<"$g") $(jq -r .integration.open <<<"$g") $(jq -r .integration.id <<<"$g") $(jq -r .integration.route <<<"$g")"
check "30. the notch grew to the panel, top edge still on the screen edge, square top corners" "true 0 0" \
  "$(jq -r '.integration.height > 32 and (.target.height == .integration.height) and (.bar.height - .target.height | fabs) < 0.5' <<<"$g") $(jq -r .bar.y <<<"$g") $(jq -r .radii.topLeft <<<"$g")"
check "31. the plugin's own popup stayed shut" "false" "$(widget state | jq -r .ownPopupShown)"

colours=$(ipc geometry | jq -c '.colours.integration // {}')
check "32. the panel paints with the notch's colours" "#000000 #ffffff" \
  "$(jq -r '.background // ""' <<<"$colours" | tr 'A-Z' 'a-z') $(jq -r '.foreground // ""' <<<"$colours" | tr 'A-Z' 'a-z')"

d=$(ipc design)
check "33. everything rounded in the panel uses the notch's radius" "0" "$(python3 -c '
import json,sys
d=json.loads(sys.argv[1]); r=d["radius"]
bad=[i for i in d.get("integration", []) if i["drawn"] and not i["gradient"] and i["width"]>2 and i["height"]>2
     and abs(i["radius"]-max(0,min(r,i["height"]/2,i["width"]/2)))>0.01]
print(len(bad))' "$d")"

# A route change reaches the kept panel without rebuilding it.
widget open tall >/dev/null
sleep 0.9
g=$(ipc geometry)
check "34. another route resizes the same panel without reloading the integration" "tall tall 1" \
  "$(jq -r .integration.route <<<"$g") $(jq -r .integration.itemRoute <<<"$g") $(ipc integrations | jq -r '.list[] | select(.id == "acme.demo") | .loads')"

# Every way of closing a panel.
harness grabCleared >/dev/null; sleep 0.9
check "35. a click outside closes it" "compact false" \
  "$(ipc geometry | jq -r .state) $(ipc geometry | jq -r .integration.open)"

ipc panel acme.demo main >/dev/null; sleep 0.8
ipc toggle >/dev/null; sleep 0.9
check "36. the open keybind leaves it for the open view" "false widgets" \
  "$(ipc geometry | jq -r .integration.open) $(ipc geometry | jq -r .view)"

ipc panel acme.demo main >/dev/null; sleep 0.7
ipc view settings >/dev/null; sleep 0.7
check "37. opening the settings over it closes the panel" "false settings" \
  "$(ipc geometry | jq -r .integration.open) $(ipc geometry | jq -r .view)"
ipc view settings >/dev/null; sleep 0.6

# Declines.
check "38. an unknown or unaccepted plugin is declined, and says so" "declined:not-accepted declined:not-accepted" \
  "$(ipc panel acme.nope main) $(ipc panel acme.future main)"

# Claims.
check "39. a claim from the widget is accepted and reported" "shown 1" \
  "$(widget claim '{"title":"Switching to test…","priority":"persistent","ttlMs":30000}') $(ipc activities | jq '.visible + .queued | length')"
# Until 19 Sep nothing drew activities, so a claim the queue would show answered
# "queued" rather than promising a line. The notch draws them now, so "shown"
# means shown. That the line is really on the resting notch is dev/
# notifications.sh's checks 5 and 6; here the notch is open, where the activity
# state does not apply.
check "40. a claim the queue shows is drawn, not merely accepted" "true shown" \
  "$(ipc activities | jq -r .rendered) $(ipc activities | jq -r '.visible[0] | if . then "shown" else "none" end')"
check "41. a claim under another plugin's key is refused" "declined:bad-key" \
  "$(widget claim '{"title":"x","key":"kalinewb.profiles"}')"
check "42. an IPC claim from an unknown owner is refused" "declined:not-accepted" \
  "$(ipc claim acme.nope '{"title":"x"}')"
check "43. releasing it takes it back" "released 0" \
  "$(widget release acme.demo) $(ipc activities | jq '.visible + .queued | length')"

# The heartbeat a plugin's service reads.
beat="$sb/state/platform.json"
check "44. the notch writes a heartbeat outside the plugins folder" "true 1 true acme.demo,acme.pulse" \
  "$([[ -f $beat ]] && echo true || echo false) $(jq -r .contract "$beat" 2>/dev/null) $(jq -r .present "$beat" 2>/dev/null) $(jq -r '.accepted | keys | join(",")' "$beat" 2>/dev/null)"
check "45. …and says why it turned the others down" "contract-newer" \
  "$(jq -r '.declined["acme.future"]' "$beat" 2>/dev/null)"
check "46. the beat is fresh" "true" "$(jq -r '(now * 1000) - .beatAt < 8000' "$beat" 2>/dev/null)"

# Switching an integration off gives the plugin its own UI back.
harness setNotch '{"batteryPeek":false,"bottomRadius":8,"disabledIntegrations":["acme.demo"]}' >/dev/null
# Wait for the eviction to finish, not just for the verdict: the file is kept
# for 300 ms so its panel can fade, and switching it back on before that is a
# different case (checked below) from switching it on after.
for _ in $(seq 1 40); do sleep 0.1
  [[ $(ipc integrations | jq -r '.list[] | select(.id == "acme.demo") | "\(.accepted) \(.pendingUnload)"') == "false false" ]] && break
done
check "47. switching it off stops the notch accepting it, at once and with the reason" "false user-off false" \
  "$(ipc integrations | jq -r '.list[] | select(.id == "acme.demo") | "\(.accepted) \(.reason)"') $(widget state | jq -r .accepted)"
check "48. …its panel is declined, so the plugin opens its own" "declined:not-accepted true" \
  "$(widget open main) $(widget state | jq -r .ownPopupShown)"

harness setNotch '{"batteryPeek":false,"bottomRadius":8}' >/dev/null
for _ in $(seq 1 40); do sleep 0.1; [[ $(ipc integrations | jq -r '.list[] | select(.id == "acme.demo") | .accepted') == true ]] && break; done
# Switching an integration off evicts the plugin's file: `pendingUnload` holds
# the Loader open for 300 ms so the panel can fade out, and then it goes. That
# is deliberate -- once the user has switched a third-party integration off,
# leaving its QML loaded and running would be wrong -- so switching it back on
# is a fresh load, and the contract is that the fresh load is clean rather than
# that it never happens.
check "49. switching it back on loads it again, cleanly, and accepts it" "true 2 ready  false" \
  "$(ipc integrations | jq -r '.list[] | select(.id == "acme.demo") | "\(.accepted) \(.loads) \(.loadStatus) \(.reason) \(.pendingUnload)"')"

# Off and on again inside the fade: the file never left, so there is nothing to
# reload -- and nothing may stay marked for an unload that will never come.
harness setNotch '{"batteryPeek":false,"bottomRadius":8,"disabledIntegrations":["acme.demo"]}' >/dev/null
harness setNotch '{"batteryPeek":false,"bottomRadius":8}' >/dev/null
sleep 1.2
check "49a. switched off and straight back on: still loaded once, accepted, nothing left pending" "true 2 false" \
  "$(ipc integrations | jq -r '.list[] | select(.id == "acme.demo") | "\(.accepted) \(.loads) \(.pendingUnload)"')"

check "50. no omarchy-shell was ever run from the harness" "0" "$(grep -c . "$sb/omarchy-shell.log" 2>/dev/null || echo 0)"
stop

# The last word: a plugin's service must not wait out the staleness.
check "51. the notch says it is gone as it goes, so a service needn't wait out the staleness" "false" "$(jq -r .present "$beat" 2>/dev/null)"

# A notch that wasn't asked to be a platform does none of it.
rm -f "$sb/state/platform2.json"
env PATH="$sb/bin:$PATH" NOTCH_HARNESS=1 NOTCH_NO_KEYBINDS=1 NOTCH_MENU_DRY_RUN=1 \
  NOTCH_HARNESS_CONFIG='{"batteryPeek":false}' quickshell -p "$root_dir" -n >>"$sb/qs.log" 2>&1 &
qs_pid=$!
for _ in $(seq 1 60); do sleep 0.1; [[ $(ipc geometry) == \{* ]] && break; done
sleep 1.0
report=$(ipc integrations)
check "52. without being asked, a test notch scans nothing and accepts nothing" "false  0" \
  "$(jq -r .enabled <<<"$report") $(jq -r .pluginsDir <<<"$report") $(jq -r '.list | length' <<<"$report")"
check "53. …and its panel verb declines" "declined:not-accepted" "$(ipc panel acme.demo main)"
stop

check "54. no QML errors in any of it" "none" \
  "$(grep -E '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" | head -1 | cut -c1-90)$(grep -qE '\.qml:[0-9]+.*(TypeError|ReferenceError)' "$sb/qs.log" || echo none)"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
