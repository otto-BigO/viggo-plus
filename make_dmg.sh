#!/bin/bash
# Bygger appen og pakker den i dist/ViggoPlus-<version>.dmg med en genvej til Programmer.
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SCRIPT_DIR/Resources/Info.plist")
DIST="$SCRIPT_DIR/dist"
STAGE="$DIST/stage"
RW_DMG="$DIST/rw.dmg"
DMG="$DIST/ViggoPlus-$VERSION.dmg"

bash "$SCRIPT_DIR/build.sh"

echo "📦 Pakker Viggo+ $VERSION..."
rm -rf "$STAGE" "$RW_DMG" "$DMG"
mkdir -p "$STAGE"
cp -R "$SCRIPT_DIR/build/Viggo+.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

# Skrivbar kopi foerst, saa drevet kan faa app-ikonet, derefter komprimeret.
hdiutil create -quiet -volname "Viggo+" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW_DMG"
MOUNT=$(hdiutil attach "$RW_DMG" -nobrowse -noautoopen | awk -F'\t' '$NF ~ /\/Volumes\// {gsub(/^[ \t]+|[ \t]+$/, "", $NF); print $NF}')
SetFile -a C "$MOUNT"
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -rf "$STAGE" "$RW_DMG"

echo "✅ $DMG"
