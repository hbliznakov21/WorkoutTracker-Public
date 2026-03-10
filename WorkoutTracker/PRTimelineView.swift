import SwiftUI

struct PRTimelineView: View {
    @Environment(WorkoutStore.self) var store

    @State private var prEntries: [PREntry] = []
    @State private var isLoading = true
    @State private var errorText: String?

    // MARK: - Computed

    private var groupedByMonth: [(month: String, entries: [PREntry])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "MMMM yyyy"
        let dict = Dictionary(grouping: prEntries, by: { fmt.string(from: $0.date) })
        return dict
            .map { (month: $0.key, entries: $0.value.sorted { $0.date > $1.date }) }
            .filter { !$0.entries.isEmpty }
            .sorted { ($0.entries.first?.date ?? .distantPast) > ($1.entries.first?.date ?? .distantPast) }
    }

    private var totalPRs: Int { prEntries.count }

    private var prsThisMonth: Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: Date())
        return prEntries.filter {
            let c = cal.dateComponents([.year, .month], from: $0.date)
            return c.year == comps.year && c.month == comps.month
        }.count
    }

    private var prsThisWeek: Int {
        let cal = Calendar.current
        let now = Date()
        // Find Monday of this week
        let weekday = cal.component(.weekday, from: now)
        let daysFromMon = (weekday + 5) % 7
        guard let mondayRaw = cal.date(byAdding: .day, value: -daysFromMon, to: now) else { return 0 }
        let monday = cal.startOfDay(for: mondayRaw)
        return prEntries.filter { $0.date >= monday }.count
    }

    /// Track which exercises have their most recent PR to show a crown
    private var latestPRExercises: Set<String> {
        var latest: [String: Date] = [:]
        for entry in prEntries {
            if latest[entry.exerciseName] == nil || entry.date > latest[entry.exerciseName]! {
                latest[entry.exerciseName] = entry.date
            }
        }
        // Build set of "exerciseName+date" keys for latest PRs
        var result = Set<String>()
        for (name, date) in latest {
            let key = "\(name)_\(date.timeIntervalSince1970)"
            result.insert(key)
        }
        return result
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
                } else if prEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "trophy")
                            .font(.system(size: 40))
                            .foregroundColor(Theme.border)
                        Text("No PRs yet")
                            .font(.headline).foregroundColor(Theme.subtle)
                        Text("Complete workouts to start setting Personal Records.")
                            .font(.caption).foregroundColor(Theme.muted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            summaryHeader.padding(.top, 8)
                            ForEach(groupedByMonth, id: \.month) { group in
                                monthSection(group.month, entries: group.entries)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task { await loadData() }
        .navigationTitle("PR Timeline")
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

    // MARK: - Summary Header

    private var summaryHeader: some View {
        HStack(spacing: 16) {
            summaryChip(count: totalPRs, label: "all time", color: Color(hex: "f59e0b"))
            summaryChip(count: prsThisMonth, label: "this month", color: Theme.accent)
            summaryChip(count: prsThisWeek, label: "this week", color: Color(hex: "38bdf8"))
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

    // MARK: - Month Section

    private func monthSection(_ month: String, entries: [PREntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(month)
                .font(.system(size: 12, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                timelineRow(entry, isLast: index == entries.count - 1)
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Timeline Row

    private func timelineRow(_ entry: PREntry, isLast: Bool) -> some View {
        let isLatest = latestPRExercises.contains("\(entry.exerciseName)_\(entry.date.timeIntervalSince1970)")
        let color = muscleColor(entry.muscleGroup)

        return HStack(alignment: .top, spacing: 12) {
            // Timeline line + dot
            VStack(spacing: 0) {
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.3), lineWidth: 2)
                            .frame(width: 16, height: 16)
                    )
                if !isLast {
                    Rectangle()
                        .fill(Theme.border)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 16)
            .padding(.top, 4)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.exerciseName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    if isLatest {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "f59e0b"))
                    }
                }

                HStack(spacing: 8) {
                    Text(entry.weightKg == 0 ? "\(entry.reps) reps" : "\(entry.weightKg.clean)kg x \(entry.reps)")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.accent)

                    Text("e1RM \(entry.e1rm.clean)kg")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.muted)
                }

                HStack(spacing: 6) {
                    Text(Self.dateFmt.string(from: entry.date))
                        .font(.system(size: 11))
                        .foregroundColor(Theme.muted)

                    Text(entry.muscleGroup)
                        .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.8)
                        .foregroundColor(color)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(color.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.bottom, isLast ? 12 : 14)

            Spacer()
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { store.activeScreen = .progress(entry.exerciseName) }
    }

    // MARK: - Data Loading

    private func loadData() async {
        struct SetRow: Decodable {
            let exerciseName: String
            let weightKg: Double
            let reps: Int
            let loggedAt: Date
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
                case exercises
            }
        }

        let rows: [SetRow]
        do {
            rows = try await SupabaseClient.shared.get(
                "workout_sets?select=exercise_name,weight_kg,reps,logged_at,exercises(muscle_group)" +
                "&order=logged_at.asc"
            )
        } catch {
            errorText = "Failed to load data: \(error.localizedDescription)"
            isLoading = false
            return
        }

        // Group by exercise name
        let byExercise = Dictionary(grouping: rows, by: { $0.exerciseName })

        var allPRs: [PREntry] = []

        for (name, exRows) in byExercise {
            let muscleGroup = exRows.first?.exercises?.muscleGroup ?? "Other"
            let isBodyweight = exRows.allSatisfy { $0.weightKg == 0 }

            // Sort chronologically
            let sorted = exRows.sorted { $0.loggedAt < $1.loggedAt }

            var bestE1RM: Double = 0

            for row in sorted {
                let e1rm = computeE1RM(row.weightKg, row.reps, isBodyweight)
                if e1rm > bestE1RM {
                    bestE1RM = e1rm
                    allPRs.append(PREntry(
                        exerciseName: name,
                        weightKg: row.weightKg,
                        reps: row.reps,
                        e1rm: e1rm,
                        date: row.loggedAt,
                        muscleGroup: muscleGroup
                    ))
                }
            }
        }

        // Sort all PRs by date descending
        allPRs.sort { $0.date > $1.date }

        prEntries = allPRs
        isLoading = false
    }

    private func computeE1RM(_ weight: Double, _ reps: Int, _ isBodyweight: Bool) -> Double {
        if isBodyweight { return Double(reps) }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
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

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}

// MARK: - Model

private struct PREntry: Identifiable {
    let id = UUID()
    let exerciseName: String
    let weightKg: Double
    let reps: Int
    let e1rm: Double
    let date: Date
    let muscleGroup: String
}
