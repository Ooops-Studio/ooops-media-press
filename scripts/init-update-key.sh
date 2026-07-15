#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift package --package-path "$ROOT" resolve
"$ROOT/.build/artifacts/sparkle/Sparkle/bin/generate_keys"
echo "Keep the private key in Keychain/offline backup. Export only the printed public key as SPARKLE_PUBLIC_KEY."
