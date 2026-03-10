import SwiftUI

struct MuscleVolumeView: View {
    @Environment(WorkoutStore.self) var store

    @State private var thisWeekData: [MuscleGroupVolume] = []
    @State private var lastWeekData: [MuscleGroupVolume] = []
    @State private var isLoading = true
    @State private var errorText: String?

    // MARK: - Muscle group mapping

    private static let exerciseToMuscle: [String: String] = [
        // Chest
        "Incline Barbell Bench Press": "Chest",
        "Incline Dumbbell Press": "Chest",
        "Dumbbell Bench Press": "Chest",
        "Chest Press Machine": "Chest",
        "Incline Dumbbell Fly": "Chest",
        "Cable Fly (High to Low)": "Chest",
        // Back
        "Single Arm Lat Pulldown": "Back",
        "Straight Arm Pulldown": "Back",
        "Seated Cable Row (V-Grip)": "Back",
        "Seated Cable Row (Wide Grip)": "Back",
        "Single Arm Cable Row": "Back",
        "T-Bar Row": "Back",
        "Chest Supported Row": "Back",
        "Lat Pulldown (Wide Grip)": "Back",
        "Lat Pulldown (Close Grip)": "Back",
        "Dumbbell Row": "Back",
        "Dumbbell Pullover": "Back",
        // Shoulders
        "Dumbbell Shoulder Press": "Shoulders",
        "Machine Shoulder Press": "Shoulders",
        "Lateral Raise": "Shoulders",
        "Cable Lateral Raise": "Shoulders",
        "Rear Delt Fly (Cable)": "Shoulders",
        "Rear Delt Fly (Dumbbell)": "Shoulders",
        "Face Pull": "Shoulders",
        "Front Raise (Cable)": "Shoulders",
        // Biceps
        "Seated Incline Curl": "Biceps",
        "Hammer Curl": "Biceps",
        "Cable Curl": "Biceps",
        "Preacher Curl (Dumbbell)": "Biceps",
        "Preacher Curl (EZ Bar)": "Biceps",
        "Behind the Back Curl (Cable)": "Biceps",
        // Triceps
        "Overhead Triceps Extension (Cable)": "Triceps",
        "Triceps Rope Pushdown": "Triceps",
        "Single Arm Pushdown": "Triceps",
        // Quads
        "Pendulum Squat (Machine)": "Quads",
        "Smith Machine Squat": "Quads",
        "Barbell Back Squat": "Quads",
        "Bulgarian Split Squat": "Quads",
        "Leg Extension": "Quads",
        "Single Leg Press": "Quads",
        // Hamstrings
        "Romanian Deadlift": "Hamstrings",
        "Seated Leg Curl": "Hamstrings",
        "Lying Leg Curl": "Hamstrings",
        // Glutes
        "Hip Thrust (Barbell)": "Glutes",
        "Hip Thrust (Smith Machine)": "Glutes",
        "Leg Adductor Machine": "Glutes",
        "Machine Hip Abduction": "Glutes",
        // Calves
        "Calf Press": "Calves",
        "Seated Calf Raise": "Calves",
        "Standing Calf Raise": "Calves",
        // Core
        "Ab Wheel Rollout": "Core",
        "Cable Crunch": "Core",
    ]

    private static let muscleGroupOrder: [String] = [
        "Chest", "Back", "Shoulders", "Quads", "Hamstrings",
        "Glutes", "Biceps", "Triceps", "Calves", "Core"
    ]

    // MARK: - Model

    struct MuscleGroupVolume: Identifiable {
        let id = UUID()
        let muscleGroup: String
        let sets: Int
    }

    // MARK: - Computed

    private var maxSets: Int {
        max(
            thisWeekData.map(\.sets).max() ?? 1,
            lastWeekData.map(\.sets).max() ?? 1,
            20 // minimum scale so bars look proportional
        )
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
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            legendRow.padding(.top, 8)
                            ForEach(Self.muscleGroupOrder, id: \.self) { group in
                                muscleRow(group)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .task { await loadData() }
        .navigationTitle("Muscle Volume")
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

    // MARK: - Legend

    private var legendRow: some View {
        HStack(spacing: 20) {
            legendDot(color: Theme.accent, label: "This week")
            legendDot(color: Theme.muted, label: "Last week")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("Optimal: 10-20 sets")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.subtle)
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Theme.subtle)
        }
    }

    // MARK: - Muscle row

    private func muscleRow(_ group: String) -> some View {
        let thisWeek = thisWeekData.first(where: { $0.muscleGroup == group })?.sets ?? 0
        let lastWeek = lastWeekData.first(where: { $0.muscleGroup == group })?.sets ?? 0
        let barColor = statusColor(sets: thisWeek)
        let delta = thisWeek - lastWeek

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(group)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                HStack(spacing: 4) {
                    Text("\(thisWeek) sets")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(barColor)
                    if delta != 0 {
                        Text(delta > 0 ? "+\(delta)" : "\(delta)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(delta > 0 ? Theme.accent : Color(hex: "ef4444"))
                    }
                }
            }

            // This week bar
            barView(sets: thisWeek, color: barColor)

            // Last week bar (dimmer)
            barView(sets: lastWeek, color: Theme.muted)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border))
    }

    private func barView(sets: Int, color: Color) -> some View {
        GeometryReader { geo in
            let fraction = sets > 0 ? CGFloat(sets) / CGFloat(maxSets) : 0
            RoundedRectangle(cornerRadius: 4)
                .fill(color)
                .frame(width: max(fraction * geo.size.width, sets > 0 ? 4 : 0))
        }
        .frame(height: 10)
    }

    private func statusColor(sets: Int) -> Color {
        if sets >= 10 {
            return Theme.accent                     // green — on target
        } else if sets >= 5 {
            return Color(hex: "eab308")             // yellow — below target
        } else {
            return Color(hex: "ef4444")             // red — way below
        }
    }

    // MARK: - Data loading

    private struct SetRow: Decodable {
        let exerciseName: String
        let loggedAt: Date

        enum CodingKeys: String, CodingKey {
            case exerciseName = "exercise_name"
            case loggedAt     = "logged_at"
        }
    }

    private func loadData() async {
        let cal = Calendar.current
        let now = Date()

        // Find Monday of this week (Monday-based)
        let weekday = cal.component(.weekday, from: now)
        let daysToMon = weekday == 1 ? -6 : 2 - weekday
        guard let thisMonday = cal.date(byAdding: .day, value: daysToMon, to: cal.startOfDay(for: now)),
              let lastMonday = cal.date(byAdding: .day, value: -7, to: thisMonday) else {
            errorText = "Could not compute week boundaries"
            isLoading = false
            return
        }

        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]

        let thisMonISO = isoFmt.string(from: thisMonday)
        let lastMonISO = isoFmt.string(from: lastMonday)
        // Next Monday = upper bound for this week
        let nextMonday = cal.date(byAdding: .day, value: 7, to: thisMonday)!
        let nextMonISO = isoFmt.string(from: nextMonday)

        do {
            // Fetch this week sets
            let thisRows: [SetRow] = try await SupabaseClient.shared.get(
                "workout_sets?select=exercise_name,logged_at" +
                "&logged_at=gte.\(thisMonISO)" +
                "&logged_at=lt.\(nextMonISO)" +
                "&order=logged_at.asc"
            )

            // Fetch last week sets
            let lastRows: [SetRow] = try await SupabaseClient.shared.get(
                "workout_sets?select=exercise_name,logged_at" +
                "&logged_at=gte.\(lastMonISO)" +
                "&logged_at=lt.\(thisMonISO)" +
                "&order=logged_at.asc"
            )

            thisWeekData = aggregateSets(thisRows)
            lastWeekData = aggregateSets(lastRows)
        } catch {
            errorText = "Failed to load data: \(error.localizedDescription)"
        }

        isLoading = false
    }

    private func aggregateSets(_ rows: [SetRow]) -> [MuscleGroupVolume] {
        var counts: [String: Int] = [:]
        for row in rows {
            guard let muscle = Self.exerciseToMuscle[row.exerciseName] else { continue }
            counts[muscle, default: 0] += 1
        }
        return counts.map { MuscleGroupVolume(muscleGroup: $0.key, sets: $0.value) }
    }
}
