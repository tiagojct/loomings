#!/usr/bin/env bash
# Import icons from Apple Icon Composer export + pad + delegate to tauri-cli for all platforms.
# Source: ./icons/Icon Exports/Icon-iOS-Default-1024x1024@1x.png
# Outputs full set: PNG sizes, .ico (Windows), .icns (macOS).
# Usage: ./scripts/build-icons.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/icons/Icon Exports/Icon-iOS-Default-1024x1024@1x.png"
ICONS="$ROOT/src-tauri/icons"
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

# Let Tauri CLI generate full platform icon set (.ico, .icns, sized PNGs).
# Outputs all into src-tauri/icons/.
"$ROOT/node_modules/.bin/tauri" icon "$PADDED" --output "$ICONS"

# Drop mobile-only assets (Tauri produces them; we don't need them for desktop).
rm -rf "$ICONS/android" "$ICONS/ios" "$ICONS"/Square*.png "$ICONS/StoreLogo.png"

rm -f "$PADDED"
echo "icons rebuilt (scale=$SCALE, all platforms)"
