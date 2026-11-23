#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh release

TARGET="$HOME/Applications"
mkdir -p "$TARGET"

pkill -x AppPresence 2>/dev/null || true
sleep 0.5

rm -rf "$TARGET/AppPresence.app"
cp -R AppPresence.app "$TARGET/AppPresence.app"
open "$TARGET/AppPresence.app"

echo "installed $TARGET/AppPresence.app"
