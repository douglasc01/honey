#!/bin/bash
# Builds a distributable Honey.app: a universal (Apple Silicon + Intel) binary,
# ad-hoc signed across the whole bundle, zipped for sharing (Route A).
#
# Recipients must clear the quarantine flag on first run — see README.md.
set -euo pipefail
cd "$(dirname "$0")"

APP="Honey.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
DIST="dist"
DEPLOY="13.0"

rm -rf "$APP" "$DIST"
mkdir -p "$MACOS" "$RES" "$DIST"

echo "Compiling arm64…"
swiftc -O -swift-version 5 -target "arm64-apple-macosx$DEPLOY" \
    Sources/Honey/*.swift -o "/tmp/honey-arm64"

echo "Compiling x86_64…"
swiftc -O -swift-version 5 -target "x86_64-apple-macosx$DEPLOY" \
    Sources/Honey/*.swift -o "/tmp/honey-x86_64"

echo "Creating universal binary…"
lipo -create "/tmp/honey-arm64" "/tmp/honey-x86_64" -output "$MACOS/Honey"
rm -f "/tmp/honey-arm64" "/tmp/honey-x86_64"

cp Sources/Honey/Resources/honey-and-bagel.json "$RES/"
cp Info.plist "$CONTENTS/Info.plist"

echo "Signing (ad-hoc, full bundle)…"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP" && echo "signature OK"

echo "Zipping…"
ditto -c -k --keepParent "$APP" "$DIST/Honey-macOS.zip"

echo
echo "Built universal: $(lipo -archs "$MACOS/Honey")"
echo "Artifact: $DIST/Honey-macOS.zip"
