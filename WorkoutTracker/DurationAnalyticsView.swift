import SwiftUI
import Charts

struct DurationAnalyticsView: View {
    @Environment(WorkoutStore.self) var store

    @State private var workouts: [Workout] = []
    @State private var isLoading = true
    @State private var errorText: String?

    // MARK: - Computed

    private var validWorkouts: [Workout] {
        workouts.filter { $0.finishedAt != nil }
    }

    private func durationMinutes(_ w: Workout) -> Double {
        guard let fin = w.finishedAt else { return 0 }
        return fin.timeIntervalSince(w.startedAt) / 60
    }

    private var trendWorkouts: [Workout] {
        Array(validWorkouts.prefix(30))
    }

    private var avgDuration: Double {
        let durations = validWorkouts.map { durationMinutes($0) }
        guard !durations.isEmpty else { return 0 }
        return durations.reduce(0, +) / Double(durations.count)
    }

    private var shortestDuration: Double {
        validWorkouts.map { durationMinutes($0) }.min() ?? 0
    }

    private var longestDuration: Double {
        validWorkouts.map { durationMinutes($0) }.max() ?? 0
    }

    private var thisWeekTotal: Double {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        let daysToMon = weekday == 1 ? -6 : 2 - weekday
        let monday = cal.startOfDay(for: cal.date(byAdding: .day, value: daysToMon, to: now)!)
        return validWorkouts
            .filter { $0.startedAt >= monday }
            .map { durationMinutes($0) }
            .reduce(0, +)
    }

    private var avgByRoutine: [(routine: String, avg: Double)] {
        let grouped = Dictionary(grouping: validWorkouts, by: { $0.routineName })
        return grouped
            .map { (routine: $0.key, avg: $0.value.map { durationMinutes($0) }.reduce(0, +) / Double($0.value.count)) }
            .sorted { $0.avg > $1.avg }
    }

    private var recentSessions: [Workout] {
        Array(validWorkouts.prefix(10))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else if let errorText {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30)).foregroundColor(Color(hex: "ef4444"))
                        Text(errorText).foregroundColor(Theme.subtle)
                            .font(.caption).multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                } else if validWorkouts.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.border)
                        Text("No completed workouts")
                            .font(.headline).foregroundColor(Theme.subtle)
                        Text("Complete a workout to see duration analytics.")
                            .font(.caption).foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            statsCards.padding(.top, 8)
                            durationTrendChart
                            avgByRoutineChart
                            recentSessionsList
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task { await loadData() }
        .navigationTitle("Duration Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.activeScreen = .home } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Home")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Stats Cards

    private var statsCards: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
            statCard(value: formatMinutes(avgDuration), label: "Avg Duration")
            statCard(value: formatMinutes(shortestDuration), label: "Shortest")
            statCard(value: formatMinutes(longestDuration), label: "Longest")
            statCard(value: formatMinutes(thisWeekTotal), label: "This Week Total")
        }
        .padding(.horizontal, 14)
    }

    private func statCard(value: String, label: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(1)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    // MARK: - Duration Trend Chart

    private var durationTrendChart: some View {
        let data = Array(trendWorkouts.reversed())

        return VStack(alignment: .leading, spacing: 10) {
            Text("Duration Trend")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)
            Text("Last \(data.count) workouts")
                .font(.caption2).foregroundColor(Theme.muted)

            Chart {
                ForEach(Array(data.enumerated()), id: \.element.id) { idx, w in
                    AreaMark(
                        x: .value("Session", idx),
                        y: .value("Minutes", durationMinutes(w))
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.3), Theme.accent.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Session", idx),
                        y: .value("Minutes", durationMinutes(w))
                    )
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Session", idx),
                        y: .value("Minutes", durationMinutes(w))
                    )
                    .foregroundStyle(idx == data.count - 1 ? Theme.accent : Theme.muted)
                    .symbolSize(idx == data.count - 1 ? 30 : 12)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))m")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    AxisGridLine().foregroundStyle(Theme.border)
                }
            }
            .frame(height: 180)
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Average by Routine Chart

    private var avgByRoutineChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Average by Routine")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)

            Chart {
                ForEach(avgByRoutine, id: \.routine) { item in
                    BarMark(
                        x: .value("Routine", item.routine),
                        y: .value("Minutes", item.avg)
                    )
                    .foregroundStyle(routineColor(item.routine))
                    .cornerRadius(6)
                    .annotation(position: .top, spacing: 4) {
                        Text("\(Int(item.avg))m")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Theme.subtle)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))m")
                                .font(.system(size: 9))
                                .foregroundColor(Theme.muted)
                        }
                    }
                    AxisGridLine().foregroundStyle(Theme.border)
                }
            }
            .frame(height: 200)
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Recent Sessions List

    private var recentSessionsList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Sessions")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            ForEach(Array(recentSessions.enumerated()), id: \.element.id) { idx, w in
                HStack {
                    Circle()
                        .fill(routineColor(w.routineName))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(w.routineName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                        Text(Self.dateFmt.string(from: w.startedAt))
                            .font(.system(size: 11))
                            .foregroundColor(Theme.muted)
                    }
                    Spacer()
                    Text(formatMinutes(durationMinutes(w)))
                        .font(.system(size: 16, weight: .black))
                        .foregroundColor(Theme.accent)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)

                if idx < recentSessions.count - 1 {
                    Divider().padding(.leading, 36).background(Theme.border)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Data Loading

    private func loadData() async {
        do {
            let fetched: [Workout] = try await SupabaseClient.shared.get(
                "workouts?select=id,routine_id,routine_name,started_at,finished_at,calories,avg_heart_rate&finished_at=not.is.null&order=started_at.desc&limit=50"
            )
            workouts = fetched
        } catch {
            errorText = "Failed to load data: \(error.localizedDescription)"
        }
        isLoading = false
    }

    // MARK: - Helpers

    private func routineColor(_ name: String) -> Color {
        let n = name.lowercased()
        if n.contains("push")            { return Color(hex: "3b82f6") }
        if n.contains("pull a")          { return Color(hex: "a855f7") }
        if n.contains("pull b")          { return Color(hex: "ec4899") }
        if n.contains("pull")            { return Color(hex: "a855f7") }
        if n.contains("legs a") || n.contains("leg a") { return Color(hex: "f59e0b") }
        if n.contains("legs b") || n.contains("leg b") { return Color(hex: "f97316") }
        if n.contains("leg")             { return Color(hex: "f59e0b") }
        if n.contains("cardio")          { return Color(hex: "14b8a6") }
        return Theme.accent
    }

    private func formatMinutes(_ m: Double) -> String {
        let total = Int(m)
        if total >= 60 {
            let h = total / 60
            let min = total % 60
            return min > 0 ? "\(h)h \(min)m" : "\(h)h"
        }
        return "\(total)m"
    }

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, EEE"
        return f
    }()
}
