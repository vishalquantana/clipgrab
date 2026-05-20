#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/release"
APP_DIR="$SCRIPT_DIR/ClipGrab.app"

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

# Copy SPM resource bundle (for Bundle.module lookups)
cp -r "$BUILD_DIR/ClipGrab_ClipGrab.bundle" "$APP_DIR/ClipGrab_ClipGrab.bundle"

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

echo "Build complete!"
echo "App bundle: $APP_DIR"
echo ""
echo "To run: open '$APP_DIR'"
echo "Or:     '$APP_DIR/Contents/MacOS/ClipGrab'"
