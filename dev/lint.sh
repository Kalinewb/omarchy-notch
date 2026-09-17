#!/bin/bash

# Lint the plugin's QML before anything runs it.
#
#   ./dev/lint.sh
#
# A third-party plugin with a QML error does not reach the journal: it just
# fails to appear. qmllint catches that first, resolving `qs.*` imports against
# the installed Omarchy shell.
#
# Fails when:
#   - qmllint exits non-zero (a syntax error exits 255), or
#   - any warning in a category that means "this will not load or bind"
#     (syntax, import, missing-type, uncreatable-type, unresolved-type,
#     signal-handler-parameters, incompatible-type, read-only-property,
#     duplicated-name, required, ...) that the Omarchy file it was forked
#     from does not also produce. Bar.qml is vendored from Omarchy's
#     plugins/bar/Bar.qml and menu/NotchMenu.qml from plugins/menu/Menu.qml,
#     so their inherited warnings are allowed -- as a count per message,
#     computed by linting the installed upstream files on every run, so the
#     allowance follows Omarchy instead of a hand-kept list.
# Reported but not fatal: `unqualified` access, and members "not found on
# type QObject" (`bar` and Style tokens are injected untyped).

set -uo pipefail

GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; BOLD=$'\e[1m'; RESET=$'\e[0m'
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
QMLLINT=/usr/lib/qt6/bin/qmllint
SHELL_PATH=$(systemctl --user show-environment 2>/dev/null | sed -n 's/^OMARCHY_PATH=//p' | tail -n 1)
: "${SHELL_PATH:=${OMARCHY_PATH:-/usr/share/omarchy}}"
[[ -x $QMLLINT ]] || { echo "lint: $QMLLINT is not installed (qt6-declarative)" >&2; exit 1; }
[[ -f $SHELL_PATH/shell/plugins/bar/Bar.qml ]] || { echo "lint: no Omarchy shell at $SHELL_PATH/shell" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-lint.XXXXXX")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/qmlpath" "$work/upstream"
ln -sfn "$SHELL_PATH/shell" "$work/qmlpath/qs"
# Each forked file's upstream, under the fork's own name so warnings match.
cp "$SHELL_PATH/shell/plugins/bar/Bar.qml" "$SHELL_PATH/shell/plugins/bar/BarModel.js" "$work/upstream/"
cp "$SHELL_PATH/shell/plugins/menu/Menu.qml" "$work/upstream/NotchMenu.qml"
cp "$SHELL_PATH/shell/plugins/menu/MenuModel.js" "$work/upstream/"

FATAL='syntax|import|missing-type|uncreatable-type|unresolved-type|signal-handler-parameters|incompatible-type|read-only-property|duplicated-name|required|unresolved-alias|missing-enum-entry|recursion-depth-errors|attached-property-reuse|non-list-property|uncreatable-type'

cd "$REPO"
mapfile -t files < <(git ls-files '*.qml' ':!dev/**' 2>/dev/null || find . -maxdepth 1 -name '*.qml' -printf '%P\n')

lint() { "$QMLLINT" -I "$work/qmlpath" -I /usr/lib/qt6/qml "$@" 2>&1; }
# "<file basename>|<category>|<message>" per fatal-category warning, no line numbers
fatal_of() { sed -nE "s#^(Warning|Error): ([^:]+):[0-9]+:[0-9]+: (.*) \[($FATAL)\]\$#\2|\4|\3#p" | sed -E 's#^[^|]*/##'; }

echo "${BOLD}QML lint${RESET}  ${DIM}${#files[@]} files, qs.* → $SHELL_PATH/shell${RESET}"
ours=$(lint "${files[@]}"); rc=$?
upstream=$(lint "$work/upstream/Bar.qml" "$work/upstream/NotchMenu.qml")

allowed=$(fatal_of <<<"$upstream" | sort | uniq -c)
found=$(fatal_of <<<"$ours" | sort | uniq -c)
# Anything in ours beyond the upstream count for the same Bar.qml message.
new=$(python3 - "$allowed" "$found" <<'PY'
import sys
def parse(t):
    out = {}
    for line in t.splitlines():
        line = line.strip()
        if not line: continue
        n, key = line.split(" ", 1)
        out[key] = int(n)
    return out
allowed, found = parse(sys.argv[1]), parse(sys.argv[2])
for key, n in sorted(found.items()):
    extra = n - (allowed.get(key, 0) if key.split("|")[0] in ("Bar.qml", "NotchMenu.qml") else 0)
    if extra > 0: print(f"{extra}× {key}")
PY
)
inherited=$(python3 - "$allowed" "$found" <<'PY'
import sys
def parse(t):
    out = {}
    for line in t.splitlines():
        line = line.strip()
        if not line: continue
        n, key = line.split(" ", 1); out[key] = int(n)
    return out
a, f = parse(sys.argv[1]), parse(sys.argv[2])
print(sum(min(n, a.get(k, 0)) for k, n in f.items() if k.split("|")[0] in ("Bar.qml", "NotchMenu.qml")))
PY
)

unqualified=$(grep -c '\[unqualified\]' <<<"$ours")
qobject=$(grep -cE 'not found on type "QObject" \[missing-property\]' <<<"$ours")
other_missing=$(grep -E '\[missing-property\]' <<<"$ours" | grep -vc 'on type "QObject"')

echo "  ${DIM}qmllint exit $rc; inherited from Omarchy's Bar.qml and Menu.qml: $inherited; unqualified: $unqualified; members not found on QObject (expected): $qobject; other missing members: $other_missing${RESET}"
if [[ -n ${LINT_VERBOSE:-} ]]; then grep -E '^(Warning|Error)' <<<"$ours" | grep -vE '\[unqualified\]'; fi

status=0
if (( rc != 0 )); then
  echo "  ${RED}FAIL${RESET}  qmllint exited $rc"
  grep -E '^(Error|Warning).*\[syntax\]|^Error' <<<"$ours" | sed 's/^/        /' | head -20
  status=1
fi
if [[ -n $new ]]; then
  echo "  ${RED}FAIL${RESET}  warnings that mean QML will not load or bind, beyond the Omarchy files they were forked from:"
  while IFS= read -r line; do
    msg=${line#*× }
    file=${msg%%|*}; rest=${msg#*|}; cat=${rest%%|*}; text=${rest#*|}
    where=$(grep -F -- "$text [$cat]" <<<"$ours" | grep -F "$file:" | sed -E 's/^(Warning|Error): ([^ ]+): .*/\2/' | tr '\n' ' ')
    echo "        ${line%%× *}× $file [$cat] $text ${DIM}at $where${RESET}"
  done <<<"$new"
  status=1
fi
if (( status == 0 )); then echo "  ${GREEN}pass${RESET}  no QML errors, and no load-breaking warnings beyond those Omarchy's own Bar.qml and Menu.qml have"; fi
exit $status
