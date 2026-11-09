import Foundation

/// Persists non-sensitive Lock Screen activity for the Overview page.
struct LockScreenActivityStore {
    private enum Key {
        static let unlockCount = "activity.lockScreenUnlocksToday.count"
        static let unlockDay = "activity.lockScreenUnlocksToday.day"
        static let lastEvent = "activity.lastLockScreenEvent"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var dayKey = ""
    private(set) var unlocksToday = 0
    private(set) var lastEvent = "no checks yet"

    init(defaults: UserDefaults = .standard, calendar: Calendar = .current) {
        self.defaults = defaults
        self.calendar = calendar
    }

    mutating func restore(at date: Date = .now) {
        dayKey = Self.localDayKey(for: date, calendar: calendar)
        if defaults.string(forKey: Key.unlockDay) == dayKey {
            unlocksToday = max(0, defaults.integer(forKey: Key.unlockCount))
        } else {
            unlocksToday = 0
            persistCount(for: dayKey)
        }
        lastEvent = defaults.string(forKey: Key.lastEvent) ?? "no checks yet"
    }

    mutating func refreshDay(at date: Date = .now) {
        let today = Self.localDayKey(for: date, calendar: calendar)
        guard today != dayKey else { return }
        dayKey = today
        unlocksToday = 0
        persistCount(for: today)
    }

    mutating func recordUnlock(at date: Date = .now) {
        refreshDay(at: date)
        unlocksToday += 1
        persistCount(for: dayKey)
    }

    mutating func recordEvent(_ event: String) {
        lastEvent = event
        defaults.set(event, forKey: Key.lastEvent)
    }

    private func persistCount(for day: String) {
        defaults.set(unlocksToday, forKey: Key.unlockCount)
        defaults.set(day, forKey: Key.unlockDay)
    }

    private static func localDayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
