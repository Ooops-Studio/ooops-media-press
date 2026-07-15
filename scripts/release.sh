#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:?Usage: scripts/release.sh VERSION}"
[[ -n "${SPARKLE_PUBLIC_KEY:-}" ]] || { echo "SPARKLE_PUBLIC_KEY is required" >&2; exit 1; }
command -v gh >/dev/null || { echo "GitHub CLI is required" >&2; exit 1; }

"$ROOT/scripts/package-app.sh" "$VERSION"
OUT="$ROOT/release-artifacts/$VERSION"
mkdir -p "$OUT"
cp "$ROOT/build/Ooops-Media-Press-$VERSION.zip" "$OUT/Ooops-Media-Press-$VERSION.zip"

SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_appcast" "$OUT"
cp "$OUT/appcast.xml" "$ROOT/docs/appcast.xml"

git tag -s "v$VERSION" -m "Ooops Media Press $VERSION"
git push origin "v$VERSION"
gh release create "v$VERSION" "$OUT/Ooops-Media-Press-$VERSION.zip" "$OUT/appcast.xml" \
  "$ROOT/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" --repo Ooops-Studio/ooops-media-press --title "Ooops Media Press $VERSION" --generate-notes

echo "Commit and push docs/appcast.xml after verifying the release."
