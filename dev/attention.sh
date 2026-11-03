#!/bin/bash

# The admission rule for the Needs attention page, as a check.
#
#   ./dev/attention.sh
#
# docs/Needs-attention.md lists seven conditions for a point to be on the page.
# The ones a machine can hold are held here, against the source of
# bin/notch-setup: every point has a stated audience (page, auto or dev); every
# state a person can see on the page (page points at fix, action or warn) has a
# plain title and one short line (no id, file name, path, command, `file(s)` or
# jargon), and a button that names what it does; a migration carries a removal
# date; every automatic repair says what it did in plain words. Then, with no
# display: the notifications helper is parked when another bar takes over, and
# only then. Needs python3, jq; touches nothing outside a temporary folder.

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

echo "${BOLD}The admission rule${RESET}  ${DIM}bin/notch-setup, read as source${RESET}"
report=$(python3 - "$REPO/bin/notch-setup" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
out = {}

order = re.search(r"POINT_ORDER=\((.*?)\)", src, re.S).group(1).split()
adm = re.search(r"admission_of\(\) \{(.*?)\n\}", src, re.S).group(1)
audience = {}
for ids, who in re.findall(r"^\s*([a-z|-]+)\) echo (page|auto)", adm, re.M):
    for i in ids.split("|"): audience[i] = who
for i in order: audience.setdefault(i, "dev")
out["unclassified"] = [i for i in order if i not in re.sub(r"\s", " ", adm) and audience[i] == "dev" and False]
out["audiences"] = {w: sum(1 for i in order if audience[i] == w) for w in ("page", "auto", "dev")}

# every point call, as one statement (continuation lines end with a backslash)
lines = src.split("\n")
calls, i = [], 0
while i < len(lines):
    m = re.match(r'\s*(?:\S.*?[;)]\s+)?point\s+("?\$?[\w-]+"?)\s+(fix|action|warn|info|ok|unknown)\s', lines[i])
    if m and not lines[i].lstrip().startswith("#") and "point() {" not in lines[i]:
        stmt = lines[i]
        while stmt.rstrip().endswith("\\") and i + 1 < len(lines):
            i += 1; stmt += "\n" + lines[i]
        calls.append((m.group(1).strip('"'), m.group(2), stmt))
    i += 1
out["calls"] = len(calls)

plugin_ids = {"plugin-face", "plugin-profiles"}
BAD = [r"\b[a-z0-9]+\.[a-z0-9-]+\.[a-z0-9-]+\b", r"file\(s\)", r"[/~]\S", r"`", r"\$\(", r"\.lua\b", r"shell\.json", r"hyprctl",
       r"\bomarchy[-.]", r"\b(companion|upstream|layer|snapshot|plugin id|toggle)\b", r"\.bak\b"]
bad, nobutton, long_, undated = [], [], [], []
shown = 0
for pid, sev, stmt in calls:
    pid_list = plugin_ids if pid == "$pid" else {pid}
    if sev not in ("fix", "action", "warn"): continue
    if not any(audience.get(p) == "page" for p in pid_list): continue
    shown += 1
    strs = re.findall(r'"((?:[^"\\]|\\.)*)"', stmt.split("\\\n", 0)[0] if False else stmt)
    # title and summary are the first two double-quoted strings after the severity
    head = stmt[stmt.index(sev) + len(sev):]
    strs = re.findall(r'"((?:[^"\\]|\\.)*)"', head)
    title, summary = (strs + ["", ""])[:2]
    plain = lambda t: re.sub(r"\\\"", '"', re.sub(r"\$\{?\w+(:-[^}]*)?\}?", "X", t))
    for label, text in (("title", plain(title)), ("summary", plain(summary))):
        for pat in BAD:
            if re.search(pat, text): bad.append(f"{pid} {label} '{text}' ~ {pat}")
    if len(plain(title)) > 48: long_.append(f"{pid} title {len(plain(title))}")
    if len(plain(summary)) > 100: long_.append(f"{pid} summary {len(plain(summary))}")
    if '"label"' not in stmt and '--arg label' not in stmt and "fixspec" not in stmt: nobutton.append(f"{pid}/{sev}")
    # a fix button names what it does
    for lab in re.findall(r'fixspec \w+ "([^"]*)"', stmt) + re.findall(r'\{"label": "([^"]*)"', stmt) + re.findall(r'--arg label "([^"]*)"', stmt):
        if lab.strip().lower() in ("fix", "ok", "yes", ""): bad.append(f"{pid} button '{lab}' does not name what it does")
out["shown"] = shown
out["bad"], out["nobutton"], out["long"] = bad, nobutton, long_

rb = re.search(r"removeby_of\(\) \{(.*?)\n\}", src, re.S).group(1)
dated = re.findall(r"^\s*([a-z-]+)\) echo (\d{4}-\d{2}-\d{2})", rb, re.M)
out["dated"] = sorted(d[0] for d in dated)
auto = re.search(r"AUTO_POINTS=\((.*?)\)", src).group(1).split()
out["auto_vs_audience"] = sorted(auto) == sorted(i for i in order if audience[i] == "auto")
pt = re.search(r"plain_title\(\) \{(.*?)\n\}", src, re.S).group(1)
# stale-notch-binds changes no file, so it has no snapshot to title
out["untitled_auto"] = [i for i in auto if i != "stale-notch-binds" and f"{i})" not in pt]
print(__import__("json").dumps(out))
PY
)
j() { jq -r "$1" <<<"$report"; }
check "every point has an audience, and the page has 9, the notch's own repairs 5, the terminal 9" "9 5 9" \
  "$(j '"\(.audiences.page) \(.audiences.auto) \(.audiences.dev)"')"
check "the source is read: $(j .calls) point states found, $(j .shown) of them can be seen on the page" "true" "$(j '.calls > 40 and .shown >= 9')"
check "no state on the page names an id, file, path, command or jargon" "" "$(j '.bad | join("; ")')"
check "…and each is a title of 48 characters and a line of 100 at most" "" "$(j '.long | join("; ")')"
check "…and each has a button that names what it does" "" "$(j '.nobutton | join(" ")')"
check "a migration or transitional row carries a removal date" "face-renamed oled-corners-still" "$(j '.dated | join(" ")')"
check "the automatic repairs are exactly those the audience table says" "true" "$(j .auto_vs_audience)"
check "…and each that changes a file says what it did in plain words (Earlier fixes)" "" "$(j '.untitled_auto | join(" ")')"

# The page itself never shows a state it cannot stand behind: unknown and info stay in the terminal.
check "the page's filter keeps only fix, action and warn" "1" \
  "$(grep -c 'def needs: .severity == "fix" or .severity == "action" or .severity == "warn"' "$REPO/bin/notch-setup")"
check "NotchSetup.qml lists only fix, action and warn" "1" "$(grep -c '\["fix", "action", "warn"\]' "$REPO/NotchSetup.qml")"

# --- parking the notifications helper ------------------------------------------------------
echo; echo "${BOLD}Leaving the notch for another bar${RESET}  ${DIM}notch-companion park, in a sandbox${RESET}"
work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-attention.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/plugins" "$work/bin"
printf '#!/bin/bash\necho "$*" >>"%s/calls"\n' "$work" >"$work/bin/disable"
chmod +x "$work/bin/disable"
list() { echo "[{\"id\": \"kalinewb.notch-notifications\", \"enabled\": $1}]"; }
park() { # park <bar id> <enabled>
  echo "{\"bar\": {\"id\": \"$1\"}}" >"$work/shell.json"
  list "$2" >"$work/list.json"
  : >"$work/calls"
  env NOTCH_COMPANION_ID=kalinewb.notch-notifications NOTCH_COMPANION_SOURCE_ID=omarchy.notifications NOTCH_COMPANION_LABEL=notifications \
    NOTCH_COMPANION_DIR="$work/plugins" NOTCH_COMPANION_ENABLE="$work/bin/disable" NOTCH_COMPANION_REMOVE="$work/bin/disable" \
    NOTCH_COMPANION_DISABLE="$work/bin/disable" NOTCH_COMPANION_SHELL_JSON="$work/shell.json" NOTCH_COMPANION_LIST="cat $work/list.json" \
    "$REPO/bin/notch-companion" park >/dev/null 2>&1
  cat "$work/calls"
}
check "another bar took over and the helper is on: it is switched off" "kalinewb.notch-notifications" "$(park omarchy.bar true)"
check "the notch is still the bar (a restart, an update): nothing is touched" "" "$(park kalinewb.notch true)"
check "another bar, helper already off: nothing to do" "" "$(park omarchy.bar false)"
rc=0; env NOTCH_COMPANION_DIR="$work/plugins" NOTCH_COMPANION_ENABLE=x NOTCH_COMPANION_REMOVE=x "$REPO/bin/notch-companion" park >/dev/null 2>&1 || rc=$?
check "a sandbox without a stand-in for disable refuses, so a test never reaches the live shell" "2" "$rc"

echo
if ((failures == 0)); then echo "${GREEN}All $checks checks pass.${RESET}"
else echo "${RED}$failures of $checks checks failed.${RESET}"; fi
exit $((failures > 0))
