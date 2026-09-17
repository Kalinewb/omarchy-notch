#!/bin/bash

# Every check, lint first.
#
#   ./dev/check.sh            lint, then all suites
#   ./dev/check.sh lint keys  lint, then just the named suites
#
# Lint gates the rest: a QML error means nothing below would test the plugin
# as it would actually load. Suites run in order and all run even if one
# fails; the exit status is non-zero if lint or any suite failed.

set -uo pipefail
DEV=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SUITES=(geometry glow glow-bottom keys media contract menu colours design motion windows)
(( $# > 0 )) && SUITES=("${@/#lint/}") && SUITES=(${SUITES[@]})

"$DEV/lint.sh" || { echo; echo "lint failed: not running the test suites"; exit 1; }

failed=()
for suite in "${SUITES[@]}"; do
  [[ -z $suite ]] && continue
  echo
  "$DEV/$suite.sh" || failed+=("$suite")
done
echo
if (( ${#failed[@]} )); then echo "failed: ${failed[*]}"; exit 1; fi
echo "lint and ${#SUITES[@]} suites pass"
