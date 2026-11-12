#!/bin/bash
# Builds Whiteboard.app from index.html, installs it in ~/Applications and adds it to the Dock.
# Run this again after editing index.html to update the app.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Whiteboard.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Whiteboard.app"
VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
echo "→ Building Whiteboard $VERSION"

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD/icon.iconset"

echo "→ Compiling app"
swiftc -O -o "$APP/Contents/MacOS/Whiteboard" "$ROOT/app/main.swift" \
  -framework Cocoa -framework WebKit

echo "→ Drawing icon"
swiftc -o "$BUILD/make_icon" "$ROOT/app/make_icon.swift" -framework Cocoa
"$BUILD/make_icon" "$BUILD/icon_1024.png"
for s in 16 32 128 256 512; do
  sips -z $s $s "$BUILD/icon_1024.png" --out "$BUILD/icon.iconset/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$BUILD/icon_1024.png" --out "$BUILD/icon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$BUILD/icon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

sed "s/__VERSION__/$VERSION/g" "$ROOT/index.html" > "$APP/Contents/Resources/index.html"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Whiteboard</string>
  <key>CFBundleDisplayName</key><string>Whiteboard</string>
  <key>CFBundleIdentifier</key><string>local.whiteboard.app</string>
  <key>CFBundleExecutable</key><string>Whiteboard</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "→ Installing to $DEST"
pkill -x Whiteboard 2>/dev/null || true
mkdir -p "$DEST_DIR"
rm -rf "$DEST"
cp -R "$APP" "$DEST"
touch "$DEST"

if ! defaults read com.apple.dock persistent-apps 2>/dev/null | grep -q "Applications/Whiteboard.app"; then
  echo "→ Adding to Dock"
  defaults write com.apple.dock persistent-apps -array-add \
    "<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>file://$DEST/</string><key>_CFURLStringType</key><integer>15</integer></dict></dict></dict>"
  killall Dock
fi

echo "✓ Done. Whiteboard $VERSION is in your Dock."
