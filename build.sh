#!/bin/bash
# Bygger build/Viggo+.app. Brug ./install.sh for at installere den.
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP="$DIR/build/Viggo+.app"
rm -rf "$DIR/build"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
    -o "$APP/Contents/MacOS/ViggoPlus" "$DIR"/Sources/*.swift "$DIR"/Shared/*.swift
codesign --force --sign - --identifier com.ottobigo.ViggoPlus \
    --requirements '=designated => identifier "com.ottobigo.ViggoPlus"' "$APP"
echo "✅ Built $APP"
