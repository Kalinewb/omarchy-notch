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
#   6   wiki/*.md: relative links resolve, Home.md lists every page, the 13 pages
#       exist (the wiki is plan-wizard.md phase 2: skipped until wiki/ exists)

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
failures=0; checks=0; skipped=0
check() { # check <description> <expected> <actual>
  checks=$((checks + 1))
  if [[ $2 == "$3" ]]; then echo "  ${GREEN}pass${RESET}  $1"
  else echo "  ${RED}FAIL${RESET}  $1 ${DIM}(expected '$2', got '$3')${RESET}"; failures=$((failures + 1)); fi
}
skip() { skipped=$((skipped + 1)); echo "  ${DIM}skip${RESET}  $1"; }

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
if [[ ! -d $REPO/wiki ]]; then
  skip "wiki/ does not exist yet: pages, Home and links wait for plan-wizard.md phase 2"
else
  missing=""; for p in $PAGES; do [[ -f $REPO/wiki/$p.md ]] || missing+="$p "; done
  check "the 13 pages exist" "" "$missing"
  check "no page beyond the 13" "13" "$(find "$REPO/wiki" -maxdepth 1 -name '*.md' | wc -l)"
  unlisted=""; for p in $PAGES; do [[ $p == Home ]] || grep -q "($p.md)" "$REPO/wiki/Home.md" 2>/dev/null || unlisted+="$p "; done
  check "Home.md lists every other page" "" "$unlisted"
  broken=$(python3 - "$REPO/wiki" <<'PY'
import os, re, sys
root = sys.argv[1]
bad = []
for name in sorted(os.listdir(root)):
    if not name.endswith(".md"): continue
    for target in re.findall(r"\]\(([^)#\s]+)(?:#[^)]*)?\)", open(os.path.join(root, name), encoding="utf-8").read()):
        if re.match(r"[a-z]+:", target): continue
        if not os.path.exists(os.path.normpath(os.path.join(root, target))): bad.append(f"{name}->{target}")
print(" ".join(bad))
PY
)
  check "every relative link resolves" "" "$broken"
fi

echo
if (( failures )); then echo "${RED}$failures of $checks checks failed${RESET}"; exit 1; fi
echo "${GREEN}$checks checks pass${RESET}${skipped:+ ${DIM}($skipped skipped)${RESET}}"
