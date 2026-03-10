import SwiftUI
import Charts

struct ExerciseProgressView: View {
    @Environment(WorkoutStore.self) var store
    let exerciseName: String

    @State private var data: [SessionBest] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var selectedPoint: SessionBest? = nil

    struct SessionBest: Identifiable {
        let id       = UUID()
        let date:    Date
        let weight:  Double
        let reps:    Int
        var e1rm: Double { weight * (1 + Double(reps) / 30) }
    }

    private var isBodyweight: Bool { !data.isEmpty && data.allSatisfy { $0.weight == 0 } }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                if loading {
                    ProgressView().tint(Theme.accent)
                } else if let errorText {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30)).foregroundColor(Color(hex: "ef4444"))
                        Text(errorText).foregroundColor(Theme.subtle)
                            .font(.caption).multilineTextAlignment(.center).padding(.horizontal, 32)
                    }
                } else if data.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.border)
                        Text("No history yet")
                            .font(.headline).foregroundColor(Theme.subtle)
                        Text("Complete a workout with \(exerciseName) and your progress chart will appear here.")
                            .font(.caption).foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            if isBodyweight {
                                repsChart.padding(.top, 8)
                            } else {
                                e1rmChart.padding(.top, 8)
                            }
                            sessionList
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task { await loadData() }
        .navigationTitle(exerciseName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.activeScreen = store.previousScreen } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("PRs")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Reps chart (bodyweight exercises)

    private var repsChart: some View {
        let best = data.max(by: { $0.reps < $1.reps })
        let minY = max(0, (data.map(\.reps).min() ?? 0) - 2)
        let maxY = (data.map(\.reps).max() ?? 20) + 2

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reps Progress")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                    .foregroundColor(Theme.subtle)
                Spacer()
                if let b = best {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Best").font(.caption2).foregroundColor(Theme.subtle)
                        Text("\(b.reps) reps").font(.system(size: 13, weight: .black))
                            .foregroundColor(Color(hex: "fbbf24"))
                    }
                }
            }

            Chart {
                ForEach(data) { pt in
                    AreaMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("Reps", pt.reps)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.25), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("Reps", pt.reps)
                    )
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("Reps", pt.reps)
                    )
                    .foregroundStyle(pt.id == best?.id ? Color(hex: "fbbf24") : Theme.accent)
                    .symbolSize(pt.id == best?.id ? 60 : 35)
                }
            }
            .chartYScale(domain: minY...maxY)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { val in
                    if let d = val.as(Date.self) {
                        AxisValueLabel {
                            Text(d, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(Theme.muted)
                    }
                    AxisGridLine().foregroundStyle(Theme.border)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { val in
                    if let v = val.as(Int.self) {
                        AxisValueLabel {
                            Text("\(v)").font(.system(size: 9))
                        }
                        .foregroundStyle(Theme.muted)
                    }
                    AxisGridLine().foregroundStyle(Theme.border)
                }
            }
            .frame(height: 200)

            Text("Bodyweight — reps only")
                .font(.caption2).foregroundColor(Color(hex: "475569"))
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Chart

    private var e1rmChart: some View {
        let best = data.max(by: { $0.e1rm < $1.e1rm })
        let minY = (data.map(\.e1rm).min() ?? 0) - 5
        let maxY = (data.map(\.e1rm).max() ?? 100) + 5

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Estimated 1RM Progress")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                    .foregroundColor(Theme.subtle)
                Spacer()
                if let b = best {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("Best").font(.caption2).foregroundColor(Theme.subtle)
                        Text("\(Int(b.e1rm)) kg").font(.system(size: 13, weight: .black))
                            .foregroundColor(Color(hex: "fbbf24"))
                    }
                }
            }

            Chart {
                ForEach(data) { pt in
                    AreaMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("e1RM", pt.e1rm)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Theme.accent.opacity(0.25), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)

                    LineMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("e1RM", pt.e1rm)
                    )
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("e1RM", pt.e1rm)
                    )
                    .foregroundStyle(pt.id == best?.id ? Color(hex: "fbbf24") : Theme.accent)
                    .symbolSize(pt.id == best?.id ? 60 : 35)
                }

                // Selected point rule line
                if let sel = selectedPoint {
                    RuleMark(x: .value("Selected", sel.date, unit: .day))
                        .foregroundStyle(Theme.subtle.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, spacing: 4) {
                            VStack(spacing: 2) {
                                Text("\(sel.weight.clean) kg \u{00D7} \(sel.reps)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                Text("e1RM: \(Int(sel.e1rm)) kg")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundColor(Theme.accent)
                                Text(shortDate(sel.date))
                                    .font(.system(size: 9))
                                    .foregroundColor(Theme.subtle)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Theme.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                        }
                }
            }
            .chartYScale(domain: max(0, minY)...maxY)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { val in
                    if let d = val.as(Date.self) {
                        AxisValueLabel {
                            Text(d, format: .dateTime.month(.abbreviated).day())
                                .font(.system(size: 9))
                        }
                        .foregroundStyle(Theme.muted)
                    }
                    AxisGridLine().foregroundStyle(Theme.border)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { val in
                    if let v = val.as(Double.self) {
                        AxisValueLabel {
                            Text("\(Int(v)) kg").font(.system(size: 9))
                        }
                        .foregroundStyle(Theme.muted)
                    }
                    AxisGridLine().foregroundStyle(Theme.border)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { drag in
                                    let x = drag.location.x - geo[proxy.plotFrame!].origin.x
                                    guard let date: Date = proxy.value(atX: x) else { return }
                                    selectedPoint = data.min(by: {
                                        abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
                                    })
                                    Haptics.selection()
                                }
                                .onEnded { _ in
                                    selectedPoint = nil
                                }
                        )
                }
            }
            .frame(height: 200)

            Text("Epley formula \u{00B7} weight \u{00D7} (1 + reps \u{00F7} 30)")
                .font(.caption2).foregroundColor(Color(hex: "475569"))
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Session list

    private var sessionList: some View {
        let bestByReps  = data.max(by: { $0.reps  < $1.reps })
        let bestByE1rm  = data.max(by: { $0.e1rm  < $1.e1rm })
        let best        = isBodyweight ? bestByReps : bestByE1rm

        return VStack(alignment: .leading, spacing: 0) {
            Text("Session Bests")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            ForEach(data.reversed()) { pt in
                HStack {
                    Text(shortDate(pt.date))
                        .font(.system(size: 13)).foregroundColor(Theme.subtle)
                        .frame(width: 56, alignment: .leading)
                    if isBodyweight {
                        Text("\(pt.reps) reps")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    } else {
                        Text("\(pt.weight.clean) × \(pt.reps)")
                            .font(.system(size: 13, weight: .semibold)).foregroundColor(.white)
                    }
                    Spacer()
                    if !isBodyweight {
                        Text("→ \(Int(pt.e1rm)) kg")
                            .font(.system(size: 14, weight: .black))
                            .foregroundColor(pt.id == best?.id ? Color(hex: "fbbf24") : Theme.accent)
                    }
                    if pt.id == best?.id {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "fbbf24"))
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                Divider().padding(.leading, 16).background(Theme.border)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Data loading

    private func loadData() async {
        struct SetRow: Decodable {
            let workoutId: UUID
            let weightKg:  Double
            let reps:      Int
            let loggedAt:  Date
            enum CodingKeys: String, CodingKey {
                case workoutId = "workout_id"
                case weightKg  = "weight_kg"
                case reps
                case loggedAt  = "logged_at"
            }
        }

        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "()&=+")
        let encodedName = exerciseName
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? exerciseName

        let rows: [SetRow]
        do {
            rows = try await SupabaseClient.shared.get(
                "workout_sets?select=workout_id,weight_kg,reps,logged_at" +
                "&exercise_name=eq.\(encodedName)&order=logged_at.asc"
            )
        } catch {
            errorText = "Failed to load progress: \(error.localizedDescription)"
            loading = false
            return
        }

        // Best set per workout session — by e1RM for weighted, by reps for bodyweight
        let isBodyweightExercise = rows.allSatisfy { $0.weightKg == 0 }
        var byWorkout: [UUID: SetRow] = [:]
        for r in rows {
            if let existing = byWorkout[r.workoutId] {
                let better = isBodyweightExercise
                    ? r.reps > existing.reps
                    : r.weightKg * (1 + Double(r.reps) / 30) > existing.weightKg * (1 + Double(existing.reps) / 30)
                if better { byWorkout[r.workoutId] = r }
            } else {
                byWorkout[r.workoutId] = r
            }
        }

        data = byWorkout.values
            .sorted { $0.loggedAt < $1.loggedAt }
            .map { row in
                SessionBest(date: row.loggedAt, weight: row.weightKg, reps: row.reps)
            }
        loading = false
    }

    private static let dMMMFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    private func shortDate(_ d: Date) -> String {
        Self.dMMMFmt.string(from: d)
    }
}
