#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_DIR="$SCRIPT_DIR/ClipGrab.app"
DMG_NAME="ClipGrab.dmg"
DMG_PATH="$SCRIPT_DIR/../$DMG_NAME"

IDENTITY="Developer ID Application: Quantana Pty Ltd (EN82ED6ZHA)"
ENTITLEMENTS="$SCRIPT_DIR/ClipGrab.entitlements"
APPLE_ID="${APPLE_ID:-me@vishalkumar.in}"
TEAM_ID="EN82ED6ZHA"

echo "Building ClipGrab..."
cd "$SCRIPT_DIR"
swift build -c release

echo "Assembling .app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/ClipGrab" "$APP_DIR/Contents/MacOS/ClipGrab"

# Copy Info.plist
cp "$SCRIPT_DIR/ClipGrab/Info.plist" "$APP_DIR/Contents/Info.plist"

# Copy resources for Bundle.main (Contents/Resources)
cp "$BUILD_DIR/ClipGrab_ClipGrab.bundle/DefaultPlatforms.json" "$APP_DIR/Contents/Resources/DefaultPlatforms.json"


# Copy app icon
ASSETS_DIR="$SCRIPT_DIR/ClipGrab/Assets.xcassets"
cp "$ASSETS_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

# Copy menu bar icons
cp "$ASSETS_DIR/menubar_icon_18x18.png" "$APP_DIR/Contents/Resources/menubar_icon_18x18.png"
cp "$ASSETS_DIR/menubar_icon_18x18@2x.png" "$APP_DIR/Contents/Resources/menubar_icon_18x18@2x.png"

# Copy Python download engine
ENGINE_DIR="$(dirname "$SCRIPT_DIR")/engine"
if [ -d "$ENGINE_DIR" ]; then
    cp "$ENGINE_DIR/download_manager.py" "$APP_DIR/Contents/Resources/download_manager.py"
fi

echo "Signing .app..."
codesign --deep --force --verify --verbose \
  --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$APP_DIR"

echo "Creating DMG..."
rm -f "$DMG_PATH"
hdiutil create -volname "ClipGrab" -srcfolder "$APP_DIR" -ov -format UDZO "$DMG_PATH"

echo "Signing DMG..."
codesign --force --sign "$IDENTITY" "$DMG_PATH"

# Notarize using stored keychain profile (set up with: xcrun notarytool store-credentials "ClipGrab-notarize")
if xcrun notarytool history --keychain-profile "ClipGrab-notarize" &>/dev/null; then
  echo "Notarizing DMG (this takes ~1-2 min)..."
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "ClipGrab-notarize" \
    --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$DMG_PATH"
  echo "Notarization complete!"
else
  echo ""
  echo "Skipping notarization (keychain profile 'ClipGrab-notarize' not found)."
  echo "To set up: xcrun notarytool store-credentials ClipGrab-notarize --apple-id YOUR_APPLE_ID --team-id EN82ED6ZHA"
fi

echo ""
echo "Build complete!"
echo "App: $APP_DIR"
echo "DMG: $DMG_PATH"
