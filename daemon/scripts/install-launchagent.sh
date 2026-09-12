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

mkdir -p "$PLIST_DIR"
sed "s|__INSTALL_PATH__|$INSTALL_DIR|g" "$SCRIPT_DIR/com.faceunlock.daemon.plist" > "$PLIST_PATH"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "Installed. Run '$INSTALL_DIR/faceunlockd enroll' to enroll your face."
echo "Grant Camera access to faceunlockd when prompted on first run."
