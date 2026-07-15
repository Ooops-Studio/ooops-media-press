#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/Design/AppIcon/AppIcon-master.svg"
OUTPUT="$ROOT/Resources/AppIcon.icns"
RSVG_CONVERT="${RSVG_CONVERT:-$(command -v rsvg-convert || true)}"

if [[ -z "$RSVG_CONVERT" ]]; then
  echo "rsvg-convert is required. Install it with: brew install librsvg" >&2
  exit 1
fi

if ! command -v iconutil >/dev/null 2>&1; then
  echo "iconutil is required and is included with macOS." >&2
  exit 1
fi

if [[ ! -f "$SOURCE" ]]; then
  echo "Missing icon source: $SOURCE" >&2
  exit 1
fi

WORK="$(mktemp -d /tmp/ooops-media-press-icon.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET" "$(dirname "$OUTPUT")"

render() {
  local pixels="$1"
  local filename="$2"
  "$RSVG_CONVERT" --width "$pixels" --height "$pixels" --output "$ICONSET/$filename" "$SOURCE"
}

render 16 icon_16x16.png
render 32 icon_16x16@2x.png
render 32 icon_32x32.png
render 64 icon_32x32@2x.png
render 128 icon_128x128.png
render 256 icon_128x128@2x.png
render 256 icon_256x256.png
render 512 icon_256x256@2x.png
render 512 icon_512x512.png
render 1024 icon_512x512@2x.png

iconutil --convert icns --output "$OUTPUT" "$ICONSET"
echo "$OUTPUT"
