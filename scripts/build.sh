#!/bin/bash
# Build LocalFlow, sign it with your Apple Development certificate, and install it to
# /Applications/LocalFlow.app.
#
# Same certificate + same install path every time = macOS keeps the Microphone, Accessibility
# and Input Monitoring permissions across rebuilds (PLAN §8).
#
# Usage: scripts/build.sh            # Release build, install, relaunch
#        scripts/build.sh Debug      # for debugging; latency numbers aren't representative
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-Release}"
APP_DEST="/Applications/LocalFlow.app"

# Team ID = the "OU" field of the Apple Development certificate in your keychain.
TEAM_ID=$(security find-certificate -c "Apple Development" -p 2>/dev/null \
  | openssl x509 -noout -subject 2>/dev/null | sed -nE 's/.*OU ?= ?([A-Z0-9]{10}).*/\1/p' | head -1)
if [[ -z "$TEAM_ID" ]]; then
  echo "No Apple Development certificate found."
  echo "Xcode → Settings → Accounts → your Apple ID → Manage Certificates → + → Apple Development"
  exit 1
fi
echo "Signing with team $TEAM_ID"

LOCALFLOW_TEAM_ID="$TEAM_ID" xcodegen generate --quiet

xcodebuild -project LocalFlow.xcodeproj -scheme LocalFlow -configuration "$CONFIG" \
  -derivedDataPath build -allowProvisioningUpdates -quiet build

BUILT="build/Build/Products/$CONFIG/LocalFlow.app"
codesign --verify --strict "$BUILT"

pkill -x LocalFlow 2>/dev/null && sleep 1 || true
rm -rf "$APP_DEST"
cp -R "$BUILT" "$APP_DEST"
open "$APP_DEST"
echo "Installed and launched $APP_DEST"
