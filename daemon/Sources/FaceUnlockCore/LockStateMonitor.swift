import Foundation

private typealias CGSessionCopyCurrentDictionaryFn = @convention(c) () -> Unmanaged<CFDictionary>?

/// Reads the current login session's dictionary via CGSessionCopyCurrentDictionary,
/// a private CoreGraphics/SkyLight API with no public header and no on-disk framework
/// stub on modern macOS (it lives only in the dyld shared cache) -- resolved at
/// runtime via dlopen/dlsym, the standard technique for this exact API.
///
/// Returns true/false if the dictionary was read successfully (true only while the
/// screen is actually locked -- the CGSSessionScreenIsLocked key is absent, not
/// false, when unlocked, which this function normalizes to false). Returns nil if
/// the API couldn't be resolved or the call failed -- callers must treat nil as
/// "unknown," never as "definitely not locked."
public func isScreenLocked() -> Bool? {
    guard let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW) else {
        return nil
    }
    defer { dlclose(handle) }

    guard let sym = dlsym(handle, "CGSessionCopyCurrentDictionary") else {
        return nil
    }

    let fn = unsafeBitCast(sym, to: CGSessionCopyCurrentDictionaryFn.self)
    guard let unmanagedDict = fn() else {
        return nil
    }
    guard let dict = unmanagedDict.takeRetainedValue() as? [String: Any] else {
        return nil
    }
    return dict["CGSSessionScreenIsLocked"] as? Bool ?? false
}
