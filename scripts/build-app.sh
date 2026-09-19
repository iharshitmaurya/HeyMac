#!/bin/bash
# Builds HeyMac.app and a DMG in dist.
# Usage: scripts/build-app.sh [version]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGING="$(dirname "$SCRIPT_DIR")/packaging"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION="${1:-1.0.0}"
DIST="$REPO_ROOT/dist"
APP="$DIST/HeyMac.app"
source "$SCRIPT_DIR/lib-signing.sh"

echo "Building executables (release)..."
(cd "$REPO_ROOT" && swift build -c release --product HeyMac)
BIN="$(cd "$REPO_ROOT" && swift build -c release --show-bin-path)"

echo "Assembling $APP..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/HeyMac" "$APP/Contents/MacOS/HeyMac"
# SwiftPM's resource bundle holds the Core ML models; the app looks for it here.
cp -R "$BIN/FaceUnlockDaemon_FaceUnlockCore.bundle" "$APP/Contents/Resources/"
cp -R "$REPO_ROOT/Sources/FaceUnlockApp/Animations" "$APP/Contents/Resources/Animations"
mkdir -p "$APP/Contents/Library/LaunchAgents"
cp "$PACKAGING/com.faceunlock.app.agent.plist" "$APP/Contents/Library/LaunchAgents/"
# One-time cleanup of the sudo hook that older versions installed (run by the app on first launch).
cp "$PACKAGING/uninstall-sudo-hook.sh" "$APP/Contents/Resources/"
sed "s/__VERSION__/$VERSION/g" "$PACKAGING/Info.plist" > "$APP/Contents/Info.plist"

echo "Drawing the app icon..."
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
if swift "$PACKAGING/make-icon.swift" "$ICONSET" 2>/dev/null; then
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
else
    echo "warning: could not draw the icon; shipping without one" >&2
fi

echo "Signing..."
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
cp "$PACKAGING/README.txt" "$STAGING/README.txt"
DMG="$DIST/HeyMac-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Hey Mac" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"

"$SCRIPT_DIR/verify-app.sh" "$APP"
echo "Built $DMG"
