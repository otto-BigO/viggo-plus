#!/bin/bash
# Bygger appen, laver DMG + zip og udgiver version <x.y.z> på GitHub med noterne fra CHANGELOG.md.
# Zip-filen er den som opdateringen i appen henter.
set -e
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SCRIPT_DIR/Resources/Info.plist")
bash "$SCRIPT_DIR/make_dmg.sh"
ZIP="$SCRIPT_DIR/dist/ViggoPlus-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$SCRIPT_DIR/build/Viggo+.app" "$ZIP"
NOTES=$(awk -v v="## $VERSION" 'index($0, v)==1 {f=1; next} /^## / && f {exit} f' "$SCRIPT_DIR/CHANGELOG.md")
gh release create "v$VERSION" "$SCRIPT_DIR/dist/ViggoPlus-$VERSION.dmg" "$ZIP" \
    --title "Viggo+ $VERSION" --notes "$NOTES"
echo "✅ Udgivet v$VERSION"
