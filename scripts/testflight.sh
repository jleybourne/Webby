#!/bin/bash
# Builds Webby on this Mac and uploads it to TestFlight (no GitHub Actions), like Cinefin's
# Tools/testflight.sh.
#
#   scripts/testflight.sh
#
# Needs the App Store Connect API key in ~/Downloads and a tvOS app with bundle ID
# au.leybourne.webby on App Store Connect. The app is archived unsigned and signed for the App Store
# during export by Apple's cloud signing, so no certificates are needed on this Mac.
#
# Webby uses a private API (UIWebView on tvOS). App Store Connect may reject the build during
# processing; `python3 scripts/asc.py builds` shows whether it went through.
set -euo pipefail
cd "$(dirname "$0")/.."

KEY_ID=83W34R3JB7
ISSUER_ID=8be62f06-e439-49eb-8d87-0546945e8386
KEY_PATH="$HOME/Downloads/AuthKey_$KEY_ID.p8"
TEAM_ID=57PZQ6DM94
[ -f "$KEY_PATH" ] || { echo "Missing $KEY_PATH"; exit 1; }

BUILD=$(python3 scripts/asc.py next-build)
echo "Build $BUILD"

xcodegen generate >/dev/null
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict></plist>
EOF

ARCHIVE="$WORK/Webby.xcarchive"
echo "• Archiving…"
if ! xcodebuild -project Webby.xcodeproj -scheme Webby -configuration Release \
     -destination "generic/platform=tvOS" -archivePath "$ARCHIVE" \
     DEVELOPMENT_TEAM="$TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD" CODE_SIGNING_ALLOWED=NO \
     archive > "$WORK/archive.log" 2>&1; then
  { grep -E "error:" "$WORK/archive.log" | sort -u | head -20; tail -30 "$WORK/archive.log"; } || true; exit 1
fi

echo "• Signing and uploading…"
if ! xcodebuild -exportArchive -archivePath "$ARCHIVE" -exportOptionsPlist "$WORK/ExportOptions.plist" \
     -exportPath "$WORK/export" -allowProvisioningUpdates -authenticationKeyPath "$KEY_PATH" \
     -authenticationKeyID "$KEY_ID" -authenticationKeyIssuerID "$ISSUER_ID" > "$WORK/export.log" 2>&1; then
  { grep -iE "error|fail" "$WORK/export.log" | sort -u | head -20; tail -30 "$WORK/export.log"; } || true; exit 1
fi
echo "Uploaded build $BUILD. Check processing with: python3 scripts/asc.py builds"
