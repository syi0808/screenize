#!/bin/bash
set -e

# ============================================
# Screenize release script
# Usage: ./scripts/release.sh 2.1
# ============================================

VERSION=$1
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
RELEASE_DIR="$PROJECT_DIR/release"
APP_NAME="Screenize"
DMG_NAME="${APP_NAME}.dmg"
SPARKLE_TOOL_DIR="$PROJECT_DIR/tools/sparkle"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}Warning:${NC} $1"
}

print_error() {
    echo -e "${RED}Error:${NC} $1"
}

# Version check
if [ -z "$VERSION" ]; then
    echo "Usage: $0 <version>"
    echo "Example: $0 2.1"
    exit 1
fi

echo ""
echo "============================================"
echo "  Screenize v${VERSION} release build"
echo "============================================"
echo ""

# Ensure Sparkle tools
if [ ! -f "$SPARKLE_TOOL_DIR/bin/sign_update" ]; then
    print_step "Downloading Sparkle tools..."
    mkdir -p "$SPARKLE_TOOL_DIR"
    cd "$SPARKLE_TOOL_DIR"
    curl -L -o Sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz
    tar -xf Sparkle.tar.xz
    rm Sparkle.tar.xz
    cd "$PROJECT_DIR"
    print_step "Sparkle tools installed"
fi

# Clean build directories
print_step "Cleaning build directories..."
rm -rf "$BUILD_DIR"
rm -rf "$RELEASE_DIR"
mkdir -p "$RELEASE_DIR"

# Update version in Info.plist
print_step "Updating Info.plist version to ${VERSION}..."
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$PROJECT_DIR/Screenize/Info.plist"

# Increment build number (CFBundleVersion)
CURRENT_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PROJECT_DIR/Screenize/Info.plist")
NEW_BUILD=$((CURRENT_BUILD + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${NEW_BUILD}" "$PROJECT_DIR/Screenize/Info.plist"
print_step "Build number: ${CURRENT_BUILD} -> ${NEW_BUILD}"

# Release build
print_step "Performing Release build..."
xcodebuild -project "$PROJECT_DIR/Screenize.xcodeproj" \
           -scheme Screenize \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
           ARCHS="arm64 x86_64" \
           ONLY_ACTIVE_ARCH=NO \
           clean build

APP_PATH="$BUILD_DIR/Build/Products/Release/${APP_NAME}.app"

if [ ! -d "$APP_PATH" ]; then
    print_error "Build failed: $APP_PATH not found"
    exit 1
fi

print_step "Build completed: $APP_PATH"

# Notarization (optional)
# Requires Apple Developer Program membership
# Uncomment below to use
# print_step "Notarizing..."
# xcrun notarytool submit "$APP_PATH" \
#     --apple-id "$APPLE_ID" \
#     --password "$APPLE_APP_PASSWORD" \
#     --team-id "PDRAQZHYD3" \
#     --wait
# xcrun stapler staple "$APP_PATH"

# Create DMG
print_step "Creating DMG..."
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
TEMP_DMG="$BUILD_DIR/${APP_NAME}_temp.dmg"
TEMP_DMG_DIR="$BUILD_DIR/dmg_temp"
VOLUME_NAME="$APP_NAME"
VOLUME_PATH="/Volumes/$VOLUME_NAME"
BG_IMAGE="$PROJECT_DIR/assets/screenize-dmg-background@2x.png"

# Prepare staging directory
mkdir -p "$TEMP_DMG_DIR"
cp -R "$APP_PATH" "$TEMP_DMG_DIR/"
ln -s /Applications "$TEMP_DMG_DIR/Applications"

# Create writable DMG (generous size, will be compressed later)
hdiutil create -volname "$VOLUME_NAME" \
               -srcfolder "$TEMP_DMG_DIR" \
               -ov \
               -format UDRW \
               -size 200m \
               "$TEMP_DMG"

rm -rf "$TEMP_DMG_DIR"

# Detach volume if already mounted
if [ -d "$VOLUME_PATH" ]; then
    hdiutil detach "$VOLUME_PATH" -force || true
fi

# Mount writable DMG
hdiutil attach "$TEMP_DMG" -noautoopen -nobrowse

# Prepare background image (Retina TIFF from @2x PNG)
print_step "Preparing background image..."
BG_TEMP_DIR="$BUILD_DIR/bg_temp"
mkdir -p "$BG_TEMP_DIR"
cp "$BG_IMAGE" "$BG_TEMP_DIR/2x.png"
sips --setProperty dpiWidth 144 --setProperty dpiHeight 144 "$BG_TEMP_DIR/2x.png" > /dev/null
sips -z 440 660 --setProperty dpiWidth 72 --setProperty dpiHeight 72 -s format png --out "$BG_TEMP_DIR/1x.png" "$BG_TEMP_DIR/2x.png" > /dev/null
tiffutil -catnosizecheck "$BG_TEMP_DIR/1x.png" "$BG_TEMP_DIR/2x.png" -out "$BG_TEMP_DIR/background.tiff"

# Copy background image and hide the folder
mkdir -p "$VOLUME_PATH/.background"
cp "$BG_TEMP_DIR/background.tiff" "$VOLUME_PATH/.background/background.tiff"
rm -rf "$BG_TEMP_DIR"

# Configure Finder window layout via AppleScript
print_step "Applying DMG window layout..."
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {0, 0, 660, 440}
        set theViewOptions to the icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 120
        set text size of theViewOptions to 12
        set background picture of theViewOptions to file ".background:background.tiff"
        -- Move all items off-screen first (hides .background folder)
        set position of every item to {760, 100}
        -- Then position visible items
        set position of item "${APP_NAME}.app" of container window to {180, 240}
        set position of item "Applications" of container window to {480, 240}
        close
        open
        update without registering applications
        delay 3
        close
    end tell
end tell
APPLESCRIPT

# Wait for .DS_Store to persist
sync
print_step "Waiting for .DS_Store to persist..."
for i in $(seq 1 10); do
    if [ -f "$VOLUME_PATH/.DS_Store" ]; then
        break
    fi
    sleep 1
done
sleep 2

# Detach
hdiutil detach "$VOLUME_PATH"

# Convert to compressed read-only DMG
print_step "Compressing DMG..."
hdiutil convert "$TEMP_DMG" \
               -format UDZO \
               -imagekey zlib-level=9 \
               -o "$DMG_PATH"
rm -f "$TEMP_DMG"

print_step "DMG created: $DMG_PATH"

# Sign DMG
print_step "Signing DMG..."
SIGNATURE_OUTPUT=$("$SPARKLE_TOOL_DIR/bin/sign_update" "$DMG_PATH")
echo "$SIGNATURE_OUTPUT"

# Extract signature info
ED_SIGNATURE=$(echo "$SIGNATURE_OUTPUT" | grep -o 'sparkle:edSignature="[^"]*"' | cut -d'"' -f2)
FILE_LENGTH=$(stat -f%z "$DMG_PATH")

if [ -z "$ED_SIGNATURE" ]; then
    print_error "Failed to generate signature"
    exit 1
fi

print_step "Signature complete"

# Generate/update appcast.xml
print_step "Updating appcast.xml..."
APPCAST_PATH="$PROJECT_DIR/appcast.xml"
PUB_DATE=$(date -R)
DOWNLOAD_URL="https://github.com/syi0808/screenize/releases/download/v${VERSION}/${DMG_NAME}"

# Extract build number (from Info.plist)
BUILD_NUMBER=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleVersion)

NEW_ITEM=$(cat << ITEM_EOF
        <item>
            <title>Version ${VERSION}</title>
            <sparkle:version>${BUILD_NUMBER}</sparkle:version>
            <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
            <sparkle:releaseNotesLink>
                https://github.com/syi0808/screenize/releases/tag/v${VERSION}
            </sparkle:releaseNotesLink>
            <pubDate>${PUB_DATE}</pubDate>
            <enclosure
                url="${DOWNLOAD_URL}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${FILE_LENGTH}"
                type="application/octet-stream" />
            <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
        </item>
ITEM_EOF
)

if [ -f "$APPCAST_PATH" ]; then
    # 기존 appcast.xml에 새 item 추가 (최신 버전이 위에 오도록 <language> 태그 뒤에 삽입)
    TEMP_ITEM_FILE=$(mktemp)
    echo "" > "$TEMP_ITEM_FILE"
    echo "$NEW_ITEM" >> "$TEMP_ITEM_FILE"
    sed -i '' "/<language>en<\/language>/r $TEMP_ITEM_FILE" "$APPCAST_PATH"
    rm -f "$TEMP_ITEM_FILE"
else
    # 새로 생성
    cat > "$APPCAST_PATH" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>Screenize Updates</title>
        <link>https://github.com/syi0808/screenize/releases</link>
        <description>Screenize app updates</description>
        <language>en</language>

${NEW_ITEM}
    </channel>
</rss>
EOF
fi

print_step "appcast.xml generated"

# Summary
echo ""
echo "============================================"
echo "  Release build complete!"
echo "============================================"
echo ""
echo "Generated files:"
echo "  - DMG: $DMG_PATH"
echo "  - appcast.xml: $APPCAST_PATH"
echo ""
echo "Next steps:"
echo "  1. Create a GitHub Release (tag: v${VERSION})"
echo "  2. Upload ${DMG_NAME}"
echo "  3. Commit and push appcast.xml:"
echo "     git add appcast.xml"
echo "     git commit -m 'Update appcast.xml for v${VERSION}'"
echo "     git push origin main"
echo ""
echo "Or automate the release with:"
echo "  ./scripts/release.sh ${VERSION} --publish"
echo ""
