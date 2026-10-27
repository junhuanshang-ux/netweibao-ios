#!/usr/bin/env bash
# Build an unsigned (ad-hoc signed) IPA on macOS.
# Usage: ./scripts/build-ipa.sh
# Output: dist/NetWeiBao-unsigned.ipa

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="NetWeiBao"
SCHEME="NetWeiBao"
CONFIG="Release"
BUILD_DIR="$ROOT/build"
PRODUCT_DIR="$BUILD_DIR/Products"
DIST_DIR="$ROOT/dist"

cd "$ROOT"

echo "==> Toolchain"
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version

echo "==> Build"
rm -rf "$BUILD_DIR"
xcodebuild \
  -project NetWeiBao.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIR" \
  CONFIGURATION_BUILD_DIR="$PRODUCT_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP_DIR="$PRODUCT_DIR/$APP_NAME.app"
test -d "$APP_DIR"

echo "==> Package"
rm -rf "$BUILD_DIR/out"
mkdir -p "$BUILD_DIR/out/Payload" "$DIST_DIR"
cp -R "$APP_DIR" "$BUILD_DIR/out/Payload/"
codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT/NetWeiBao/App/NetWeiBao.entitlements" \
  "$BUILD_DIR/out/Payload/$APP_NAME.app"
( cd "$BUILD_DIR/out" && zip -qry "$DIST_DIR/$APP_NAME-unsigned.ipa" Payload )
shasum -a 256 "$DIST_DIR/$APP_NAME-unsigned.ipa" | tee "$DIST_DIR/$APP_NAME-unsigned.ipa.sha256"

echo
echo "Done: $DIST_DIR/$APP_NAME-unsigned.ipa"
echo "Install with Sideloadly / AltStore (re-sign with your Apple ID)."
