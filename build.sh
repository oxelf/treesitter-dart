#!/usr/bin/env bash
set -e

VERSION="$1"
if [[ -z "$VERSION" ]]; then
  echo "Usage: $0 <tree-sitter-version>"
  echo "Example: $0 0.25.6"
  exit 1
fi

REPO="https://github.com/tree-sitter/tree-sitter"
DIR="tree-sitter"
OUTPUT_DIR="$(pwd)/output"
BASE_DIR="$(pwd)"
XCFRAMEWORK_NAME="TreeSitter.xcframework"

echo "[+] Cleaning output directory..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "[+] Cloning Tree-sitter..."
rm -rf "$DIR"
git clone --depth=1 --branch "v$VERSION" "$REPO"
cd "$DIR/lib/src"

CFLAGS="-fPIC"
INCLUDES="-I../include"

# Compile for macOS
echo "[+] Building macOS static library..."
MACOS_BUILD_DIR="$OUTPUT_DIR/macos"
mkdir -p "$MACOS_BUILD_DIR"
clang $CFLAGS -arch arm64 -arch x86_64 $INCLUDES -c lib.c -o "$MACOS_BUILD_DIR/libtree-sitter-macos.o"
libtool -static "$MACOS_BUILD_DIR/libtree-sitter-macos.o" -o "$MACOS_BUILD_DIR/libtree-sitter-macos.a"

# Compile for iOS device
echo "[+] Building iOS (device) static library..."
IOS_BUILD_DIR="$OUTPUT_DIR/ios"
mkdir -p "$IOS_BUILD_DIR"
xcrun --sdk iphoneos clang $CFLAGS -arch arm64 -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" $INCLUDES -c lib.c -o "$IOS_BUILD_DIR/libtree-sitter-ios.o"
libtool -static "$IOS_BUILD_DIR/libtree-sitter-ios.o" -o "$IOS_BUILD_DIR/libtree-sitter-ios.a"

# Compile for iOS simulator (arm64 + x86_64)
echo "[+] Building iOS Simulator static library..."
SIM_BUILD_DIR="$(pwd)/../../../sim"
mkdir -p "$SIM_BUILD_DIR"
xcrun --sdk iphonesimulator clang $CFLAGS -arch arm64 -arch x86_64 -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" $INCLUDES -c lib.c -o "$SIM_BUILD_DIR/libtree-sitter-sim.o"
libtool -static "$SIM_BUILD_DIR/libtree-sitter-sim.o" -o "$SIM_BUILD_DIR/libtree-sitter-sim.a"

cd ../../../

# Create .xcframework
echo "[+] Creating .xcframework..."
rm -rf "$OUTPUT_DIR/$XCFRAMEWORK_NAME"
xcodebuild -create-xcframework \
  -library "$IOS_BUILD_DIR/libtree-sitter-ios.a" -headers "$DIR/lib/include" \
  -library "$SIM_BUILD_DIR/libtree-sitter-sim.a" -headers "$DIR/lib/include" \
  -library "$MACOS_BUILD_DIR/libtree-sitter-macos.a" -headers "$DIR/lib/include" \
  -output "$OUTPUT_DIR/$XCFRAMEWORK_NAME"

# Cleanup build dirs
rm -rf "$MACOS_BUILD_DIR" "$IOS_BUILD_DIR" "$SIM_BUILD_DIR" "$DIR"

# Download prebuilt binaries for other platforms
echo "[+] Downloading prebuilt binaries..."

BASE_URL="https://github.com/tree-sitter/tree-sitter/releases/download/v$VERSION"

curl -L "$BASE_URL/tree-sitter-windows-x64.gz" -o "$OUTPUT_DIR/tree-sitter-windows-x64.gz"
gunzip -f "$OUTPUT_DIR/tree-sitter-windows-x64.gz"

curl -L "$BASE_URL/tree-sitter-linux-x64.gz" -o "$OUTPUT_DIR/tree-sitter-linux-x64.gz"
gunzip -f "$OUTPUT_DIR/tree-sitter-linux-x64.gz"

curl -L "$BASE_URL/web-tree-sitter.js" -o "$OUTPUT_DIR/web-tree-sitter.js"
curl -L "$BASE_URL/web-tree-sitter.wasm" -o "$OUTPUT_DIR/web-tree-sitter.wasm"

cp  -R $OUTPUT_DIR/TreeSitter.xcframework "$BASE_DIR/macos/TreeSitter.xcframework"
cp  -R $OUTPUT_DIR/TreeSitter.xcframework "$BASE_DIR/ios/TreeSitter.xcframework"

echo "[✓] Done. Output is in: $OUTPUT_DIR"
