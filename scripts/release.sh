#!/bin/bash
# Build Dami for release and put it in a .dmg, for people without Xcode (v1.0 M4).
#
# Signed with the same Apple Development certificate as scripts/build.sh, so an install from the .dmg over a build from source
# keeps macOS permissions. Not notarized (owner, 2026-11-04): on first open macOS blocks it, and the README explains
# System Settings › Privacy & Security › Open Anyway. The .dmg window shows those steps, with a shortcut to that pane.
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
RW="$OUT/Dami-rw.dmg"
VOLUME="Dami $VERSION"
rm -rf "$STAGE" "$DMG" "$RW"
mkdir -p "$STAGE/.background"
cp -R "$BUILT" "$STAGE/Dami.app"
ln -s /Applications "$STAGE/Applications"
# Opens System Settings › Privacy & Security, where Open Anyway is, for the first open.
ln -s /System/Library/PreferencePanes/Security.prefPane "$STAGE/Privacy & Security"

# The window's look: a drawn background with the icons placed on it (scripts/make-dmg-background.swift holds the same layout).
swift scripts/make-dmg-background.swift "$OUT/bg" > /dev/null
tiffutil -cathidpicheck "$OUT/bg/background.png" "$OUT/bg/background@2x.png" -out "$STAGE/.background/background.tiff" 2> /dev/null
rm -rf "$OUT/bg"

# A writable image first, so Finder can save the layout into it, then the compressed one.
if [[ -d "/Volumes/$VOLUME" ]]; then hdiutil detach -quiet "/Volumes/$VOLUME" || true; fi
hdiutil create -quiet -volname "$VOLUME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW"
rm -rf "$STAGE"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | sed -nE 's|.*(/Volumes/.*)$|\1|p' | head -1)
detach() { hdiutil detach -quiet "$MOUNT" 2> /dev/null || hdiutil detach -quiet -force "$MOUNT" 2> /dev/null || true; }
trap detach EXIT

# Finder may ask once to let this terminal control it (Automation). Without it the .dmg still works, just as a plain folder.
if ! osascript <<OSA
with timeout of 300 seconds
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 608}
    set options to the icon view options of container window
    set arrangement of options to not arranged
    set icon size of options to 96
    set text size of options to 12
    set background picture of options to file ".background:background.tiff"
    set position of item "Dami.app" of container window to {170, 160}
    set position of item "Applications" of container window to {490, 160}
    set position of item "Privacy & Security" of container window to {540, 355}
    update without registering applications
    delay 1
    close
  end tell
end tell
end timeout
OSA
then
  echo "Finder couldn't lay out the window; the .dmg will open as a plain folder."
fi
sync
detach
trap - EXIT
hdiutil convert -quiet "$RW" -format UDZO -o "$DMG"
rm -f "$RW"

# What macOS checks to keep permissions: the same designated requirement as the installed app.
echo "Signature:"
codesign -d -r- "$BUILT" 2>&1 | sed -n 's/^designated => /  /p'
echo "Wrote $DMG ($(du -h "$DMG" | cut -f1))"
