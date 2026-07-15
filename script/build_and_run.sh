#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Ooops Media Press"
PROCESS_NAME="OoopsMediaPress"
BUNDLE_ID="studio.ooops.OoopsMediaPress"
VERSION="${APP_VERSION:-0.1.0}"
ARCHIVE="$ROOT_DIR/build/Ooops-Media-Press-$VERSION.zip"
RUNTIME_DIR="/tmp/ooops-media-press-run"
APP_BUNDLE="$RUNTIME_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$PROCESS_NAME"

pkill -x "$PROCESS_NAME" >/dev/null 2>&1 || true
"$ROOT_DIR/scripts/package-app.sh" "$VERSION"
rm -rf "$RUNTIME_DIR"
mkdir -p "$RUNTIME_DIR"
ditto -x -k --noqtn "$ARCHIVE" "$RUNTIME_DIR"
xattr -cr "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    for _ in {1..20}; do
      if pgrep -x "$PROCESS_NAME" >/dev/null; then
        exit 0
      fi
      sleep 0.25
    done
    echo "$APP_NAME did not remain running after launch." >&2
    exit 1
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
