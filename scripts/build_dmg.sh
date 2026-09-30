#!/bin/bash
set -e

# Project root directory
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "🔨 Building AIUsage.app..."
"$DIR/scripts/build_app.sh"

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

# Strip any extended attributes from staging
xattr -rc "$STAGING_DIR" 2>/dev/null || true

echo "💿 Creating compressed DMG..."
hdiutil create \
  -volname "$DMG_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_FILE"

# Ad-hoc sign DMG
codesign --force --sign - "$DMG_FILE" 2>/dev/null || true

# Also create versioned DMG copy if Info.plist has CFBundleShortVersionString
VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$DIR/AIUsage.app/Contents/Info.plist" 2>/dev/null || echo "")
if [ -n "$VERSION" ]; then
  cp "$DMG_FILE" "$DIR/AIUsage-v${VERSION}.dmg"
  echo "📦 Also created versioned artifact: $DIR/AIUsage-v${VERSION}.dmg"
fi

rm -rf "$STAGING_DIR"
echo "✅ DMG successfully created at: $DMG_FILE"
