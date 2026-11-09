import Foundation

/// Persists non-sensitive Lock Screen activity for the Overview page.
struct LockScreenActivityStore {
    enum Event: String {
        case scanning, unlocked, passwordRejected, noMatch, noFace, scanEnded

        var messageKey: String {
            switch self {
            case .scanning: return "Lock Screen scanning at %@"
            case .unlocked: return "Lock Screen unlocked at %@"
            case .passwordRejected: return "Saved password rejected at %@"
            case .noMatch: return "Face not recognized at %@"
            case .noFace: return "No face detected at %@"
            case .scanEnded: return "Lock Screen scan ended at %@"
            }
        }
    }

    private enum Key {
        static let unlockCount = "activity.lockScreenUnlocksToday.count"
        static let unlockDay = "activity.lockScreenUnlocksToday.day"
        static let lastEvent = "activity.lastLockScreenEvent"
        static let lastEventType = "activity.lastLockScreenEvent.type"
        static let lastEventTime = "activity.lastLockScreenEvent.time"
    }

    private let defaults: UserDefaults
    private let calendar: Calendar
    private var dayKey = ""
    private(set) var unlocksToday = 0
    private(set) var lastEvent = L10n.text("No checks yet")

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
        if let rawType = defaults.string(forKey: Key.lastEventType),
           let event = Event(rawValue: rawType),
           let time = defaults.string(forKey: Key.lastEventTime) {
            lastEvent = L10n.format(event.messageKey, time)
        } else {
            lastEvent = Self.localizedLegacyEvent(defaults.string(forKey: Key.lastEvent))
        }
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
        defaults.removeObject(forKey: Key.lastEventType)
        defaults.removeObject(forKey: Key.lastEventTime)
    }

    mutating func recordEvent(_ event: Event, at date: Date = .now) {
        let time = date.formatted(date: .omitted, time: .shortened)
        lastEvent = L10n.format(event.messageKey, time)
        defaults.set(event.rawValue, forKey: Key.lastEventType)
        defaults.set(time, forKey: Key.lastEventTime)
        defaults.removeObject(forKey: Key.lastEvent)
    }

    private func persistCount(for day: String) {
        defaults.set(unlocksToday, forKey: Key.unlockCount)
        defaults.set(day, forKey: Key.unlockDay)
    }

    private static func localizedLegacyEvent(_ value: String?) -> String {
        guard let value else { return L10n.text("No checks yet") }
        let legacy: [(String, Event)] = [
            ("lock screen scanning ", .scanning),
            ("lock screen unlocked ", .unlocked),
            ("stored password rejected ", .passwordRejected),
            ("face not recognized ", .noMatch),
            ("no face detected ", .noFace),
            ("lock screen scan ended ", .scanEnded),
        ]
        for (prefix, event) in legacy where value.hasPrefix(prefix) {
            return L10n.format(event.messageKey, String(value.dropFirst(prefix.count)))
        }
        return L10n.text(value)
    }

    private static func localDayKey(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(parts.era ?? 0)-\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }
}
