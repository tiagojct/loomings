#!/usr/bin/env bash
# Import icons from Apple Icon Composer export + pad to Apple HIG safe area.
# Source: ./icons/Icon Exports/Icon-iOS-Default-1024x1024@1x.png
# Adds 5% transparent padding so squircle visual size matches other dock icons.
# Outputs: src-tauri/icons/{icon.png, 32x32.png, 128x128.png, 128x128@2x.png, icon.icns}
# Usage: ./scripts/build-icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/icons/Icon Exports/Icon-iOS-Default-1024x1024@1x.png"
ICONS="$ROOT/src-tauri/icons"
ICONSET="/tmp/loomings.iconset"
PADDED="/tmp/loomings-padded-1024.png"
PADDER="$ROOT/scripts/pad-icon"
PADDER_SRC="$ROOT/scripts/pad-icon.swift"
SCALE="0.90"

if [[ ! -f "$SRC" ]]; then
  echo "Source not found: $SRC"
  echo "Export from Icon Composer first (File → Export → 'iOS, macOS Shared')"
  exit 1
fi

if [[ ! -x "$PADDER" || "$PADDER_SRC" -nt "$PADDER" ]]; then
  echo "compiling pad-icon..."
  swiftc -O -o "$PADDER" "$PADDER_SRC"
fi

"$PADDER" "$SRC" "$PADDED" 1024 "$SCALE"

cp "$PADDED" "$ICONS/icon.png"
sips -z 32 32   "$PADDED" --out "$ICONS/32x32.png"       > /dev/null
sips -z 128 128 "$PADDED" --out "$ICONS/128x128.png"     > /dev/null
sips -z 256 256 "$PADDED" --out "$ICONS/128x128@2x.png"  > /dev/null

rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16     "$PADDED" --out "$ICONSET/icon_16x16.png"        > /dev/null
sips -z 32 32     "$PADDED" --out "$ICONSET/icon_16x16@2x.png"     > /dev/null
sips -z 32 32     "$PADDED" --out "$ICONSET/icon_32x32.png"        > /dev/null
sips -z 64 64     "$PADDED" --out "$ICONSET/icon_32x32@2x.png"     > /dev/null
sips -z 128 128   "$PADDED" --out "$ICONSET/icon_128x128.png"      > /dev/null
sips -z 256 256   "$PADDED" --out "$ICONSET/icon_128x128@2x.png"   > /dev/null
sips -z 256 256   "$PADDED" --out "$ICONSET/icon_256x256.png"      > /dev/null
sips -z 512 512   "$PADDED" --out "$ICONSET/icon_256x256@2x.png"   > /dev/null
sips -z 512 512   "$PADDED" --out "$ICONSET/icon_512x512.png"      > /dev/null
sips -z 1024 1024 "$PADDED" --out "$ICONSET/icon_512x512@2x.png"   > /dev/null

iconutil -c icns "$ICONSET" -o "$ICONS/icon.icns"
rm -rf "$ICONSET" "$PADDED"
echo "icons rebuilt (scale=$SCALE)"
