#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

APP="AppPresence.app"
CONFIG="${1:-release}"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/AppPresence" "$APP/Contents/MacOS/AppPresence"
cp "Resources/Info.plist" "$APP/Contents/Info.plist"

codesign --force --sign - --identifier com.aryan.apppresence "$APP" 2>/dev/null

echo "built $APP"
