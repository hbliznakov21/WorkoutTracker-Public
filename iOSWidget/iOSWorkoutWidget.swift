import WidgetKit
import SwiftUI

// MARK: - Timeline Entry

struct WorkoutEntry: TimelineEntry {
    let date: Date
    let routineName: String
    let lastDuration: Int       // seconds
    let lastVolume: Double      // kg
    let daysCompleted: Int      // 0-6
    let isMarkedRestDay: Bool   // manually marked rest day
    let workoutDoneToday: Bool  // whether today's workout is complete
    let todayVolume: String     // formatted volume if done today
    let todayDuration: String   // formatted duration if done today
    let hour: Int               // current hour for time-of-day context
}

// MARK: - Timeline Provider

struct WorkoutProvider: TimelineProvider {
    #if SONYA
    private static let appGroupID = "group.com.hbliznakov.WorkoutTrackerSonya"
    #else
    private static let appGroupID = "group.com.hbliznakov.WorkoutTracker"
    #endif

    private static let defaultSchedule: [String: String] = [
        "Monday": "Push (Mon)", "Tuesday": "Pull A",
        "Wednesday": "Legs A", "Thursday": "Push (Thu)",
        "Friday": "Pull B", "Saturday": "Legs B", "Sunday": "Rest"
    ]

    private static let englishWeekdays = [
        "Sunday", "Monday", "Tuesday", "Wednesday",
        "Thursday", "Friday", "Saturday"
    ]

    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(date: .now, routineName: "Push", lastDuration: 3600, lastVolume: 12500, daysCompleted: 3, isMarkedRestDay: false, workoutDoneToday: false, todayVolume: "", todayDuration: "", hour: 12)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        let entry = makeEntry()
        let cal = Calendar.current
        let now = Date()
        let hour = cal.component(.hour, from: now)

        let boundaries = [6, 10, 20, 24]
        let nextBoundary = boundaries.first(where: { $0 > hour }) ?? 24
        let nextRefresh: Date
        if nextBoundary == 24 {
            nextRefresh = cal.startOfDay(for: now).addingTimeInterval(86400)
        } else {
            nextRefresh = cal.date(bySettingHour: nextBoundary, minute: 0, second: 0, of: now) ?? now.addingTimeInterval(3600)
        }
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func makeEntry() -> WorkoutEntry {
        let defaults = UserDefaults(suiteName: Self.appGroupID)

        let weekday = Calendar.current.component(.weekday, from: Date()) - 1
        let dayName = Self.englishWeekdays[weekday]
        var routineName = "Rest"
        if let data = defaults?.data(forKey: "weeklySchedule"),
           let schedule = try? JSONDecoder().decode([String: String].self, from: data) {
            routineName = schedule[dayName] ?? "Rest"
        } else {
            routineName = Self.defaultSchedule[dayName] ?? "Rest"
        }

        let duration = defaults?.integer(forKey: "lastWorkoutDuration") ?? 0
        let volume = defaults?.double(forKey: "lastWorkoutVolume") ?? 0
        let daysCompleted = defaults?.integer(forKey: "widgetTrainingDaysCompleted") ?? 0

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let todayStr = fmt.string(from: Date())
        let restDayStrings = defaults?.stringArray(forKey: "widgetRestDays") ?? []
        let isMarkedRestDay = restDayStrings.contains(todayStr)

        let hour = Calendar.current.component(.hour, from: Date())
        let workoutDoneToday = defaults?.bool(forKey: "widgetWorkoutDone") ?? false
        let todayVolume = defaults?.string(forKey: "widgetTodayVolume") ?? ""
        let todayDuration = defaults?.string(forKey: "widgetTodayDuration") ?? ""

        return WorkoutEntry(
            date: .now,
            routineName: routineName,
            lastDuration: duration,
            lastVolume: volume,
            daysCompleted: daysCompleted,
            isMarkedRestDay: isMarkedRestDay,
            workoutDoneToday: workoutDoneToday,
            todayVolume: todayVolume,
            todayDuration: todayDuration,
            hour: hour
        )
    }
}

// MARK: - Widget View

struct WorkoutWidgetView: View {
    let entry: WorkoutEntry

    private let bg = Color(hex: "0f172a")
    private let accent = Color(hex: "22c55e")
    private let subtle = Color(hex: "94a3b8")
    private let muted = Color(hex: "475569")
    private let surface = Color(hex: "1e293b")
    private let amber = Color(hex: "f59e0b")

    private var isRestDay: Bool { entry.routineName == "Rest" || entry.isMarkedRestDay }
    private var isDone: Bool { entry.workoutDoneToday }

    /// Short display name for the routine
    private var shortName: String {
        entry.routineName
            .replacingOccurrences(of: "(Mon)", with: "Mon")
            .replacingOccurrences(of: "(Thu)", with: "Thu")
            .replacingOccurrences(of: " A", with: " A")
            .replacingOccurrences(of: " B", with: " B")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isDone {
                doneView
            } else if isRestDay {
                restView
            } else {
                readyView
            }

            Spacer(minLength: 4)

            // Weekly progress bar — always visible
            weeklyProgress
        }
        .containerBackground(bg, for: .widget)
    }

    // MARK: - Workout completed state

    private var doneView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Checkmark + routine
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(accent)
                Text("DONE")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(accent)
            }

            Text(shortName)
                .font(.system(size: 20, weight: .black))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 2)

            // Stats row
            HStack(spacing: 10) {
                if !entry.todayDuration.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "clock")
                            .font(.system(size: 9))
                        Text(entry.todayDuration)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(subtle)
                }
                if !entry.todayVolume.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "scalemass")
                            .font(.system(size: 9))
                        Text(entry.todayVolume)
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(subtle)
                }
            }
        }
    }

    // MARK: - Rest day state

    private var restView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RECOVERY")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(muted)

            HStack(spacing: 6) {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16))
                Text("Rest Day")
                    .font(.system(size: 20, weight: .black))
            }
            .foregroundStyle(subtle)
            .lineLimit(1)

            Spacer(minLength: 2)

            Text("Recover & grow")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(muted)
        }
    }

    // MARK: - Ready to train state

    private var readyView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TODAY")
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.2)
                .foregroundStyle(muted)

            Text(shortName)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 2)

            // Last session reference
            if entry.lastDuration > 0 {
                HStack(spacing: 3) {
                    Text("Last:")
                        .foregroundStyle(muted)
                    Text("\(entry.lastDuration / 60)m")
                        .foregroundStyle(subtle)
                    Text("·")
                        .foregroundStyle(muted)
                    Text(formatVolume(entry.lastVolume))
                        .foregroundStyle(subtle)
                }
                .font(.system(size: 10, weight: .semibold))
            }
        }
    }

    // MARK: - Weekly progress bar

    private var weeklyProgress: some View {
        VStack(spacing: 4) {
            // Segmented bar
            GeometryReader { geo in
                let total = 6
                let spacing: CGFloat = 3
                let barWidth = (geo.size.width - spacing * CGFloat(total - 1)) / CGFloat(total)

                HStack(spacing: spacing) {
                    ForEach(0..<total, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2.5)
                            .fill(i < entry.daysCompleted ? accent : surface)
                            .frame(width: barWidth, height: 5)
                    }
                }
            }
            .frame(height: 5)

            // Label
            HStack {
                Text("\(entry.daysCompleted)/6 this week")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(muted)
                Spacer()
                if entry.daysCompleted >= 4 {
                    HStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 8))
                        Text("streak")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(amber)
                }
            }
        }
    }

    private func formatVolume(_ v: Double) -> String {
        if v >= 1000 {
            return String(format: "%.1fk", v / 1000)
        }
        return "\(Int(v))kg"
    }
}

// MARK: - Widget Configuration

struct iOSWorkoutWidget: Widget {
    let kind = "iOSWorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutProvider()) { entry in
            WorkoutWidgetView(entry: entry)
        }
        .configurationDisplayName("Workout Today")
        .description("Today's routine and training progress")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Color hex extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8) & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
