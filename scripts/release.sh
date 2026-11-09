#!/bin/bash
# Build Dami for release and put it in a .dmg, for people without Xcode (v1.0 M4).
#
# Signed with the same Apple Development certificate as scripts/build.sh, so an install from the .dmg over a build from source
# keeps macOS permissions. Not notarized (owner, 2026-11-04): on first open macOS blocks it, and the README explains
# System Settings › Privacy & Security › Open Anyway.
#
# Doesn't install or relaunch anything. Writes build/release/Dami-<version>.dmg.
set -euo pipefail

cd "$(dirname "$0")/.."

TEAM_ID=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1)
if [[ -z "$TEAM_ID" ]]; then
  echo "No Apple Development certificate found."
  echo "Xcode → Settings → Accounts → your Apple ID → Manage Certificates → + → Apple Development"
  exit 1
fi

VERSION=$(sed -nE 's/^ *MARKETING_VERSION: *"?([^"]+)"?/\1/p' project.yml | head -1)
BUILD=$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([^"]+)"?/\1/p' project.yml | head -1)
echo "Dami $VERSION ($BUILD), signing with team $TEAM_ID"

DAMI_TEAM_ID="$TEAM_ID" xcodegen generate --quiet
xcodebuild -project Dami.xcodeproj -scheme Dami -configuration Release \
  -derivedDataPath build -allowProvisioningUpdates -quiet build

BUILT="build/Build/Products/Release/Dami.app"
codesign --verify --deep --strict "$BUILT"

OUT="build/release"
STAGE="$OUT/stage"
DMG="$OUT/Dami-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$BUILT" "$STAGE/Dami.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Dami $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$STAGE"

# What macOS checks to keep permissions: the same designated requirement as the installed app.
echo "Signature:"
codesign -d -r- "$BUILT" 2>&1 | sed -n 's/^designated => /  /p'
echo "Wrote $DMG ($(du -h "$DMG" | cut -f1))"
