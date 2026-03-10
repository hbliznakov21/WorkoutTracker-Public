//
//  WorkoutWidget.swift
//  WorkoutWidget
//
//  Created by Hristo Bliznakov on 04/03/2026.
//

import WidgetKit
import SwiftUI

// MARK: - Shared schedule

#if SONYA
private let appGroupID = "group.com.hbliznakov.WorkoutTrackerSonya"
#else
private let appGroupID = "group.com.hbliznakov.WorkoutTracker"
#endif
private let scheduleKey = "weeklySchedule"

// Must match defaultWeeklySchedule in Models.swift — used only on first launch before app writes to App Group
private let fallbackSchedule: [String: String] = [
    "Monday": "Push (Mon)", "Tuesday": "Pull A", "Wednesday": "Legs A",
    "Thursday": "Push (Thu)", "Friday": "Pull B", "Saturday": "Legs B", "Sunday": "Rest"
]

private func loadSchedule() -> [String: String] {
    guard let defaults = UserDefaults(suiteName: appGroupID),
          let data = defaults.data(forKey: scheduleKey),
          let dict = try? JSONDecoder().decode([String: String].self, from: data)
    else { return fallbackSchedule }
    return dict
}

private let englishWeekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

private func routineName(for date: Date) -> String {
    let schedule = loadSchedule()
    let day = englishWeekdays[Calendar.current.component(.weekday, from: date) - 1]
    return schedule[day] ?? "Rest"
}

// MARK: - Timeline

struct WorkoutEntry: TimelineEntry {
    let date: Date
    let todayRoutine: String
    let nextRoutine: String
    let isMarkedRestDay: Bool
}

struct WorkoutTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkoutEntry {
        WorkoutEntry(date: .now, todayRoutine: "Push", nextRoutine: "Pull A", isMarkedRestDay: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkoutEntry) -> Void) {
        completion(entry(for: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkoutEntry>) -> Void) {
        let now = Date()
        let cal = Calendar.current
        let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: now) ?? now)
        let current = entry(for: now)
        completion(Timeline(entries: [current], policy: .after(tomorrow)))
    }

    private func entry(for date: Date) -> WorkoutEntry {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: date) ?? date

        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let dateStr = fmt.string(from: date)
        let defaults = UserDefaults(suiteName: appGroupID)
        let restDayStrings = defaults?.stringArray(forKey: "widgetRestDays") ?? []
        let isMarkedRest = restDayStrings.contains(dateStr)

        return WorkoutEntry(
            date: date,
            todayRoutine: routineName(for: date),
            nextRoutine: routineName(for: tomorrow),
            isMarkedRestDay: isMarkedRest
        )
    }
}

// MARK: - Widget Views

struct WorkoutWidgetEntryView: View {
    let entry: WorkoutEntry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            circularView
        case .accessoryRectangular:
            rectangularView
        case .accessoryCorner:
            cornerView
        case .accessoryInline:
            inlineView
        default:
            circularView
        }
    }

    private var isRest: Bool { entry.todayRoutine == "Rest" || entry.isMarkedRestDay }

    private func routineIcon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("push")  { return "arrow.up.circle.fill" }
        if n.contains("pull")  { return "arrow.down.circle.fill" }
        if n.contains("legs") || n.contains("leg") { return "figure.run" }
        if n == "rest"         { return "bed.double.fill" }
        return "dumbbell.fill"
    }

    /// Day index in training week (Mon=1 .. Sat=6, Sun=0)
    private var trainingDayProgress: Double {
        let weekday = Calendar.current.component(.weekday, from: entry.date) // 1=Sun..7=Sat
        let mapped: [Int: Double] = [2: 1, 3: 2, 4: 3, 5: 4, 6: 5, 7: 6, 1: 0]
        let day = mapped[weekday] ?? 0
        return isRest ? 1.0 : day / 6.0
    }

    private var todayIcon: String {
        if entry.isMarkedRestDay { return "moon.zzz.fill" }
        return routineIcon(entry.todayRoutine)
    }

    private var displayName: String {
        if entry.isMarkedRestDay && entry.todayRoutine != "Rest" { return "REST" }
        return shortName(entry.todayRoutine)
    }

    private var circularView: some View {
        ZStack {
            // Progress ring
            AccessoryWidgetBackground()
            Gauge(value: trainingDayProgress) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(isRest ? .gray : .orange)

            // Centered icon + label
            VStack(spacing: 1) {
                Image(systemName: todayIcon)
                    .font(.system(size: 16, weight: .bold))
                Text(displayName)
                    .font(.system(size: 10, weight: .heavy))
                    .minimumScaleFactor(0.5)
            }
        }
        .containerBackground(.clear, for: .widget)
    }

    private var rectangularView: some View {
        HStack(spacing: 8) {
            Gauge(value: trainingDayProgress) {
                Image(systemName: todayIcon)
                    .font(.system(size: 10, weight: .bold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(isRest ? .gray : .orange)
            .scaleEffect(0.7)
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: routineIcon(entry.nextRoutine))
                        .font(.system(size: 9))
                    Text("Next: \(shortName(entry.nextRoutine))")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                Text(displayName)
                    .font(.system(size: 15, weight: .black))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(.clear, for: .widget)
    }

    private var cornerView: some View {
        Text(displayName)
            .font(.system(size: 14, weight: .bold))
            .widgetLabel {
                Label(isRest ? "Rest Day" : entry.todayRoutine, systemImage: todayIcon)
            }
            .containerBackground(.clear, for: .widget)
    }

    private var inlineView: some View {
        Label(isRest ? "Rest Day" : entry.todayRoutine, systemImage: todayIcon)
            .containerBackground(.clear, for: .widget)
    }

    private func shortName(_ name: String) -> String {
        let n = name.lowercased()
        if n.hasPrefix("push")   { return "PUSH" }
        if n.hasPrefix("pull a") { return "PL A" }
        if n.hasPrefix("pull b") { return "PL B" }
        if n.hasPrefix("legs a") { return "LG A" }
        if n.hasPrefix("legs b") { return "LG B" }
        if n.hasPrefix("legs")   { return "LEGS" }
        if n == "rest"           { return "REST" }
        return String(name.prefix(4)).uppercased()
    }
}

// MARK: - Widget Configuration

struct WorkoutWidget: Widget {
    let kind = "WorkoutWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WorkoutTimelineProvider()) { entry in
            WorkoutWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Workout")
        .description("Today's workout at a glance")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryCorner,
            .accessoryInline
        ])
    }
}

#Preview(as: .accessoryRectangular) {
    WorkoutWidget()
} timeline: {
    WorkoutEntry(date: .now, todayRoutine: "Push (Mon)", nextRoutine: "Pull A", isMarkedRestDay: false)
    WorkoutEntry(date: .now, todayRoutine: "Rest", nextRoutine: "Push (Mon)", isMarkedRestDay: false)
    WorkoutEntry(date: .now, todayRoutine: "Pull A", nextRoutine: "Legs A", isMarkedRestDay: true)
}
