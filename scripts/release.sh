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

# Release build
print_step "Performing Release build..."
xcodebuild -project "$PROJECT_DIR/Screenize.xcodeproj" \
           -scheme Screenize \
           -configuration Release \
           -derivedDataPath "$BUILD_DIR" \
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
TEMP_DMG_DIR="$BUILD_DIR/dmg_temp"

mkdir -p "$TEMP_DMG_DIR"
cp -R "$APP_PATH" "$TEMP_DMG_DIR/"

# Add Applications symlink
ln -s /Applications "$TEMP_DMG_DIR/Applications"

# Create DMG image
hdiutil create -volname "$APP_NAME" \
               -srcfolder "$TEMP_DMG_DIR" \
               -ov \
               -format UDZO \
               "$DMG_PATH"

rm -rf "$TEMP_DMG_DIR"

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
