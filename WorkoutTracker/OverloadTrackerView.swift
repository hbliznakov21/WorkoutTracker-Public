import SwiftUI
import Charts

struct OverloadTrackerView: View {
    @Environment(WorkoutStore.self) var store

    @State private var exercises: [ExerciseTrend] = []
    @State private var isLoading = true
    @State private var errorText: String?

    private var progressing: [ExerciseTrend] { exercises.filter { $0.trend == .progressing } }
    private var stalling:    [ExerciseTrend] { exercises.filter { $0.trend == .stalling } }
    private var regressing:  [ExerciseTrend] { exercises.filter { $0.trend == .regressing } }

    private var groupedByMuscle: [(muscle: String, items: [ExerciseTrend])] {
        let dict = Dictionary(grouping: exercises, by: { $0.muscleGroup })
        return dict
            .map { (muscle: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.muscle < $1.muscle }
    }

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
                } else if exercises.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.border)
                        Text("Not enough data")
                            .font(.headline).foregroundColor(Theme.subtle)
                        Text("Complete at least 2 sessions of an exercise to see overload trends.")
                            .font(.caption).foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            summaryBar.padding(.top, 8)
                            ForEach(groupedByMuscle, id: \.muscle) { group in
                                muscleSection(group.muscle, items: group.items)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task { await loadData() }
        .navigationTitle("Overload Tracker")
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
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { store.activeScreen = .exerciseSubstitutions } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                        Text("Subs")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Summary bar

    private var summaryBar: some View {
        HStack(spacing: 16) {
            summaryChip(count: progressing.count, label: "progressing", color: Theme.accent)
            summaryChip(count: stalling.count, label: "stalling", color: Color(hex: "f59e0b"))
            summaryChip(count: regressing.count, label: "regressing", color: Color(hex: "ef4444"))
        }
        .padding(.horizontal, 14)
    }

    private func summaryChip(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(count)")
                .font(.system(size: 18, weight: .black))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Theme.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border))
    }

    // MARK: - Muscle section

    private func muscleSection(_ muscle: String, items: [ExerciseTrend]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(muscleColor(muscle))
                    .frame(width: 8, height: 8)
                Text(muscle)
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                    .foregroundColor(Theme.subtle)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            ForEach(items) { item in
                exerciseRow(item)
                if item.id != items.last?.id {
                    Divider().padding(.leading, 16).background(Theme.border)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    private func exerciseRow(_ item: ExerciseTrend) -> some View {
        let isStallAlert = item.trend == .stalling && item.stallWeeks >= 3

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer()

                // Trend badge
                HStack(spacing: 3) {
                    Text(item.trend.icon)
                        .font(.system(size: 14, weight: .bold))
                    if item.isBodyweight {
                        Text("\(item.lastValue, specifier: "%.0f") reps")
                            .font(.system(size: 12, weight: .bold))
                    } else {
                        Text("\(Int(item.lastValue)) kg")
                            .font(.system(size: 12, weight: .bold))
                    }
                }
                .foregroundColor(item.trend.color)
            }

            // Mini sparkline
            if item.sessionE1RMs.count >= 2 {
                Chart {
                    ForEach(Array(item.sessionE1RMs.enumerated()), id: \.offset) { idx, val in
                        LineMark(
                            x: .value("Session", idx),
                            y: .value("e1RM", val)
                        )
                        .foregroundStyle(item.trend.color)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Session", idx),
                            y: .value("e1RM", val)
                        )
                        .foregroundStyle(idx == item.sessionE1RMs.count - 1 ? item.trend.color : Theme.muted)
                        .symbolSize(idx == item.sessionE1RMs.count - 1 ? 30 : 15)
                    }
                }
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .chartYScale(domain: max(0, (item.sessionE1RMs.min() ?? 0) * 0.95) ... max(1, (item.sessionE1RMs.max() ?? 100) * 1.05))
                .frame(height: 36)
            }

            // Stall alert
            if isStallAlert {
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                    Text("Stalling \(item.stallWeeks) weeks")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(hex: "f59e0b"))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(hex: "f59e0b").opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text("Consider: increase weight, add reps, or change variation")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.muted)

                // Substitution suggestions
                substitutionChips(for: item.name)
            } else if item.trend == .stalling {
                Text("Stalling \(item.stallWeeks) week\(item.stallWeeks == 1 ? "" : "s")")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "f59e0b"))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(isStallAlert ? Color(hex: "f59e0b").opacity(0.04) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { store.activeScreen = .progress(item.name) }
    }

    // MARK: - Substitution chips

    @ViewBuilder
    private func substitutionChips(for exerciseName: String) -> some View {
        let subs = ExerciseSubstitutions.suggestions(for: exerciseName, limit: 3)
        if !subs.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Try instead:")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.subtle)

                HStack(spacing: 6) {
                    ForEach(subs, id: \.self) { name in
                        Button {
                            store.activeScreen = .progress(name)
                        } label: {
                            Text(name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.accent.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Theme.accent.opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadData() async {
        struct SetRow: Decodable {
            let exerciseName: String
            let weightKg: Double
            let reps: Int
            let loggedAt: Date
            let workoutId: UUID
            let exercises: ExRow?

            struct ExRow: Decodable {
                let muscleGroup: String?
                enum CodingKeys: String, CodingKey { case muscleGroup = "muscle_group" }
            }

            enum CodingKeys: String, CodingKey {
                case exerciseName = "exercise_name"
                case weightKg    = "weight_kg"
                case reps
                case loggedAt    = "logged_at"
                case workoutId   = "workout_id"
                case exercises
            }
        }

        let cal = Calendar.current
        let eightWeeksAgo = cal.date(byAdding: .weekOfYear, value: -8, to: Date())!
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]
        let dateStr = isoFmt.string(from: eightWeeksAgo)

        let rows: [SetRow]
        do {
            rows = try await SupabaseClient.shared.get(
                "workout_sets?select=exercise_name,weight_kg,reps,logged_at,workout_id,exercises(muscle_group)" +
                "&order=logged_at.desc&logged_at=gte.\(dateStr)"
            )
        } catch {
            errorText = "Failed to load data: \(error.localizedDescription)"
            isLoading = false
            return
        }

        // Group by exercise name
        let byExercise = Dictionary(grouping: rows, by: { $0.exerciseName })

        var results: [ExerciseTrend] = []

        for (name, exRows) in byExercise {
            let muscleGroup = exRows.first?.exercises?.muscleGroup ?? "Other"
            let isBodyweight = exRows.allSatisfy { $0.weightKg == 0 }

            // Group by workout_id to get session bests
            let bySession = Dictionary(grouping: exRows, by: { $0.workoutId })
            var sessionBests: [(date: Date, e1rm: Double)] = []

            for (_, sessionRows) in bySession {
                guard let best = sessionRows.max(by: { e1rm($0.weightKg, $0.reps, isBodyweight) < e1rm($1.weightKg, $1.reps, isBodyweight) }) else { continue }
                let val = e1rm(best.weightKg, best.reps, isBodyweight)
                sessionBests.append((date: best.loggedAt, e1rm: val))
            }

            sessionBests.sort { $0.date < $1.date }

            guard sessionBests.count >= 2 else { continue }

            // Take last 6 for sparkline
            let sparkline = Array(sessionBests.suffix(6).map(\.e1rm))
            let lastValue = sessionBests.last?.e1rm ?? 0

            // Determine trend from last 3 sessions
            let recent = Array(sessionBests.suffix(3))
            let trend: TrendDirection
            var stallWeeks = 0

            if recent.count >= 3 {
                let a = recent[0].e1rm
                let b = recent[1].e1rm
                let c = recent[2].e1rm  // most recent
                let maxVal = max(a, b, c)
                let threshold = maxVal * 0.025  // 2.5%

                let abClose = abs(a - b) <= threshold
                let bcClose = abs(b - c) <= threshold
                let acClose = abs(a - c) <= threshold

                if abClose && bcClose && acClose {
                    trend = .stalling
                    // Count consecutive stalling sessions
                    stallWeeks = countStallSessions(sessionBests)
                } else if c > b {
                    trend = .progressing
                } else if c < b && c < a {
                    trend = .regressing
                } else {
                    // Edge case: b dropped but c recovered, or other
                    if c >= a { trend = .progressing }
                    else { trend = .stalling; stallWeeks = 1 }
                }
            } else {
                // Only 2 sessions
                let a = recent[0].e1rm
                let b = recent[1].e1rm
                let threshold = max(a, b) * 0.025
                if abs(a - b) <= threshold {
                    trend = .stalling
                    stallWeeks = 1
                } else if b > a {
                    trend = .progressing
                } else {
                    trend = .regressing
                }
            }

            results.append(ExerciseTrend(
                name: name,
                muscleGroup: muscleGroup,
                trend: trend,
                lastValue: lastValue,
                sessionE1RMs: sparkline,
                stallWeeks: stallWeeks,
                isBodyweight: isBodyweight
            ))
        }

        exercises = results.sorted { $0.name < $1.name }
        isLoading = false
    }

    private func e1rm(_ weight: Double, _ reps: Int, _ isBodyweight: Bool) -> Double {
        if isBodyweight { return Double(reps) }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    private func countStallSessions(_ sessions: [(date: Date, e1rm: Double)]) -> Int {
        guard sessions.count >= 2 else { return 0 }
        let latest = sessions.last!.e1rm
        let threshold = latest * 0.025
        var count = 0
        for s in sessions.reversed() {
            if abs(s.e1rm - latest) <= threshold {
                count += 1
            } else {
                break
            }
        }
        return max(1, count - 1)  // sessions stalling = gaps between them
    }

    // MARK: - Helpers

    private func muscleColor(_ muscle: String) -> Color {
        let m = muscle.lowercased()
        if m.contains("chest") || m.contains("pec")     { return Theme.accent }
        if m.contains("back")  || m.contains("lat")     { return Color(hex: "3b82f6") }
        if m.contains("shoulder") || m.contains("delt") { return Color(hex: "a855f7") }
        if m.contains("tricep")                          { return Color(hex: "f97316") }
        if m.contains("bicep")                           { return Color(hex: "ec4899") }
        if m.contains("quad")  || m.contains("leg")     { return Color(hex: "ef4444") }
        if m.contains("hamstring")                       { return Color(hex: "dc2626") }
        if m.contains("glute")                           { return Color(hex: "f59e0b") }
        if m.contains("calf")  || m.contains("calves")  { return Color(hex: "14b8a6") }
        if m.contains("core")  || m.contains("ab")      { return Color(hex: "eab308") }
        return Theme.muted
    }
}

// MARK: - Models

private enum TrendDirection {
    case progressing, stalling, regressing

    var icon: String {
        switch self {
        case .progressing: return "\u{2191}"  // up arrow
        case .stalling:    return "\u{2192}"  // right arrow
        case .regressing:  return "\u{2193}"  // down arrow
        }
    }

    var color: Color {
        switch self {
        case .progressing: return Theme.accent
        case .stalling:    return Color(hex: "f59e0b")
        case .regressing:  return Color(hex: "ef4444")
        }
    }
}

private struct ExerciseTrend: Identifiable {
    let id = UUID()
    let name: String
    let muscleGroup: String
    let trend: TrendDirection
    let lastValue: Double
    let sessionE1RMs: [Double]
    let stallWeeks: Int
    let isBodyweight: Bool
}
