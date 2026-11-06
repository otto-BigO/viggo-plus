#!/bin/bash
# Bygger Viggo+, kopierer den til Programmer og starter den.
set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
bash "$SCRIPT_DIR/build.sh"

APP_DEST="/Applications/Viggo+.app"
echo "🚀 Installerer Viggo+.app i /Applications..."
pkill -x ViggoPlus || true
for _ in $(seq 1 50); do pgrep -x ViggoPlus >/dev/null || break; sleep 0.1; done

rm -rf "$APP_DEST"
cp -R "$SCRIPT_DIR/build/Viggo+.app" "$APP_DEST"
touch "$APP_DEST"

echo "✨ Åbner Viggo+.app..."
open "$APP_DEST"
