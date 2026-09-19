import AppKit

struct TrackedWindow: Equatable {
    let number: CGWindowID
    let layer: Int
    /// AppKit coordinates (origin bottom-left of the primary display).
    let frame: CGRect
}

/// Reads another process's on-screen windows from the window server. Owner, layer, number
/// and bounds are available without Screen Recording permission (titles are not).
enum WindowTracker {
    /// Windows of `pid`, front-to-back.
    static func windows(forPID pid: pid_t) -> [TrackedWindow] {
        guard pid != ProcessInfo.processInfo.processIdentifier,
              let primaryHeight = NSScreen.screens.first?.frame.height,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var result: [TrackedWindow] = []
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  (0...200).contains(layer),
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: boundsDict),
                  b.width >= 40, b.height >= 40
            else { continue }
            let frame = CGRect(x: b.minX, y: primaryHeight - (b.minY + b.height), width: b.width, height: b.height)
            result.append(TrackedWindow(number: number, layer: layer, frame: frame))
        }
        return result
    }
}
