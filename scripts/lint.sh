#!/bin/bash
# SwiftLint helper script
# Usage: ./scripts/lint.sh [--fix]

set -e

cd "$(dirname "$0")/.."

# Check if SwiftLint is available
SWIFTLINT=""

# Try SPM build directory first
SPM_SWIFTLINT="${BUILD_DIR%/Build/*}/SourcePackages/checkouts/SwiftLint/swiftlint"
if [ -f "$SPM_SWIFTLINT" ]; then
    SWIFTLINT="$SPM_SWIFTLINT"
# Try Homebrew (Apple Silicon)
elif [ -f "/opt/homebrew/bin/swiftlint" ]; then
    SWIFTLINT="/opt/homebrew/bin/swiftlint"
# Try Homebrew (Intel)
elif [ -f "/usr/local/bin/swiftlint" ]; then
    SWIFTLINT="/usr/local/bin/swiftlint"
# Try PATH
elif command -v swiftlint &> /dev/null; then
    SWIFTLINT="swiftlint"
fi

if [ -z "$SWIFTLINT" ]; then
    echo "Error: SwiftLint not found"
    echo "Install with: brew install swiftlint"
    echo "Or add SwiftLint package to your Xcode project"
    exit 1
fi

echo "Using SwiftLint: $SWIFTLINT"

if [ "$1" == "--fix" ]; then
    echo "Running SwiftLint with auto-fix..."
    "$SWIFTLINT" --fix
    echo ""
    echo "Running SwiftLint again to show remaining issues..."
fi

"$SWIFTLINT" lint
