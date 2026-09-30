#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "🔨 Building AIUsage.app..."
./build_app.sh

DMG_NAME="AIUsage"
DMG_FILE="$DIR/${DMG_NAME}.dmg"
STAGING_DIR="$DIR/.dmg_staging"

echo "📦 Preparing DMG staging directory..."
rm -rf "$STAGING_DIR" "$DMG_FILE"
mkdir -p "$STAGING_DIR"

# Copy AIUsage.app
cp -R "$DIR/AIUsage.app" "$STAGING_DIR/"

# Create /Applications symlink for drag-and-drop installation
ln -s /Applications "$STAGING_DIR/Applications"

echo "💿 Creating compressed DMG..."
hdiutil create \
  -volname "$DMG_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_FILE"

rm -rf "$STAGING_DIR"
echo "✅ DMG successfully created at: $DMG_FILE"
