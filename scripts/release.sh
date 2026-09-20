#!/bin/bash
# Builds a release and the Sparkle appcast for it.
# Usage: scripts/release.sh VERSION [--publish]
#   Without --publish: builds dist/HeyMac-VERSION.dmg and dist/appcast.xml and stops.
#   With --publish:    also creates the GitHub release vVERSION with the DMG (versioned and as HeyMac.dmg)
#                      and appcast attached, so the README's download button and
#                      installed copies find the update at releases/latest/download/appcast.xml.
# The DMG is signed with the private key that `generate_keys` stored in your login Keychain;
# it must match SUPublicEDKey in packaging/Info.plist.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
VERSION="${1:?usage: release.sh VERSION [--publish]}"
PUBLISH="${2:-}"
REPO="iharshitmaurya/HeyMac"
DMG="$REPO_ROOT/dist/HeyMac-$VERSION.dmg"
LATEST_DMG="$REPO_ROOT/dist/HeyMac.dmg" # fixed name, so releases/latest/download/HeyMac.dmg always resolves
APPCAST="$REPO_ROOT/dist/appcast.xml"
SIGN_UPDATE="$REPO_ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"

"$SCRIPT_DIR/build-app.sh" "$VERSION"

echo "Signing the DMG for Sparkle..."
# Prints: sparkle:edSignature="..." length="..."
SIGNATURE_ATTRS="$("$SIGN_UPDATE" "$DMG")"
cp "$DMG" "$LATEST_DMG"

cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Hey Mac</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/HeyMac-$VERSION.dmg"
                 type="application/x-apple-diskimage" $SIGNATURE_ATTRS />
    </item>
  </channel>
</rss>
XML
echo "Wrote $APPCAST"

if [ "$PUBLISH" = "--publish" ]; then
    gh release create "v$VERSION" "$DMG" "$LATEST_DMG" "$APPCAST" --repo "$REPO" --title "Hey Mac $VERSION" --generate-notes
    echo "Published v$VERSION"
else
    echo "Not published. Re-run with --publish to create the GitHub release."
fi
