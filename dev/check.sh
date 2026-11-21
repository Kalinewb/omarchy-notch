#!/bin/bash

# Every check, lint first.
#
#   ./dev/check.sh            lint, then all suites
#   ./dev/check.sh lint keys  lint, then just the named suites
#
# Lint gates the rest: a QML error means nothing below would test the plugin
# as it would actually load. Suites run in order and all run even if one
# fails; the exit status is non-zero if lint or any suite failed.
#
# Every suite runs with a private TMPDIR, and one that leaves a process behind
# (a test notch, its inotifywait children) fails: whatever still carries that
# TMPDIR ten seconds after the suite is its own. It is ended, so one leak cannot
# pile onto the next. dev/leftovers.sh tests this.

set -uo pipefail
DEV=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source "$DEV/harness/leftovers.sh"
RUN_TMP=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-check.XXXXXX")
export TMPDIR=$RUN_TMP
trap 'rm -rf "$RUN_TMP"' EXIT
SUITES=(geometry glow glow-bottom glow-fade keys media contract menu menu-replace colours design motion windows update surface plugins setup platform hosting overlays keepshown notifications osd notifications-companion notifications-omarchy detached back notifications-interact settings panels attention quiet backone config leftovers)
(( $# > 0 )) && SUITES=("${@/#lint/}") && SUITES=(${SUITES[@]})

"$DEV/lint.sh" || { echo; echo "lint failed: not running the test suites"; exit 1; }

failed=()
for suite in "${SUITES[@]}"; do
  [[ -z $suite ]] && continue
  echo
  "$DEV/$suite.sh" || failed+=("$suite")
  # A child of a killed test notch (a `notch-setup detect` mid-run) is gone within
  # seconds; an inotifywait -m never is. Give the first a moment before judging.
  left=$(leftovers "$RUN_TMP")
  for _ in $(seq 20); do [[ -z $left ]] && break; sleep 0.5; left=$(leftovers "$RUN_TMP"); done
  if [[ -n $left ]]; then
    echo "  FAIL  $suite left running:"; sed 's/^/        /' <<<"$left"
    kill $(cut -d' ' -f1 <<<"$left") 2>/dev/null
    [[ " ${failed[*]} " == *" $suite "* ]] || failed+=("$suite")
  fi
done
echo
if (( ${#failed[@]} )); then echo "failed: ${failed[*]}"; exit 1; fi
echo "lint and ${#SUITES[@]} suites pass"
