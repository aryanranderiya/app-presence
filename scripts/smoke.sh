#!/bin/bash
set -uo pipefail

LOG="$HOME/Library/Application Support/AppPresence/app.log"
: > "$LOG" 2>/dev/null || true

for app in Arc Rex Conductor Ghostty; do
    echo "focus $app"
    open -a "$app" 2>/dev/null || echo "  not installed"
    sleep 4
done

echo "--- activity log ---"
tail -20 "$LOG" 2>/dev/null || echo "no log at $LOG"
