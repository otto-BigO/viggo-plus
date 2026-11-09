#!/bin/bash
# Builds Viggo+ for the iPhone connected by cable (or on the same Wi-Fi) and installs it.
# With a free Apple account the app stops opening after 7 days; run this again to renew it.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  TMP="$(mktemp)"
  xcrun devicectl list devices --json-output "$TMP" >/dev/null
  DEVICE="$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))["result"]["devices"]
phones = [x for x in d if x["hardwareProperties"].get("reality") == "physical"
          and x["hardwareProperties"].get("deviceType") == "iPhone"
          and x["connectionProperties"].get("tunnelState") != "unavailable"]
print(phones[0]["hardwareProperties"]["udid"] if phones else "")' "$TMP")"
  rm -f "$TMP"
fi
[ -n "$DEVICE" ] || { echo "Ingen iPhone fundet. Sæt den til med kabel og lås den op."; exit 1; }

command -v xcodegen >/dev/null || PATH="/opt/homebrew/bin:$PATH"
xcodegen generate --quiet
echo "Bygger til $DEVICE ..."
xcodebuild -project ViggoPlusPhone.xcodeproj -scheme ViggoPlus -configuration Release \
  -destination "id=$DEVICE" -derivedDataPath build-device -allowProvisioningUpdates -quiet build
APP="build-device/Build/Products/Release-iphoneos/Viggo+.app"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
EXP="$(security cms -D -i "$APP/embedded.mobileprovision" | plutil -extract ExpirationDate raw -)"
echo "Installeret. Signaturen udløber $EXP, så kør scriptet igen inden da."
