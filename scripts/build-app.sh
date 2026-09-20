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
mkdir -p "$DIST" && touch "$DIST/.metadata_never_index"  # keeps Spotlight from listing this build copy as an installed app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/HeyMac" "$APP/Contents/MacOS/HeyMac"
# SwiftPM's resource bundle holds the Core ML models; the app looks for it here.
cp -R "$BIN/HeyMac_HeyMacCore.bundle" "$APP/Contents/Resources/"
cp -R "$REPO_ROOT/Sources/HeyMacApp/Animations" "$APP/Contents/Resources/Animations"
# Sparkle (the updater) is a framework the executable loads from Contents/Frameworks.
SPARKLE="$(find "$REPO_ROOT/.build/artifacts/sparkle" -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' | head -1)"
[ -d "$SPARKLE" ] || { echo "Sparkle.framework not found; run swift build first" >&2; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
mkdir -p "$APP/Contents/Library/LaunchAgents"
cp "$PACKAGING/com.heymac.app.agent.plist" "$APP/Contents/Library/LaunchAgents/"
cp "$REPO_ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/"
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
# Inside-out: Sparkle's helpers, then the framework, then the app.
SPK="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for nested in "$SPK/XPCServices/Installer.xpc" "$SPK/XPCServices/Downloader.xpc" "$SPK/Autoupdate" "$SPK/Updater.app"; do
    [ -e "$nested" ] && sign_nested "$nested"
done
sign_nested "$APP/Contents/Frameworks/Sparkle.framework"
sign_code "$APP" com.heymac.app
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
