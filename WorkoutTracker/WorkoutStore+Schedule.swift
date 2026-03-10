import Foundation
import WidgetKit
import os.log

// MARK: - Schedule, Rest Days, Deload Week Tracking

extension WorkoutStore {

    // MARK: - Deload week management

    func startDeloadWeek() {
        isDeloadWeek = true
        deloadSuggestionDismissed = false
    }

    func endDeloadWeek() {
        isDeloadWeek = false
        weeksWithoutDeload = 0
        deloadSuggestionDismissed = false
    }

    func dismissDeloadSuggestion() {
        deloadSuggestionDismissed = true
    }

    /// Check if we've entered a new training week and increment the counter.
    /// Called on app launch / home view load. Uses Monday-based week number.
    func checkAndIncrementDeloadWeek() {
        let cal = Calendar.current
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        let daysToMon = weekday == 1 ? -6 : 2 - weekday
        guard let monday = cal.date(byAdding: .day, value: daysToMon, to: cal.startOfDay(for: today)) else { return }
        let mondayKey = Int(monday.timeIntervalSince1970)

        let lastChecked = UserDefaults.standard.integer(forKey: UDKey.deloadLastCheckedWeek)
        guard mondayKey != lastChecked else { return }
        UserDefaults.standard.set(mondayKey, forKey: UDKey.deloadLastCheckedWeek)

        if isDeloadWeek {
            endDeloadWeek()
        } else {
            weeksWithoutDeload += 1
            deloadSuggestionDismissed = false
        }
    }

    // MARK: - Load rest days (last 30 days)

    func loadRestDays() async {
        struct RestRow: Decodable { let restDate: String
            enum CodingKeys: String, CodingKey { case restDate = "rest_date" }
        }
        let cal    = Calendar.current
        guard let thirtyDaysAgo = cal.date(byAdding: .day, value: -30, to: Date()) else { return }
        let cutoff = String(isoFmt.string(from: thirtyDaysAgo).prefix(10))
        guard let rows: [RestRow] = await sb.tryGet(
            "rest_days?select=rest_date&rest_date=gte.\(cutoff)"
        ) else { return }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
        restDays = Set(rows.compactMap { fmt.date(from: $0.restDate) }.map { cal.startOfDay(for: $0) })
        syncRestDaysToWidget()
    }

    // MARK: - Toggle rest day

    func toggleRestDay(date: Date) async {
        let cal  = Calendar.current
        let day  = cal.startOfDay(for: date)
        let fmt  = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
        let dateStr = fmt.string(from: day)

        if restDays.contains(day) {
            restDays.remove(day)
            do {
                try await sb.delete("rest_days?rest_date=eq.\(dateStr)")
            } catch {
                restDays.insert(day)
                errorMessage = "Failed to update rest day: \(error.localizedDescription)"
            }
        } else {
            restDays.insert(day)
            struct RestInsert: Encodable { let rest_date: String }
            do {
                try await sb.postBatch("rest_days", body: [RestInsert(rest_date: dateStr)])
            } catch {
                restDays.remove(day)
                errorMessage = "Failed to update rest day: \(error.localizedDescription)"
            }
        }
        syncRestDaysToWidget()
    }

    // MARK: - Sync rest days to widget & Watch

    func syncRestDaysToWidget() {
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"; fmt.locale = Locale(identifier: "en_US_POSIX")
        let strings = restDays.map { fmt.string(from: $0) }
        if let defaults = UserDefaults(suiteName: Self.appGroupID) {
            defaults.set(strings, forKey: "widgetRestDays")
        }
        WidgetCenter.shared.reloadAllTimelines()
        PhoneConnectivityManager.shared.sendRestDays(strings)
    }

    // MARK: - Editable weekly schedule

    func updateSchedule(day: String, routineName: String) {
        schedule[day] = routineName
        if let data = try? JSONEncoder().encode(schedule) {
            Self.sharedDefaults?.set(data, forKey: "weeklySchedule")
            UserDefaults.standard.set(data, forKey: "weeklySchedule")
        }
        WidgetCenter.shared.reloadAllTimelines()
        PhoneConnectivityManager.shared.sendSchedule(schedule)
        syncScheduleToSupabase()
    }

    func syncScheduleToSupabase() {
        Task {
            do {
                try await sb.upsertRaw("weekly_schedule", payload: [["id": 1, "schedule": schedule]])
            } catch {
                print("[Supabase] schedule sync failed: \(error.localizedDescription)")
            }
        }
    }

    func loadScheduleFromSupabase() async {
        struct ScheduleRow: Decodable {
            let schedule: [String: String]
        }
        guard let rows: [ScheduleRow] = await sb.tryGet("weekly_schedule?select=schedule") else { return }
        guard let remote = rows.first?.schedule else { return }
        schedule = remote
        if let data = try? JSONEncoder().encode(schedule) {
            Self.sharedDefaults?.set(data, forKey: "weeklySchedule")
            UserDefaults.standard.set(data, forKey: "weeklySchedule")
        }
        WidgetCenter.shared.reloadAllTimelines()
        PhoneConnectivityManager.shared.sendSchedule(schedule)
    }

    // MARK: - Today's routine

    private static let englishWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var todayRoutineName: String {
        let day = Self.englishWeekdays[Calendar.current.component(.weekday, from: Date()) - 1]
        return schedule[day] ?? "Rest"
    }

    /// Lightweight check: query Supabase for any finished workout today matching the routine.
    func checkTodayRoutineCompleted() async {
        let name = todayRoutineName
        guard name != "Rest" else {
            todayRoutineCompleted = false
            return
        }
        let cal = Calendar.current
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current
        let startOfDay = fmt.string(from: cal.startOfDay(for: Date()))
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? name

        struct MiniWk: Decodable { let id: UUID }
        let rows: [MiniWk]? = await sb.tryGet(
            "workouts?select=id&routine_name=eq.\(encoded)" +
            "&finished_at=not.is.null&started_at=gte.\(startOfDay)&limit=1"
        )
        todayRoutineCompleted = !(rows ?? []).isEmpty
    }

    var todayRoutine: Routine? {
        let name = todayRoutineName
        // Auto-switch to week-specific variant during reverse diet
        if let suffix = reverseWeekSuffix, name != "Rest" {
            let weekName = "\(name) \(suffix)"
            if let match = routines.first(where: { $0.name == weekName }) {
                return match
            }
        }
        let matches = routines.filter { $0.name == name }
        return matches.count == 1 ? matches.first : nil
    }

    /// Routines filtered for display — hides week variants not matching the current week.
    /// During Week 2 for example, "Push (Mon) W2" replaces "Push (Mon)" in the list,
    /// and W3/W4 variants are hidden entirely.
    var visibleRoutines: [Routine] {
        let suffix = reverseWeekSuffix                     // e.g. "W2" or nil
        let allSuffixes = ["W2", "W3", "W4"]
        let otherSuffixes = allSuffixes.filter { $0 != suffix }

        return routines.filter { r in
            // Hide week variants for other weeks
            for other in otherSuffixes {
                if r.name.hasSuffix(" \(other)") { return false }
            }
            // If we're in a week that has variants, hide the base routine when the variant exists
            if let suffix {
                let weekName = "\(r.name) \(suffix)"
                if routines.contains(where: { $0.name == weekName }) {
                    return false  // hide base; the variant will appear instead
                }
            }
            return true
        }
    }

    #if !SONYA
    // MARK: - Cardio this week (Mon-Sun)

    func loadCardioThisWeek() async {
        let cal  = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today) // 1=Sun … 7=Sat
        let daysToMon = weekday == 1 ? -6 : 2 - weekday
        guard let monday = cal.date(byAdding: .day, value: daysToMon, to: today) else { return }
        guard let sunday = cal.date(byAdding: .day, value: 6, to: monday) else { return }

        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = .current

        let from = fmt.string(from: monday)
        let to   = fmt.string(from: cal.date(byAdding: .day, value: 1, to: sunday)!)

        struct MiniWk: Decodable { let startedAt: String
            enum CodingKeys: String, CodingKey { case startedAt = "started_at" }
        }
        guard let rows: [MiniWk] = await sb.tryGet(
            "workouts?select=started_at&routine_id=is.null&finished_at=not.is.null" +
            "&started_at=gte.\(from)&started_at=lt.\(to)&order=started_at.asc"
        ) else { return }

        let isoWithFrac = ISO8601DateFormatter()
        isoWithFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        cardioThisWeek = rows.compactMap { isoWithFrac.date(from: $0.startedAt) ?? isoPlain.date(from: $0.startedAt) }
            .map { cal.startOfDay(for: $0) }
    }
    #endif

    /// Returns "W2", "W3", or "W4" during reverse diet weeks, nil otherwise.
    private var reverseWeekSuffix: String? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        guard let w2 = fmt.date(from: "2026-03-15"),
              let w3 = fmt.date(from: "2026-03-22"),
              let w4 = fmt.date(from: "2026-03-29"),
              let end = fmt.date(from: "2026-04-05") else { return nil }
        if today >= w4 && today < end { return "W4" }
        if today >= w3 && today < w4  { return "W3" }
        if today >= w2 && today < w3  { return "W2" }
        return nil
    }
}
