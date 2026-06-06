#!/bin/bash
# Builds Honey.app directly with swiftc (SwiftPM's manifest tooling is broken in
# this Command Line Tools install, so we assemble the .app bundle by hand).
set -euo pipefail
cd "$(dirname "$0")"

APP="Honey.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "Compiling…"
swiftc -O -swift-version 5 \
    Sources/Honey/*.swift \
    -o "$MACOS/Honey"

cp Sources/Honey/Resources/honey-and-bagel.json "$RES/"
cp Info.plist "$CONTENTS/Info.plist"

echo "Built $APP"
