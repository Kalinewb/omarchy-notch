#!/bin/bash

# The notifications companion's one decision -- is Omarchy's toast window
# visible -- as numbers.
#
#   ./dev/notifications-companion.sh
#
# Runs companion/kalinewb.notch-notifications/Service.qml under qmltestrunner
# against a stand-in for Omarchy's Service.qml (dev/harness/notifications-companion)
# and the notch's real bridge. Needs Qt only: no Quickshell, no Omarchy, no
# session, so it runs anywhere qt6-declarative's test tools are installed.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
HARNESS="$REPO/dev/harness/notifications-companion"
RUNNER=/usr/lib/qt6/bin/qmltestrunner
[[ -x $RUNNER ]] || { echo "notifications-companion: $RUNNER is not installed (qt6-declarative-dev-tools, qml6-module-qttest)" >&2; exit 1; }

work=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-notch-nc.XXXXXX")
trap 'rm -rf "$work"' EXIT
cp "$HARNESS/Api.qml" "$HARNESS/Win.qml" "$work/"
for f in "$HARNESS"/*.qml.in; do
  sed -e "s#@HARNESS@#$HARNESS#g; s#@REPO@#$REPO#g" "$f" >"$work/$(basename "${f%.in}")"
done

cd "$work" || exit 1
QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-$work}" \
  "$RUNNER" -import "$HARNESS" -input "$work" 2>&1 | grep -E "^(PASS|FAIL|Totals)|Actual|Expected|Loc:"
exit "${PIPESTATUS[0]}"
