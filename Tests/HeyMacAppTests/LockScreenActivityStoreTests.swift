import Foundation
import Testing
@testable import HeyMacApp

@Suite
struct LockScreenActivityStoreTests {
    @Test func countSurvivesStoreRecreationOnTheSameDay() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = utcCalendar()
        let today = date(2026, 11, 9, calendar: calendar)

        var firstLaunch = LockScreenActivityStore(defaults: defaults, calendar: calendar)
        firstLaunch.restore(at: today)
        firstLaunch.recordUnlock(at: today)
        firstLaunch.recordUnlock(at: today)

        var nextLaunch = LockScreenActivityStore(defaults: defaults, calendar: calendar)
        nextLaunch.restore(at: today)
        #expect(nextLaunch.unlocksToday == 2)
    }

    @Test func countResetsOnTheNextLocalDayAndStaysResetAfterRestart() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = utcCalendar()
        let firstDay = date(2026, 11, 9, calendar: calendar)
        let nextDay = date(2026, 11, 10, calendar: calendar)

        var store = LockScreenActivityStore(defaults: defaults, calendar: calendar)
        store.restore(at: firstDay)
        store.recordUnlock(at: firstDay)
        store.refreshDay(at: nextDay)
        #expect(store.unlocksToday == 0)

        var nextLaunch = LockScreenActivityStore(defaults: defaults, calendar: calendar)
        nextLaunch.restore(at: nextDay)
        #expect(nextLaunch.unlocksToday == 0)
    }

    @Test func latestActivitySurvivesStoreRecreation() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let calendar = utcCalendar()
        let today = date(2026, 11, 9, calendar: calendar)
        var firstLaunch = LockScreenActivityStore(defaults: defaults, calendar: calendar)
        firstLaunch.restore(at: today)
        firstLaunch.recordEvent("lock screen unlocked 9:41 AM")

        var nextLaunch = LockScreenActivityStore(defaults: defaults, calendar: calendar)
        nextLaunch.restore(at: today)
        #expect(nextLaunch.lastEvent == "lock screen unlocked 9:41 AM")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "heymac.activity-tests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
