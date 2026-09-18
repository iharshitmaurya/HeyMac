#!/bin/bash
# Builds FaceUnlock.app and a DMG in daemon/dist.
# Usage: scripts/build-app.sh [version]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DAEMON_ROOT="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$DAEMON_ROOT")"
VERSION="${1:-1.0.0}"
DIST="$DAEMON_ROOT/dist"
APP="$DIST/FaceUnlock.app"
source "$SCRIPT_DIR/lib-signing.sh"

echo "Building executables (release)..."
(cd "$DAEMON_ROOT" && swift build -c release --product FaceUnlock)
BIN="$(cd "$DAEMON_ROOT" && swift build -c release --show-bin-path)"

echo "Building the sudo PAM module..."
(cd "$REPO_ROOT/pam" && make)

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/pam"
cp "$BIN/FaceUnlock" "$APP/Contents/MacOS/FaceUnlock"
# SwiftPM's resource bundle holds the Core ML models; the app looks for it here.
cp -R "$BIN/FaceUnlockDaemon_FaceUnlockCore.bundle" "$APP/Contents/Resources/"
cp -R "$DAEMON_ROOT/Sources/FaceUnlockApp/Animations" "$APP/Contents/Resources/Animations"
cp "$REPO_ROOT/pam/pam_faceunlock.so" "$APP/Contents/Resources/pam/"
cp "$REPO_ROOT/pam/scripts/install-pam.sh" "$REPO_ROOT/pam/scripts/uninstall-pam.sh" "$APP/Contents/Resources/pam/"
sed "s/__VERSION__/$VERSION/g" "$SCRIPT_DIR/app/Info.plist" > "$APP/Contents/Info.plist"

echo "Drawing the app icon..."
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$SCRIPT_DIR/app/make-icon.swift" "$ICONSET" 2>/dev/null; then
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
else
    echo "warning: could not draw the icon; shipping without one" >&2
fi

echo "Signing..."
sign_code "$APP/Contents/Resources/pam/pam_faceunlock.so" com.faceunlock.pam
sign_code "$APP" com.faceunlock.app
codesign --verify --deep --strict "$APP"
if ! signing_identity_available; then
    echo "note: signed ad-hoc. Run scripts/create-signing-identity.sh once so permissions survive app updates." >&2
fi

echo "Building the disk image..."
STAGING="$DIST/dmg"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
cp "$SCRIPT_DIR/app/README.txt" "$STAGING/README.txt"
DMG="$DIST/FaceUnlock-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "FaceUnlock" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

"$SCRIPT_DIR/verify-app.sh" "$APP"
echo "Built $DMG"
