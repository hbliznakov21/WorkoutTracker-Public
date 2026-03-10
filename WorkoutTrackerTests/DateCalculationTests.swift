import Testing
import Foundation

@Suite("Date Calculation Tests")
struct DateCalculationTests {

    // MARK: - Monday calculation (week start)

    @Test("Monday arithmetic returns correct day")
    func mondayArithmetic() {
        let cal = Calendar.current
        // Test several known dates
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        // March 8, 2026 is a Sunday
        let sunday = formatter.date(from: "2026-03-08")!
        let weekday = cal.component(.weekday, from: sunday)
        let daysFromMon = (weekday + 5) % 7
        let monday = cal.date(byAdding: .day, value: -daysFromMon, to: cal.startOfDay(for: sunday))!

        #expect(cal.component(.weekday, from: monday) == 2) // Monday
        #expect(formatter.string(from: monday) == "2026-03-02")
    }

    @Test("Monday calculation for actual Monday returns same day")
    func mondayOnMonday() {
        let cal = Calendar.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")

        let monday = formatter.date(from: "2026-03-02")!
        let weekday = cal.component(.weekday, from: monday)
        let daysFromMon = (weekday + 5) % 7
        #expect(daysFromMon == 0)
    }

    // MARK: - Streak counting

    @Test("Unique days from timestamps")
    func uniqueDaysCounting() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let timestamps = [
            "2026-03-01T10:00:00Z",
            "2026-03-01T14:00:00Z", // same day
            "2026-03-02T09:00:00Z",
            "2026-03-04T08:00:00Z",
        ]

        let dates = timestamps.compactMap { formatter.date(from: $0) }
        let cal = Calendar.current
        let uniqueDays = Set(dates.map { cal.startOfDay(for: $0) })
        #expect(uniqueDays.count == 3)
    }

    // MARK: - Safe date arithmetic (no force unwrap)

    @Test("Calendar.date(byAdding:) with nil fallback")
    func safeDateArithmetic() {
        let result = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        #expect(result < Date())
    }

    @Test("Calendar.date(byAdding:) with large negative value")
    func largeDateArithmetic() {
        let result = Calendar.current.date(byAdding: .day, value: -3650, to: Date()) ?? Date()
        #expect(result < Date())
    }
}
