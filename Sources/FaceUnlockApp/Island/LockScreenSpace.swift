import AppKit

/// Puts a window on the real macOS lock screen.
///
/// Ordinary windows — even at `.screenSaver` level — cannot draw over the lock screen;
/// it runs in a protected window-server space of its own. The only known way around
/// that is a private, undocumented SkyLight (window server) API: create a space, raise
/// it to the same level Notification Center itself uses while locked, and move a
/// window's ID into that space.
///
/// This is not a supported API. `dlopen`/`dlsym` resolve four C symbols with no public
/// header and no stability guarantee — Apple can rename, resandbox, or remove any of
/// them in a point release with no notice, and shipping code that calls them would
/// disqualify Mac App Store distribution. `LockScreenSpace()` returns `nil` the moment
/// any symbol fails to resolve, so a caller's fallback is always "no lock-screen
/// visibility," never a crash. This same technique (and level value) is published in
/// Lakr233/SkyLightWindow (MIT) and is how other on-device face-unlock utilities
/// achieve the same effect.
struct LockScreenSpace {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias CreateSpace = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SetSpaceLevel = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias RevealSpaces = @convention(c) (Int32, CFArray) -> Int32
    private typealias MoveWindowsIn = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32
    private typealias MoveWindowsOut = @convention(c) (Int32, CFArray, CFArray) -> Int32

    /// The absolute window-server level Notification Center's own panel uses while the
    /// screen is locked — one step above the plain "screen lock" level, which is why
    /// that lower level isn't enough on its own.
    private static let lockScreenPanelLevel: Int32 = 400

    private let connectionID: Int32
    private let spaceID: Int32
    private let moveIn: MoveWindowsIn
    private let moveOut: MoveWindowsOut

    init?() {
        guard let library = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW
        ) else { return nil }

        func resolve<T>(_ name: String, as _: T.Type) -> T? {
            dlsym(library, name).map { unsafeBitCast($0, to: T.self) }
        }

        guard
            let mainConnection = resolve("SLSMainConnectionID", as: MainConnection.self),
            let createSpace = resolve("SLSSpaceCreate", as: CreateSpace.self),
            let setSpaceLevel = resolve("SLSSpaceSetAbsoluteLevel", as: SetSpaceLevel.self),
            let revealSpaces = resolve("SLSShowSpaces", as: RevealSpaces.self),
            let moveIn = resolve("SLSSpaceAddWindowsAndRemoveFromSpaces", as: MoveWindowsIn.self),
            let moveOut = resolve("SLSRemoveWindowsFromSpaces", as: MoveWindowsOut.self)
        else { return nil }

        self.moveIn = moveIn
        self.moveOut = moveOut

        connectionID = mainConnection()
        // Type 1 is required here: any other space type makes Finder paint desktop
        // icons into it.
        spaceID = createSpace(connectionID, 1, 0)
        _ = setSpaceLevel(connectionID, spaceID, Self.lockScreenPanelLevel)
        _ = revealSpaces(connectionID, [spaceID] as CFArray)
    }

    /// Moves `window` into the lock-screen-visible space. Only meaningful while the
    /// screen is actually locked.
    func show(_ window: NSWindow) {
        _ = moveIn(connectionID, spaceID, [window.windowNumber] as CFArray, 7)
    }

    /// Returns `window` to ordinary window-server behavior. Call this as soon as the
    /// screen unlocks — nothing should stay pinned to the lock-screen space afterward.
    func hide(_ window: NSWindow) {
        _ = moveOut(connectionID, [window.windowNumber] as CFArray, [spaceID] as CFArray)
    }
}
