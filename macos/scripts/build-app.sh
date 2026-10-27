#!/usr/bin/env bash
# Build a local personal-use arm64 Loomings.app. Signing is ad-hoc only; this
# is not Developer ID signing and the result is not notarised.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS="$(cd "$HERE/.." && pwd)"
REPO="$(cd "$MACOS/.." && pwd)"
CONFIG="${1:-release}"
APP="$MACOS/dist/Loomings.app"

if [[ "$(uname -m)" != "arm64" ]]; then
    echo "Loomings is Apple Silicon only (host is $(uname -m))." >&2
    exit 1
fi

swift build --package-path "$MACOS" -c "$CONFIG" --product LoomingsApp
BIN_DIR="$(swift build --package-path "$MACOS" -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/LoomingsApp" "$APP/Contents/MacOS/Loomings"

VERSION="$(node -p "require('$REPO/package.json').version")"
BUILD="$(git -C "$REPO" rev-list --count HEAD 2>/dev/null || echo 1)"
sed \
    -e "s/__VERSION__/$VERSION/g" \
    -e "s/__BUILD__/$BUILD/g" \
    "$MACOS/Resources/Info.plist" > "$APP/Contents/Info.plist"

# Shared native resources: palettes, teaching material, and font files.
cp "$MACOS/Resources/palettes.json" "$APP/Contents/Resources/"
cp "$MACOS/Resources/cheatsheet.md" "$APP/Contents/Resources/"
cp "$MACOS/Resources/example.md" "$APP/Contents/Resources/"
cp -R "$MACOS/Resources/lessons" "$APP/Contents/Resources/lessons"
cp -R "$MACOS/Resources/Fonts" "$APP/Contents/Resources/Fonts"

# The native icon is built from macos/scripts/build-icon.swift in the
# Adamastor style (padded squircle + keyline). Do not generate it from the
# web/social icon exports: those are full-bleed and use a different treatment.
cp "$MACOS/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - --identifier eu.tiagojacinto.loomings.native "$APP"

echo "$APP"
