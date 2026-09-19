# FaceUnlock

A macOS menu-bar app that unlocks your Mac's lock screen with your face and can lock chosen apps behind Face ID, Touch ID or your password. A notch "island" overlay shows scan progress.

- **Lock-screen unlock** — on-device face recognition (Core ML) with anti-spoofing; the embedding is stored encrypted in the Keychain.
- **App Lock** — pick apps; they are blurred until you authenticate. Choose a whole-screen or locked-app-only shield and a relock policy per app.

Requires macOS 14+.

## Layout

```
Package.swift
Sources/
  FaceUnlockCore/     recognition (ArcFace, anti-spoof), Keychain/secure storage, lock-state monitors
  FaceUnlockEngine/   camera, enrollment, verification, lock-screen unlocker, App Lock logic
  FaceUnlockApp/      SwiftUI/AppKit app
    App/  MenuBar/  Settings/  Setup/  AppLock/  Island/  DesignSystem/  Debug/  Animations/
Tests/                unit tests per module
scripts/              build-app.sh, verify-app.sh, signing helpers
packaging/            Info.plist, LaunchAgent plist, icon generator, DMG readme
tools/                throwaway spikes
```

## Build

```sh
swift build --product FaceUnlock      # dev build
scripts/create-signing-identity.sh    # once: stable signing so permissions survive rebuilds
scripts/build-app.sh 1.0.0            # dist/FaceUnlock.app and a DMG
```

`swift run FaceUnlock --render-ui <dir>` renders the app's screens to PNG.
