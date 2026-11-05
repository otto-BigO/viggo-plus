#!/bin/bash
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP="$DIR/build/Viggo+.app"
rm -rf "$DIR/build"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
    -o "$APP/Contents/MacOS/ViggoPlus" "$DIR"/Sources/*.swift
codesign --force --sign - --identifier com.ottobigo.ViggoPlus \
    --requirements '=designated => identifier "com.ottobigo.ViggoPlus"' "$APP"
echo "Built $APP"

if [ "$1" = "install" ]; then
    pkill -x ViggoPlus 2>/dev/null; sleep 1
    rm -rf "/Applications/Viggo+.app"
    cp -R "$APP" "/Applications/Viggo+.app"
    open "/Applications/Viggo+.app"
    echo "Installed /Applications/Viggo+.app"
fi
