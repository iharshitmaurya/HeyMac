#!/bin/bash
set -euo pipefail

INSTALL_DIR="$HOME/Library/Application Support/faceunlock/bin"
PLIST_DIR="$HOME/Library/LaunchAgents"
PLIST_PATH="$PLIST_DIR/com.faceunlock.daemon.plist"
LABEL="com.faceunlock.daemon"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Building faceunlockd (release)..."
(cd "$DAEMON_ROOT" && swift build -c release)

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

mkdir -p "$INSTALL_DIR"
cp "$DAEMON_ROOT/.build/release/faceunlockd" "$INSTALL_DIR/faceunlockd"
# SwiftPM emits a resource bundle beside the executable (holds the vendored .mlpkgdata
# models); Bundle.module's generated accessor looks for it next to the executable and
# fatalErrors if it's missing, so it must be copied alongside the binary.
for bundle in "$DAEMON_ROOT"/.build/release/*.bundle; do
    [ -e "$bundle" ] || continue
    rm -rf "$INSTALL_DIR/$(basename "$bundle")"
    cp -R "$bundle" "$INSTALL_DIR/"
done
# A stable identifier (matching the embedded Info.plist) for Camera/Accessibility prompts.
codesign --force --sign - --identifier com.faceunlock.daemon "$INSTALL_DIR/faceunlockd"

mkdir -p "$PLIST_DIR"
sed "s|__INSTALL_PATH__|$INSTALL_DIR|g" "$SCRIPT_DIR/com.faceunlock.daemon.plist" > "$PLIST_PATH"
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

BIN="$INSTALL_DIR/faceunlockd"
cat <<EOF
Installed and started. Daemon log: /tmp/faceunlockd.err

Next steps (run in Terminal):
  1. "$BIN" enroll          # allow Camera when asked; look at the camera
  2. "$BIN" verify          # should print OK; shows per-frame scores
  3. "$BIN" set-password    # only if you want lock-screen unlock
  4. Lock-screen unlock also needs System Settings > Privacy & Security > Accessibility
     to include: $BIN   (re-add it after every reinstall; the signature changes)
EOF
