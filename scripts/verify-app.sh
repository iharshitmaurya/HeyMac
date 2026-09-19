#!/bin/bash
# Checks a built HeyMac.app: contents, signature, and that the models really load.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="${1:-$(dirname "$SCRIPT_DIR")/dist/HeyMac.app}"
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -d "$APP" ] || fail "no app at $APP"
for path in \
    Contents/MacOS/HeyMac \
    Contents/Info.plist \
    Contents/Resources/FaceUnlockDaemon_FaceUnlockCore.bundle \
    Contents/Resources/Animations/unlockstatic.png \
    Contents/Resources/Animations/unlockanimation.mp4 \
    Contents/Resources/Animations/unsuccessfulunlockanimation.mp4 \
    Contents/Resources/uninstall-sudo-hook.sh \
    Contents/Library/LaunchAgents/com.faceunlock.app.agent.plist
do
    [ -e "$APP/$path" ] || fail "missing $path"
done

codesign --verify --deep --strict "$APP" || fail "signature does not verify"
[ "$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "$APP/Contents/Info.plist")" = "true" ] || fail "LSUIElement is not set (the app would show a Dock icon)"
/usr/libexec/PlistBuddy -c 'Print :NSCameraUsageDescription' "$APP/Contents/Info.plist" >/dev/null || fail "no camera usage description"

bash -n "$APP/Contents/Resources/uninstall-sudo-hook.sh" || fail "uninstall-sudo-hook.sh is not valid shell"

"$APP/Contents/MacOS/HeyMac" --self-check || fail "self-check failed"

echo "OK: $APP"
