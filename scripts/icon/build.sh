#!/usr/bin/env bash
# Regenerates Webby's layered tvOS app icon (Back: background, Middle: cyan pane, Front: violet pane), Top Shelf images and docs/icon.png.
# Needs python3 and Node with Playwright (npm i playwright).
# Usage, from the repo root: bash scripts/icon/build.sh
set -e
cd "$(dirname "$0")/../.."
HERE=scripts/icon
TMP=$(mktemp -d)
r() { python3 -I "$HERE/gen.py" "$TMP/t.svg" "$2" "$3" "$4" "$5" "$6" && node "$HERE/render.js" "$TMP/t.svg" "$1" "$2" "$3"; }
APP="Webby/Resources/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
for spec in "App Icon|400|240|1x" "App Icon|800|480|2x" "App Icon - App Store|1280|768|1x"; do
  IFS='|' read -r name w h sc <<< "$spec"
  d="$APP/$name.imagestack"
  r "$TMP/back.png" "$w" "$h" back 0 0.92
  python3 -I -c "import sys; from PIL import Image; Image.open(sys.argv[1]).convert('RGB').save(sys.argv[2])" "$TMP/back.png" "$d/Back.imagestacklayer/Content.imageset/back@$sc.png"
  r "$d/Middle.imagestacklayer/Content.imageset/middle@$sc.png" "$w" "$h" left 0 0.92
  r "$d/Front.imagestacklayer/Content.imageset/front@$sc.png" "$w" "$h" right 0 0.92
done
for spec in "Top Shelf Image|1920|720|1x" "Top Shelf Image|3840|1440|2x" "Top Shelf Image Wide|2320|720|1x" "Top Shelf Image Wide|4640|1440|2x"; do
  IFS='|' read -r name w h sc <<< "$spec"
  r "$TMP/ts.png" "$w" "$h" back,left,right 0 0.7
  python3 -I -c "import sys; from PIL import Image; Image.open(sys.argv[1]).convert('RGB').save(sys.argv[2])" "$TMP/ts.png" "$APP/$name.imageset/topshelf@$sc.png"
done
r docs/icon.png 800 480 back,left,right 0 0.92
rm -rf "$TMP"
echo "Icons regenerated."
