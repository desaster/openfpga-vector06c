#!/bin/bash
# Package the Vector-06C core for Analogue Pocket
# Creates a zip file ready to extract to the SD card root
set -e

CORE_NAME="desaster.Vector06C"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="$PROJECT_DIR/scripts"
RBF="$PROJECT_DIR/output_files/Vector-06C.rbf"
DIST="$PROJECT_DIR/dist"
BUILD_DIR="$PROJECT_DIR/output_files/package"

if [ ! -f "$RBF" ]; then
    echo "Error: $RBF not found. Run scripts/build.sh first."
    exit 1
fi

# Determine version from git
TAG=$(git -C "$PROJECT_DIR" describe --tags --exact-match HEAD 2>/dev/null || true)
if [ -n "$TAG" ]; then
    VERSION="${TAG#v}"
else
    SHORT_HASH=$(git -C "$PROJECT_DIR" rev-parse --short HEAD)
    VERSION="0.0.0-dev.${SHORT_HASH}"
    if ! git -C "$PROJECT_DIR" diff-index --quiet HEAD -- 2>/dev/null; then
        VERSION="${VERSION}.dirty"
    fi
fi

DATE=$(date +'%Y-%m-%d')
ZIP="$PROJECT_DIR/output_files/${CORE_NAME}_${VERSION}_${DATE}.zip"

echo "Packaging Vector-06C core for Analogue Pocket..."
echo "  Version: $VERSION ($DATE)"

# Clean previous package
rm -rf "$PROJECT_DIR/output_files/package"

# Create SD card directory structure
mkdir -p "$BUILD_DIR/Cores/$CORE_NAME"
mkdir -p "$BUILD_DIR/Platforms/_images"

# Reverse the bitstream
python3 "$SCRIPTS_DIR/reverse_bitstream.py" "$RBF" "$BUILD_DIR/Cores/$CORE_NAME/bitstream.rbf_r"

# Copy core definition files
cp "$DIST/Cores/$CORE_NAME/"*.json "$BUILD_DIR/Cores/$CORE_NAME/"

# Copy platform definition and image
cp "$DIST/Platforms/"*.json "$BUILD_DIR/Platforms/"
cp "$DIST/Platforms/_images/"* "$BUILD_DIR/Platforms/_images/"

# Copy assets
cp -r "$DIST/Assets" "$BUILD_DIR/"

# Patch version and date in core.json
CORE_JSON="$BUILD_DIR/Cores/$CORE_NAME/core.json"
sed -i "s/\"version\": *\"[^\"]*\"/\"version\": \"$VERSION\"/" "$CORE_JSON"
sed -i "s/\"date_release\": *\"[^\"]*\"/\"date_release\": \"$DATE\"/" "$CORE_JSON"

# Create the zip
cd "$BUILD_DIR"
zip -r "$ZIP" Assets/ Cores/ Platforms/

echo "Package created: $ZIP"
