#!/bin/bash
# Builds Webby on this Mac, signs it for development and installs it on a paired Apple TV.
#
#   scripts/install-appletv.sh                  # the first paired Apple TV
#   scripts/install-appletv.sh "Living Room"    # a specific one, by name
#
# Signs with the App Store Connect API key in ~/Downloads (team 57PZQ6DM94), so Xcode doesn't need an
# Apple ID signed in. The first run registers the Apple TV on the developer account and creates a
# development certificate in this Mac's keychain; later runs reuse both.
#
# Pair the Apple TV first: on the TV, Settings > Remotes and Devices > Remote App and Devices; on the
# Mac, Xcode > Window > Devices and Simulators > select it > Pair.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID=83W34R3JB7
ISSUER_ID=8be62f06-e439-49eb-8d87-0546945e8386
KEY_PATH="$HOME/Downloads/AuthKey_$KEY_ID.p8"
[ -f "$KEY_PATH" ] || { echo "Missing $KEY_PATH"; exit 1; }

DEVICE="${1:-}"
if [ -z "$DEVICE" ]; then
  DEVICES=$(mktemp)
  xcrun devicectl list devices --json-output "$DEVICES" >/dev/null 2>&1 || true
  DEVICE=$(python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
tvs = [d["deviceProperties"]["name"] for d in data["result"]["devices"]
       if d.get("hardwareProperties", {}).get("deviceType") == "appleTV"]
print(tvs[0] if tvs else "")' "$DEVICES" 2>/dev/null || true)
  rm -f "$DEVICES"
fi
[ -n "$DEVICE" ] || { echo "No paired Apple TV found. Pair it in Xcode first (see the top of this script)."; exit 1; }
echo "Installing on: $DEVICE"

xcodegen generate >/dev/null
LOG=$(mktemp)
if ! xcodebuild -project Webby.xcodeproj -scheme Webby -configuration Release \
     -destination "platform=tvOS,name=$DEVICE" -derivedDataPath build/DD-device \
     -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
     -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID" \
     build > "$LOG" 2>&1; then
  { grep -E "error:" "$LOG" | sort -u | head -20; tail -30 "$LOG"; } || true; exit 1
fi

APP=build/DD-device/Build/Products/Release-appletvos/Webby.app
xcrun devicectl device install app --device "$DEVICE" "$APP"
xcrun devicectl device process launch --device "$DEVICE" app.webby || true
echo "Done. A free or paid team's development build keeps working until its profile expires; re-run to renew."
