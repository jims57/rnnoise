#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RNNOISE_SRC="$SCRIPT_DIR"
BUILD_DIR="$SCRIPT_DIR/build"
FRAMEWORK_NAME="RNNoise"
FRAMEWORK_VERSION="A"

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

# Build architectures for iOS and iOS Simulator
function build_for_arch() {
    PLATFORM=$1
    ARCH=$2
    SDK=$3
    OUT_DIR="$BUILD_DIR/$PLATFORM-$ARCH"
    
    echo "Building for $PLATFORM $ARCH..."
    mkdir -p "$OUT_DIR"
    
    # Get SDK path
    SDKPATH=$(xcrun -sdk $SDK --show-sdk-path)
    
    # Configure compiler flags
    export CFLAGS="-arch $ARCH -isysroot $SDKPATH -miphoneos-version-min=11.0"
    export LDFLAGS="-arch $ARCH -isysroot $SDKPATH"
    
    if [ "$PLATFORM" = "simulator" ]; then
        CFLAGS="$CFLAGS -mios-simulator-version-min=11.0"
    fi
    
    # Configure and build
    cd "$SCRIPT_DIR"
    ./configure --host=$ARCH-apple-darwin --prefix="$OUT_DIR" --enable-static --disable-shared --disable-examples || true
    make clean || true
    make -j8
    make install
}

# Build for iOS device architectures
build_for_arch "ios" "arm64" "iphoneos"

# Build for iOS Simulator architectures
build_for_arch "simulator" "arm64" "iphonesimulator"
build_for_arch "simulator" "x86_64" "iphonesimulator"

# Create fat libraries for simulator
mkdir -p "$BUILD_DIR/simulator-fat/lib"
lipo -create "$BUILD_DIR/simulator-arm64/lib/librnnoise.a" "$BUILD_DIR/simulator-x86_64/lib/librnnoise.a" -output "$BUILD_DIR/simulator-fat/lib/librnnoise.a"
cp -R "$BUILD_DIR/simulator-arm64/include" "$BUILD_DIR/simulator-fat/"

# Create device framework
FRAMEWORK_DIR="$BUILD_DIR/$FRAMEWORK_NAME.framework"
rm -rf "$FRAMEWORK_DIR"
mkdir -p "$FRAMEWORK_DIR/Versions/$FRAMEWORK_VERSION/Headers"
mkdir -p "$FRAMEWORK_DIR/Versions/$FRAMEWORK_VERSION/Resources"

# Create symlinks
ln -s "$FRAMEWORK_VERSION" "$FRAMEWORK_DIR/Versions/Current"
ln -s "Versions/Current/Headers" "$FRAMEWORK_DIR/Headers"
ln -s "Versions/Current/Resources" "$FRAMEWORK_DIR/Resources"
ln -s "Versions/Current/$FRAMEWORK_NAME" "$FRAMEWORK_DIR/$FRAMEWORK_NAME"

# Copy headers
cp -R "$BUILD_DIR/ios-arm64/include/rnnoise.h" "$FRAMEWORK_DIR/Headers/"

# Create module map
cat > "$FRAMEWORK_DIR/Headers/module.modulemap" << EOF
framework module $FRAMEWORK_NAME {
  header "rnnoise.h"
  export *
}
EOF

# Create Info.plist
cat > "$FRAMEWORK_DIR/Resources/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>org.xiph.$FRAMEWORK_NAME</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$FRAMEWORK_NAME</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>11.0</string>
</dict>
</plist>
EOF

# Copy iOS library to framework
cp "$BUILD_DIR/ios-arm64/lib/librnnoise.a" "$FRAMEWORK_DIR/Versions/Current/$FRAMEWORK_NAME"

# Create simulator framework
SIM_FRAMEWORK_DIR="$BUILD_DIR/$FRAMEWORK_NAME-simulator.framework"
rm -rf "$SIM_FRAMEWORK_DIR"
mkdir -p "$SIM_FRAMEWORK_DIR/Versions/$FRAMEWORK_VERSION/Headers"
mkdir -p "$SIM_FRAMEWORK_DIR/Versions/$FRAMEWORK_VERSION/Resources"

# Create symlinks for simulator framework
ln -s "$FRAMEWORK_VERSION" "$SIM_FRAMEWORK_DIR/Versions/Current"
ln -s "Versions/Current/Headers" "$SIM_FRAMEWORK_DIR/Headers"
ln -s "Versions/Current/Resources" "$SIM_FRAMEWORK_DIR/Resources"
ln -s "Versions/Current/$FRAMEWORK_NAME" "$SIM_FRAMEWORK_DIR/$FRAMEWORK_NAME"

# Copy headers and resources to simulator framework
cp -R "$BUILD_DIR/simulator-fat/include/rnnoise.h" "$SIM_FRAMEWORK_DIR/Headers/"
cp "$FRAMEWORK_DIR/Headers/module.modulemap" "$SIM_FRAMEWORK_DIR/Headers/"
cp "$FRAMEWORK_DIR/Resources/Info.plist" "$SIM_FRAMEWORK_DIR/Resources/"

# Copy simulator library to framework
cp "$BUILD_DIR/simulator-fat/lib/librnnoise.a" "$SIM_FRAMEWORK_DIR/Versions/Current/$FRAMEWORK_NAME"

# Create XCFramework
XCFRAMEWORK_PATH="$BUILD_DIR/$FRAMEWORK_NAME.xcframework"
rm -rf "$XCFRAMEWORK_PATH"

xcodebuild -create-xcframework \
    -framework "$FRAMEWORK_DIR" \
    -framework "$SIM_FRAMEWORK_DIR" \
    -output "$XCFRAMEWORK_PATH"

echo "XCFramework created at $XCFRAMEWORK_PATH"