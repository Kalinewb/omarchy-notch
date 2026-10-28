#!/bin/bash

# The quiet UI, as numbers (plan-wizard.md 2): the words on screen, counted.
#
#   ./dev/strings.sh
#
# dev/strings.py reads the QML and JS the notch draws, and bin/notch-setup's
# point titles and finish messages. A lint, not proof: it cannot see a sentence
# built somewhere it does not look. Nothing runs; no notch is started.
#
#   1   no string over the rule: one sentence of at most 7 words (a tip: 60
#       characters, no full stop); the allowlist applied; no stale allowlist entry
#   2   bash titles and finish messages: none over 7 words, one sentence or 44
#       characters
#   3   the ratchets hold: wrapMode and Style.font.caption Texts only fall
#   4   the checker can fail: an 8-word string, two sentences, a sentence split
#       across two `+`-joined literals, a 45-character title and a stale
#       allowlist entry are flagged; a 7-word string and an allowlisted one pass
#   5   none of the strings the diet removed is back in dev/, bin/ or README.md
#   6   wiki/*.md: the 13 pages exist and nothing else is there, Home.md lists
#       every page, every relative link and anchor resolves, no image and no
#       curl piped to a shell, the README links Home; the check can fail

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}

PY="$REPO/dev/strings.py"
ALLOW="$REPO/dev/strings-allow.txt"
BASE="$REPO/dev/baselines/strings.json"
work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-strings.XXXXXX")
trap 'rm -rf "$work"' EXIT

echo "${BOLD}The quiet UI${RESET}  ${DIM}plugin: $REPO${RESET}"

report=$(python3 "$PY" --allow "$ALLOW" --removed "$REPO/dev/baselines/strings-removed.txt")
if ! jq -e . >/dev/null 2>&1 <<<"$report"; then echo "  ${RED}FAIL${RESET}  dev/strings.py printed no JSON"; exit 1; fi

# ---------------------------------------------------------------------------
# 1  The rule
# ---------------------------------------------------------------------------
echo; echo "${BOLD}1  The rule${RESET}"
check "$(jq -r '.scanned | length' <<<"$report") files scanned, none of the 10 always-present ones missing" "10" \
  "$(jq -r '[.scanned[] | select(IN("Bar.qml","NotchSettings.qml","NotchSetup.qml","SetupService.qml","NotchUpdate.qml","plugins/NotchPlugins.qml","plugins/NotchPluginsNotice.qml","plugins/PluginsModel.js","platform.js","keys.js"))] | length' <<<"$report")"
check "no string over the rule (allowlist applied)" "" \
  "$(jq -r '.offenders[] | "\(.file):\(.line) \(.why | join(", ")): \(.text[0:60])"' <<<"$report" | head -5 | paste -sd';')"
check "no allowlist entry for a literal that is gone" "" "$(jq -r '.stale | map(split("\t")[1]) | join("; ")' <<<"$report")"

# ---------------------------------------------------------------------------
# 2  Bash titles and finish messages
# ---------------------------------------------------------------------------
echo; echo "${BOLD}2  bin/notch-setup${RESET}"
check "point titles and finish messages are read (more than 60)" "true" "$(jq -r '.titles > 60' <<<"$report")"
check "none is over 7 words, one sentence or 44 characters" "" \
  "$(jq -r '.bash[] | "\(.kind) \(.line) \(.why | join(", ")): \(.text[0:50])"' <<<"$report" | head -5 | paste -sd';')"

# ---------------------------------------------------------------------------
# 3  Ratchets
# ---------------------------------------------------------------------------
echo; echo "${BOLD}3  Ratchets${RESET}"
check "wrapMode Text items: at most the baseline ($(jq -r .wrapMax "$BASE")), itself at most 5" "true" \
  "$(jq -rn --argjson r "$report" --slurpfile b "$BASE" '($r.wraps <= $b[0].wrapMax) and ($b[0].wrapMax <= 5)')"
check "Style.font.caption Texts: at most the baseline ($(jq -r .captionMax "$BASE")), itself at most 10" "true" \
  "$(jq -rn --argjson r "$report" --slurpfile b "$BASE" '($r.captions <= $b[0].captionMax) and ($b[0].captionMax <= 10)')"
check "…and the baselines are tight: a count that fell is written down" "$(jq -r '"\(.wraps) \(.captions)"' <<<"$report")" \
  "$(jq -r '"\(.wrapMax) \(.captionMax)"' "$BASE")"

# ---------------------------------------------------------------------------
# 4  The checker can fail
# ---------------------------------------------------------------------------
echo; echo "${BOLD}4  The checker can fail${RESET}"
mkdir -p "$work/fx"
cat >"$work/fx/eight.qml" <<'QML'
Text { text: "One two three four five six seven eight" }
QML
cat >"$work/fx/two.qml" <<'QML'
Text { text: "Saved it. Nothing else." }
QML
cat >"$work/fx/split.qml" <<'QML'
Text { text: "Alpha beta gamma delta" + name + " epsilon zeta eta theta" }
QML
cat >"$work/fx/seven.qml" <<'QML'
Text { text: "One two three four five six seven" }
Text { text: cond ? "One two three four five six seven" : "Alpha beta gamma delta epsilon zeta eta" }
Text { text: "Plain" }
QML
cat >"$work/fx/lower.qml" <<'QML'
Text { text: "and then the rest of it" }
QML
cat >"$work/fx/allowed.qml" <<'QML'
Text { text: "One two three four five six seven eight nine" }
QML
cat >"$work/fx/title" <<'SH'
  point some-id fix "Extraordinary compositions arrange themselves" \
    "The summary"
  finish failed 1 "Two short ones. Two short ones."
  point other-id ok "Seven words are fine to say here"
SH
printf '# fixture\nallowed.qml\tOne two three four five six seven eight nine\tfixture\nseven.qml\tnot in the file\tfixture\n' >"$work/fx/allow.txt"
fx() { python3 "$PY" --root "$work/fx" --allow "$work/fx/allow.txt" "$@"; }
n() { jq -r "$1" ; }
check "an 8-word string is flagged" "1" "$(fx eight.qml | n '.offenders | length')"
check "two sentences are flagged, in 4 words" "1" "$(fx two.qml | n '[.offenders[] | select(.why | index("two sentences"))] | length')"
check "a sentence split across two +-joined literals is flagged as one" "1 8 words" \
  "$(fx split.qml | n '"\(.offenders | length) \(.offenders[0].why[0])"')"
check "an unjoined literal that starts lowercase is flagged as a fragment" "a fragment" "$(fx lower.qml | n '.offenders[0].why[0]')"
check "a 45-character title is flagged" "1" "$(python3 "$PY" --root "$work/fx" --bash title | n '[.bash[] | select(.why | index("45 characters"))] | length')"
check "…as is a two-sentence finish message, and a 7-word title passes" "2" "$(python3 "$PY" --root "$work/fx" --bash title | n '.bash | length')"
check "a 7-word string, a 7-word branch and a one-word one pass" "0" "$(fx seven.qml | n '.offenders | length')"
check "an allowlisted string passes" "0" "$(fx allowed.qml | n '.offenders | length')"
check "an allowlist entry for a literal that is gone is stale" "seven.qml	not in the file" "$(fx seven.qml allowed.qml | n '.stale[0]')"

# ---------------------------------------------------------------------------
# 5  The removed strings
# ---------------------------------------------------------------------------
echo; echo "${BOLD}5  Removed strings${RESET}"
check "$(grep -vc '^#' "$REPO/dev/baselines/strings-removed.txt") old strings listed (40 at least)" "true" \
  "$([[ $(grep -vc '^#' "$REPO/dev/baselines/strings-removed.txt") -ge 40 ]] && echo true || echo false)"
check "none is back in dev/, bin/ or README.md" "" "$(jq -r '.old[] | "\(.file): \(.text[0:50])"' <<<"$report" | head -5 | paste -sd';')"
mkdir -p "$work/gone/dev" "$work/gone/bin"
printf '# comment\nA string long gone\n' >"$work/gone/removed.txt"
printf 'echo "A string long gone"\n' >"$work/gone/bin/script"
check "…and the check can fail: one put back in bin/ is found" "bin/script" \
  "$(python3 "$PY" --root "$work/gone" --removed "$work/gone/removed.txt" | jq -r '.old[0].file')"

# ---------------------------------------------------------------------------
# 6  The wiki (phase 2)
# ---------------------------------------------------------------------------
echo; echo "${BOLD}6  The wiki${RESET}"
PAGES="Home Getting-started Settings Plugins Setup-points Integrations Notifications Menu Lock-and-Face Profiles Corners Troubleshooting Export-and-import"

# wiki_problems <wiki dir>: one problem per line (none when the wiki is sound).
# Pages and Home; every relative link resolves, anchors too (GitHub's slugs, and
# a link into another .md file of the repo); no image, no `curl | sh`, no <word> that GitHub would hide as HTML, nothing
# in wiki/ but the 13 .md files. Links and headings inside code are not read.
wiki_problems() {
  python3 - "$1" "$PAGES" <<'PY'
import os, re, sys
root, pages = sys.argv[1], sys.argv[2].split()
bad = []
files = sorted(os.listdir(root)) if os.path.isdir(root) else []
for p in pages:
    if p + ".md" not in files: bad.append(f"missing page {p}")
for f in files:
    if f.endswith(".md") and f[:-3] not in pages: bad.append(f"extra page {f}")
    if not f.endswith(".md"): bad.append(f"not a page: {f}")
def text_of(path):
    t = open(path, encoding="utf-8").read()
    return re.sub(r"```.*?```", lambda m: "\n" * m.group(0).count("\n"), t, flags=re.S)
def slugs(path):
    out, seen = set(), {}
    for h in re.findall(r"^#{1,6}\s+(.+?)\s*#*\s*$", text_of(path), flags=re.M):
        h = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", h).replace("`", "").lower()
        s = re.sub(r"[^\w\- ]", "", h).replace(" ", "-")
        n = seen.get(s, 0); seen[s] = n + 1
        out.add(s if n == 0 else f"{s}-{n}")
    return out
home = os.path.join(root, "Home.md")
if os.path.isfile(home):
    h = open(home, encoding="utf-8").read()
    for p in pages:
        if p != "Home" and f"({p}.md)" not in h: bad.append(f"Home does not list {p}")
for name in files:
    if not name.endswith(".md"): continue
    raw = open(os.path.join(root, name), encoding="utf-8").read()
    if re.search(r"!\[[^\]]*\]\(", raw): bad.append(f"{name}: image")
    if re.search(r"<img\b", raw, re.I): bad.append(f"{name}: image")
    if re.search(r"<[A-Za-z/][^>]*>", re.sub(r"`[^`\n]*`", "", text_of(os.path.join(root, name)))): bad.append(f"{name}: angle brackets read as HTML")
    if re.search(r"curl[^\n]*\|\s*(su[d]o\s+)?(ba|z)?sh\b", raw): bad.append(f"{name}: curl piped to a shell")
    body = re.sub(r"`[^`\n]*`", "", text_of(os.path.join(root, name)))
    for target in re.findall(r"\]\(([^)\s]+)\)", body):
        if re.match(r"[a-z][a-z0-9+.-]*:", target): continue
        path, _, frag = target.partition("#")
        dest = os.path.normpath(os.path.join(root, path)) if path else os.path.join(root, name)
        if not os.path.exists(dest): bad.append(f"{name}->{target}"); continue
        if frag and dest.endswith(".md") and frag not in slugs(dest): bad.append(f"{name}->{target} (no such heading)")
print("\n".join(bad))
PY
}

check "the wiki folder exists" "true" "$([[ -d $REPO/wiki ]] && echo true || echo false)"
problems=$(wiki_problems "$REPO/wiki")
check "the 13 pages exist and no other file is in wiki/" "" "$(grep -E '^(missing page|extra page|not a page)' <<<"$problems" | paste -sd';')"
check "Home.md lists every other page" "" "$(grep -E '^Home does not' <<<"$problems" | paste -sd';')"
check "every relative link and anchor resolves" "" "$(grep -E -- '->' <<<"$problems" | paste -sd';')"
check "no image, no curl piped to a shell, no <word> GitHub would hide" "" "$(grep -E ': (image|curl|angle)' <<<"$problems" | paste -sd';')"
check "the README links the wiki's Home" "true" \
  "$(grep -q 'https://github.com/Kalinewb/omarchy-notch/blob/master/wiki/Home.md' "$REPO/README.md" && echo true || echo false)"

# The check can fail: a fixture wiki with one of each fault.
fxw="$work/wiki"; mkdir -p "$fxw"
for p in $PAGES; do printf '# %s\n\n## Heading\n' "$p" >"$fxw/$p.md"; done
{ echo "# Home"; for p in $PAGES; do [[ $p == Home || $p == Corners ]] || echo "- [$p]($p.md)"; done; } >"$fxw/Home.md"
printf '# Plugins\n\n## Heading\n[gone](Nowhere.md) [bad](Menu.md#no-such) [ok](Menu.md#heading) [self](#heading)\n![pic](a.png)\nRun `curl x | sh` now <hidden> text\n' >"$fxw/Plugins.md"
rm "$fxw/Troubleshooting.md"; echo x >"$fxw/Extra.md"; echo x >"$fxw/shot.png"
fxp=$(wiki_problems "$fxw")
check "…and it can fail: a missing page is found" "true" "$(grep -q 'missing page Troubleshooting' <<<"$fxp" && echo true || echo false)"
check "…an extra page and a binary are found" "2" "$(grep -cE '^(extra page Extra.md|not a page: shot.png)' <<<"$fxp")"
check "…a page Home leaves out is found" "true" "$(grep -q 'Home does not list Corners' <<<"$fxp" && echo true || echo false)"
check "…a broken link and a broken anchor are found" "Plugins.md->Nowhere.md;Plugins.md->Menu.md#no-such (no such heading)" \
  "$(grep -E 'Plugins.md->(Nowhere|Menu)' <<<"$fxp" | paste -sd';')"
check "…and a good link, a good anchor and a link to its own heading pass" "" "$(grep -E 'Menu.md#heading|->#heading' <<<"$fxp" | paste -sd';')"
check "…an image, a piped curl and a hidden <word> are found" "3" "$(grep -cE ': (image|curl|angle)' <<<"$fxp")"

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}"
