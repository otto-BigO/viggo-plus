#!/bin/bash
# Bygger build/Viggo+.app. Brug ./install.sh for at installere den.
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP="$DIR/build/Viggo+.app"
rm -rf "$DIR/build"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$DIR/Resources/Info.plist" "$APP/Contents/Info.plist"
cp "$DIR/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# The iPhone app's source goes inside the Mac app, so Viggo+ can build and install it on an iPhone.
SRC="$APP/Contents/Resources/iPhoneSource"
mkdir -p "$SRC/iOS"
XCODEGEN="$(command -v xcodegen || echo /opt/homebrew/bin/xcodegen)"
if [ -x "$XCODEGEN" ]; then (cd "$DIR/iOS" && "$XCODEGEN" generate --quiet); fi
cp -R "$DIR/Shared" "$SRC/Shared"
for f in Sources Widget Assets.xcassets ViggoPlusPhone.xcodeproj App-Info.plist App.entitlements Widget.entitlements project.yml; do
    cp -R "$DIR/iOS/$f" "$SRC/iOS/$f"
done
rm -rf "$SRC/iOS/ViggoPlusPhone.xcodeproj/xcuserdata" "$SRC/iOS/ViggoPlusPhone.xcodeproj/project.xcworkspace/xcuserdata"
grep -m1 'MARKETING_VERSION' "$DIR/iOS/project.yml" | sed 's/.*"\(.*\)".*/\1/' > "$SRC/VERSION"

swiftc -O -parse-as-library -target arm64-apple-macosx14.0 \
    -o "$APP/Contents/MacOS/ViggoPlus" "$DIR"/Sources/*.swift "$DIR"/Shared/*.swift
codesign --force --sign - --identifier com.ottobigo.ViggoPlus \
    --requirements '=designated => identifier "com.ottobigo.ViggoPlus"' "$APP"
echo "✅ Built $APP"
