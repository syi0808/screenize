#!/bin/bash
set -e

# ============================================
# Sparkle bootstrap script
# Generates EdDSA keys and updates Info.plist
# ============================================

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_TOOL_DIR="$PROJECT_DIR/tools/sparkle"
INFO_PLIST="$PROJECT_DIR/Screenize/Info.plist"

# Color output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}==>${NC} $1"
}

print_info() {
    echo -e "${CYAN}Info:${NC} $1"
}

# Summary header
echo ""
echo "============================================"
echo "  Sparkle setup"
echo "============================================"
echo ""

# Sparkle tool download
if [ ! -f "$SPARKLE_TOOL_DIR/bin/generate_keys" ]; then
    print_step "Downloading Sparkle tools..."
    mkdir -p "$SPARKLE_TOOL_DIR"
    cd "$SPARKLE_TOOL_DIR"
    curl -L -o Sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz
    tar -xf Sparkle.tar.xz
    rm Sparkle.tar.xz
    cd "$PROJECT_DIR"
    print_step "Sparkle tools installed"
else
    print_info "Sparkle tools are already installed"
fi

# Check for existing key (based on exit status)
print_step "Checking for existing EdDSA key..."
if "$SPARKLE_TOOL_DIR/bin/generate_keys" -p >/dev/null 2>&1; then
    EXISTING_KEY=$("$SPARKLE_TOOL_DIR/bin/generate_keys" -p 2>/dev/null)
    echo ""
    echo -e "${YELLOW}An EdDSA key already exists in the Keychain:${NC}"
    echo "$EXISTING_KEY"
    echo ""
    read -p "Use this key? (y/n): " USE_EXISTING

if [ "$USE_EXISTING" = "y" ] || [ "$USE_EXISTING" = "Y" ]; then
        PUBLIC_KEY_VALUE="$EXISTING_KEY"
    else
        echo ""
        echo "To generate a new key, delete the existing entry from Keychain first:"
        echo "  1. Open Keychain Access"
        echo "  2. Search for 'Sparkle'"
        echo "  3. Delete the 'Sparkle EdDSA private key' item"
        echo ""
        exit 1
    fi
else
    # Generate a new key
    print_step "Generating new EdDSA key..."
    KEY_OUTPUT=$("$SPARKLE_TOOL_DIR/bin/generate_keys" 2>&1)
    echo ""
    echo "$KEY_OUTPUT"
    # Extract the value between <string> tags
    PUBLIC_KEY_VALUE=$(echo "$KEY_OUTPUT" | grep '<string>' | sed 's/.*<string>\(.*\)<\/string>.*/\1/')
fi

if [ -z "$PUBLIC_KEY_VALUE" ]; then
    echo -e "${RED}Error:${NC} Unable to extract the public key"
    exit 1
fi

echo ""
print_info "Public key: $PUBLIC_KEY_VALUE"

echo ""
print_step "Updating Info.plist..."

# Update SUPublicEDKey in Info.plist
# First check for a commented SUPublicEDKey block
if grep -q "<!-- <key>SUPublicEDKey</key> -->" "$INFO_PLIST"; then
    # Replace the commented block with the actual key
    sed -i '' "s|<!-- <key>SUPublicEDKey</key> -->|<key>SUPublicEDKey</key>|g" "$INFO_PLIST"
    sed -i '' "s|<!-- <string>YOUR_EDDSA_PUBLIC_KEY</string> -->|<string>${PUBLIC_KEY_VALUE}</string>|g" "$INFO_PLIST"
elif grep -q "<key>SUPublicEDKey</key>" "$INFO_PLIST"; then
    # Update the existing key value
    # Use plutil
    plutil -replace SUPublicEDKey -string "$PUBLIC_KEY_VALUE" "$INFO_PLIST"
else
    echo ""
    echo -e "${YELLOW}Warning:${NC} Please add SUPublicEDKey to Info.plist manually:"
    echo ""
    echo "  <key>SUPublicEDKey</key>"
    echo "  <string>${PUBLIC_KEY_VALUE}</string>"
    echo ""
fi

# Enable SUEnableAutomaticChecks
if grep -q "<key>SUEnableAutomaticChecks</key>" "$INFO_PLIST"; then
    # Change false to true
    sed -i '' '/<key>SUEnableAutomaticChecks<\/key>/{n;s/<false\/>/<true\/>/;}' "$INFO_PLIST"
fi

print_step "Setup complete!"

echo ""
echo "============================================"
echo "  Next steps"
echo "============================================"
echo ""
echo "1. Set startingUpdater to true in SparkleController.swift:"
echo "   File: Screenize/App/SparkleController.swift"
echo "   Change: startingUpdater: false → startingUpdater: true"
echo ""
echo "2. Verify SUFeedURL in Info.plist:"
echo "   Current: https://raw.githubusercontent.com/syi0808/screenize/main/appcast.xml"
echo ""
echo "3. Create a release build:"
echo "   ./scripts/release.sh <version>"
echo ""
