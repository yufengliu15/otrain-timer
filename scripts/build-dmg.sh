#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/otrain-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "dist/O-Train Timer.app" "$STAGING/O-Train Timer.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create \
  -volname "O-Train Timer" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$PWD/O-Train Timer.dmg"
hdiutil verify "$PWD/O-Train Timer.dmg"
printf '\nCreated: %s/O-Train Timer.dmg\n' "$PWD"
