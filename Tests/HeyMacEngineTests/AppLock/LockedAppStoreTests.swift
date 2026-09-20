import Testing
import Foundation
@testable import HeyMacEngine

private func makeStore() -> LockedAppStore {
    LockedAppStore(defaults: UserDefaults(suiteName: "applock-tests-\(UUID().uuidString)")!)
}

@Test func blacklistProtectsRecoveryToolsAndItself() {
    #expect(AppLockBlacklist.isProtected("com.apple.Terminal"))
    #expect(AppLockBlacklist.isProtected("com.apple.finder"))
    #expect(AppLockBlacklist.isProtected("com.apple.SystemSettings"))
    #expect(AppLockBlacklist.isProtected("com.apple.ActivityMonitor"))
    #expect(AppLockBlacklist.isProtected("com.heymac.app", ownBundleID: "com.heymac.app"))
    #expect(!AppLockBlacklist.isProtected("com.apple.MobileSMS", ownBundleID: "com.heymac.app"))
}

@Test func addedAppsPersistAndAreLockedOnlyWhileEnabled() {
    let store = makeStore()
    #expect(store.add(bundleID: "com.apple.MobileSMS", name: "Messages"))
    #expect(store.apps.map(\.bundleID) == ["com.apple.MobileSMS"])
    #expect(!store.isLocked("com.apple.MobileSMS")) // feature is off by default
    store.enabled = true
    #expect(store.isLocked("com.apple.MobileSMS"))
    #expect(!store.isLocked("com.apple.Notes"))
}

@Test func blacklistedAndDuplicateAppsAreRejected() {
    let store = makeStore()
    #expect(!store.add(bundleID: "com.apple.Terminal", name: "Terminal"))
    #expect(store.add(bundleID: "com.apple.Notes", name: "Notes"))
    #expect(!store.add(bundleID: "com.apple.Notes", name: "Notes"))
    #expect(store.apps.count == 1)
}

@Test func removeAndPolicyChangesPersist() {
    let store = makeStore()
    store.add(bundleID: "com.apple.Notes", name: "Notes")
    #expect(store.app("com.apple.Notes")?.policy == .afterMinutes(5))
    store.setPolicy(.everyTime, for: "com.apple.Notes")
    #expect(store.app("com.apple.Notes")?.policy == .everyTime)
    store.remove(bundleID: "com.apple.Notes")
    #expect(store.apps.isEmpty)
}
