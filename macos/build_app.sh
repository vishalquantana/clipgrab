#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build/debug"
APP_DIR="$SCRIPT_DIR/ClipGrab.app"

echo "Building ClipGrab..."
cd "$SCRIPT_DIR"
swift build

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

echo "Build complete!"
echo "App bundle: $APP_DIR"
echo ""
echo "To run: open '$APP_DIR'"
echo "Or:     '$APP_DIR/Contents/MacOS/ClipGrab'"
