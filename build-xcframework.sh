#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RNNOISE_SRC="$SCRIPT_DIR"
BUILD_DIR="$SCRIPT_DIR/build"
FRAMEWORK_NAME="RNNoise"

# Install autotools dependencies if not already installed
which autoconf >/dev/null || brew install autoconf
which automake >/dev/null || brew install automake
which libtool >/dev/null || brew install libtool

# Make autogen.sh executable if it exists
if [ -f "$SCRIPT_DIR/autogen.sh" ]; then
    chmod +x "$SCRIPT_DIR/autogen.sh"
    "$SCRIPT_DIR/autogen.sh"
else
    echo "autogen.sh not found, trying alternate approach"
    # If no autogen.sh, try standard autoconf approach
    if [ ! -f "$SCRIPT_DIR/configure" ]; then
        cd "$SCRIPT_DIR"
        autoreconf -i
    fi
fi

# Make sure the build directory exists
mkdir -p "$BUILD_DIR"

# Build for iOS device architecture (arm64)
OUT_DIR="$BUILD_DIR/ios-arm64"
echo "Building for iOS arm64..."
mkdir -p "$OUT_DIR"

# Get SDK path
SDKPATH=$(xcrun -sdk iphoneos --show-sdk-path)

# Configure compiler flags
export CFLAGS="-arch arm64 -isysroot $SDKPATH -miphoneos-version-min=11.0"
export LDFLAGS="-arch arm64 -isysroot $SDKPATH"

# Configure and build
cd "$SCRIPT_DIR"
./configure --host=arm64-apple-darwin --prefix="$OUT_DIR" --enable-static --disable-shared --disable-examples || true
make clean || true
make -j8
make install

# Create iOS framework
echo "Creating iOS framework..."
mkdir -p "$BUILD_DIR/ios-framework"
cp "$BUILD_DIR/ios-arm64/lib/librnnoise.a" "$BUILD_DIR/ios-framework/librnnoise.a"
cp -R "$BUILD_DIR/ios-arm64/include" "$BUILD_DIR/ios-framework/"

# Create XCFramework
XCFRAMEWORK_PATH="$BUILD_DIR/$FRAMEWORK_NAME.xcframework"
rm -rf "$XCFRAMEWORK_PATH"

echo "Creating XCFramework..."
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/ios-framework/librnnoise.a" -headers "$BUILD_DIR/ios-framework/include" \
    -output "$XCFRAMEWORK_PATH"

echo "XCFramework created at $XCFRAMEWORK_PATH"