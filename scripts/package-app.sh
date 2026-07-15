#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$ROOT/Support/Info.plist")}"
FINAL_ZIP="$ROOT/build/Ooops-Media-Press-$VERSION.zip"
STAGING="$(mktemp -d /tmp/ooops-media-press.XXXXXX)"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Ooops Media Press.app"

swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Tools" "$APP/Contents/Frameworks"
cp "$BIN_DIR/OoopsMediaPress" "$APP/Contents/MacOS/"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/"
cp -R "$BIN_DIR/OoopsMediaPress_OoopsMediaPress.bundle" "$APP/Contents/Resources/"
cp -R "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/"
cp "$ROOT/Sources/OoopsMediaPress/Resources/Tools/ffmpeg" "$APP/Contents/Resources/Tools/"
cp "$ROOT/Sources/OoopsMediaPress/Resources/Tools/ffprobe" "$APP/Contents/Resources/Tools/"
rm -f "$APP/Contents/Resources/OoopsMediaPress_OoopsMediaPress.bundle/ffmpeg" "$APP/Contents/Resources/OoopsMediaPress_OoopsMediaPress.bundle/ffprobe"
cp "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/OoopsMediaPress" 2>/dev/null || true
xattr -cr "$APP"
xattr -cr "$APP/Contents/Resources/OoopsMediaPress_OoopsMediaPress.bundle"
xattr -cr "$APP/Contents/Frameworks/Sparkle.framework"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$APP/Contents/Info.plist"

codesign --force --sign - "$APP/Contents/Resources/Tools/ffmpeg"
codesign --force --sign - "$APP/Contents/Resources/Tools/ffprobe"
find "$APP/Contents/Frameworks/Sparkle.framework" -depth \( -name '*.xpc' -o -name '*.app' \) -print0 | while IFS= read -r -d '' item; do
  codesign --force --sign - --preserve-metadata=entitlements "$item"
done
codesign --force --sign - "$APP/Contents/Frameworks/Sparkle.framework"
xattr -cr "$APP/Contents/Resources/OoopsMediaPress_OoopsMediaPress.bundle"
xattr -cr "$APP/Contents/Frameworks/Sparkle.framework"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
xattr -cr "$APP/Contents/Resources/OoopsMediaPress_OoopsMediaPress.bundle"
xattr -cr "$APP/Contents/Frameworks/Sparkle.framework"
xattr -d com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -d 'com.apple.fileprovider.fpfs#P' "$APP" 2>/dev/null || true
codesign --verify --strict --verbose=2 "$APP"

rm -rf "$ROOT/build/Ooops Media Press.app" "$FINAL_ZIP"
ditto --norsrc --noextattr --noqtn --noacl -c -k --keepParent "$APP" "$FINAL_ZIP"
echo "$FINAL_ZIP"
