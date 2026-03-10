import SwiftUI

// MARK: - Substitution Data

enum ExerciseSubstitutions {

    /// Muscle group -> list of interchangeable exercise names
    static let groups: [String: [[String]]] = [
        "Chest": [
            ["Incline Bench", "Incline Dumbbell Press", "Machine Chest Press", "Cable Fly",
             "Incline Bench Press", "Flat Bench Press", "Chest Press", "Incline Fly"]
        ],
        "Back": [
            ["Lat Pulldown", "Pull-ups", "T-Bar Row", "Seated Cable Row",
             "Single Arm Lat Pulldown", "Straight Arm Pulldown", "Chest Supported Row",
             "Seated Cable Row Wide", "Seated Cable Row V-Grip", "Lat Pulldown Wide"]
        ],
        "Shoulders": [
            ["OHP", "Seated Dumbbell Press", "Machine Shoulder Press", "Arnold Press",
             "Seated OHP", "Overhead Press", "Lateral Raise", "Rear Delt Fly"]
        ],
        "Triceps": [
            ["Skull Crushers", "Overhead Tricep Extension", "Rope Pushdown", "Close Grip Bench",
             "Tricep Pushdown", "Cable Pushdown"]
        ],
        "Biceps": [
            ["Barbell Curl", "Incline Curl", "Hammer Curl", "Cable Curl",
             "EZ Bar Curl", "Concentration Curl"]
        ],
        "Quads": [
            ["Hack Squat", "Leg Press", "Leg Extension", "Bulgarian Split Squat",
             "Smith Squat", "Single Leg Press", "Goblet Squat"]
        ],
        "Hamstrings": [
            ["RDL", "Lying Leg Curl", "Seated Leg Curl", "Good Morning",
             "Romanian Deadlift", "Stiff Leg Deadlift"]
        ],
        "Glutes": [
            ["Hip Thrust", "Cable Kickback", "Glute Bridge", "Sumo Deadlift"]
        ],
        "Calves": [
            ["Calf Press", "Seated Calf Raise", "Standing Calf Raise",
             "Calf Raise", "Donkey Calf Raise"]
        ],
        "Core": [
            ["Cable Crunch", "Ab Wheel", "Pallof Press", "Hanging Leg Raise",
             "Plank", "Russian Twist"]
        ]
    ]

    /// Fuzzy-match an exercise name from the DB to a known substitution name.
    /// Returns the muscle group key and the index within that group's alternatives.
    private static func findMatch(for exerciseName: String) -> (muscle: String, groupIndex: Int, matchIndex: Int)? {
        let lower = exerciseName.lowercased()

        for (muscle, alternativeGroups) in groups {
            for (gIdx, alternatives) in alternativeGroups.enumerated() {
                for (aIdx, alt) in alternatives.enumerated() {
                    let altLower = alt.lowercased()
                    // Exact match
                    if lower == altLower { return (muscle, gIdx, aIdx) }
                    // DB name contains the substitution name
                    if lower.contains(altLower) { return (muscle, gIdx, aIdx) }
                    // Substitution name contains the DB name (for short names like "RDL")
                    if altLower.contains(lower) && lower.count >= 3 { return (muscle, gIdx, aIdx) }
                }
            }
        }
        return nil
    }

    /// Get substitution suggestions for a given exercise name.
    /// Returns up to `limit` alternative exercise names (excluding the matched one).
    static func suggestions(for exerciseName: String, limit: Int = 3) -> [String] {
        guard let match = findMatch(for: exerciseName) else { return [] }

        guard let muscleGroups = groups[match.muscle],
              match.groupIndex < muscleGroups.count else { return [] }
        let alternatives = muscleGroups[match.groupIndex]
        guard match.matchIndex < alternatives.count else { return [] }
        let matchedName = alternatives[match.matchIndex]

        // Return alternatives that aren't the matched exercise
        return alternatives
            .filter { $0 != matchedName }
            .prefix(limit)
            .map { $0 }
    }

    /// Get the muscle group for a given exercise name via fuzzy match.
    static func muscleGroup(for exerciseName: String) -> String? {
        findMatch(for: exerciseName)?.muscle
    }

    /// All muscle groups with their alternatives (for the standalone browser).
    static var allMuscleGroups: [(muscle: String, exercises: [String])] {
        let order = ["Chest", "Back", "Shoulders", "Triceps", "Biceps",
                     "Quads", "Hamstrings", "Glutes", "Calves", "Core"]
        return order.compactMap { muscle in
            guard let alts = groups[muscle]?.first else { return nil }
            return (muscle: muscle, exercises: alts)
        }
    }
}

// MARK: - Substitution Browser View

struct SubstitutionView: View {
    @Environment(WorkoutStore.self) var store

    @State private var searchText = ""

    private var filtered: [(muscle: String, exercises: [String])] {
        let all = ExerciseSubstitutions.allMuscleGroups
        if searchText.isEmpty { return all }
        let q = searchText.lowercased()
        return all.compactMap { group in
            let matches = group.exercises.filter { $0.lowercased().contains(q) }
            if matches.isEmpty && !group.muscle.lowercased().contains(q) { return nil }
            // If muscle name matches, show all; otherwise show only matching exercises
            if group.muscle.lowercased().contains(q) {
                return group
            }
            return (muscle: group.muscle, exercises: matches)
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(Theme.border)
                    Text("No matches")
                        .font(.headline).foregroundColor(Theme.subtle)
                }
            } else {
                ScrollView {
                    VStack(spacing: 14) {
                        ForEach(filtered, id: \.muscle) { group in
                            muscleCard(group.muscle, exercises: group.exercises)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search exercises...")
        .navigationTitle("Substitutions")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.activeScreen = store.previousScreen } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    private func muscleCard(_ muscle: String, exercises: [String]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(muscleColor(muscle))
                    .frame(width: 8, height: 8)
                Text(muscle)
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                    .foregroundColor(Theme.subtle)
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            // Exercise chips in a flow layout
            FlowLayout(spacing: 8) {
                ForEach(exercises, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(muscleColor(muscle).opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(muscleColor(muscle).opacity(0.4), lineWidth: 1)
                        )
                        .onTapGesture {
                            store.activeScreen = .progress(name)
                        }
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 14)

            // Swap hint
            HStack(spacing: 4) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9))
                Text("All exercises in this group can substitute for each other")
                    .font(.system(size: 10))
            }
            .foregroundColor(Theme.muted)
            .padding(.horizontal, 16).padding(.bottom, 12)
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    private func muscleColor(_ muscle: String) -> Color {
        let m = muscle.lowercased()
        if m.contains("chest")      { return Theme.accent }
        if m.contains("back")       { return Color(hex: "3b82f6") }
        if m.contains("shoulder")   { return Color(hex: "a855f7") }
        if m.contains("tricep")     { return Color(hex: "f97316") }
        if m.contains("bicep")      { return Color(hex: "ec4899") }
        if m.contains("quad")       { return Color(hex: "ef4444") }
        if m.contains("hamstring")  { return Color(hex: "dc2626") }
        if m.contains("glute")      { return Color(hex: "f59e0b") }
        if m.contains("calf")       { return Color(hex: "14b8a6") }
        if m.contains("core")       { return Color(hex: "eab308") }
        return Theme.muted
    }
}

// MARK: - Flow Layout (for wrapping chips)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, offset) in result.offsets.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (offsets: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (offsets, CGSize(width: maxX, height: y + rowHeight))
    }
}
