import Foundation

struct WarmUpSet: Identifiable {
    let id = UUID()
    let weight: Double
    let reps: Int
    let label: String   // e.g. "Empty bar", "40%", "60%", "80%"
}

enum WarmUpGenerator {

    /// Generate progressive warm-up sets for a given working weight.
    /// Returns empty array for bodyweight exercises (weight = 0) or very light weights.
    static func generate(workingWeight: Double) -> [WarmUpSet] {
        guard workingWeight > 0 else { return [] }

        var sets: [WarmUpSet] = []

        // Set 1: Empty bar (20kg) x 10 — skip if working weight <= 30kg
        if workingWeight > 30 {
            sets.append(WarmUpSet(weight: 20, reps: 10, label: "Empty bar"))
        }

        // Set 2: 40% x 8
        let w40 = roundToNearest2_5(workingWeight * 0.40)
        if w40 > 0 {
            sets.append(WarmUpSet(weight: w40, reps: 8, label: "40%"))
        }

        // Set 3: 60% x 5
        let w60 = roundToNearest2_5(workingWeight * 0.60)
        if w60 > w40 {
            sets.append(WarmUpSet(weight: w60, reps: 5, label: "60%"))
        }

        // Set 4: 80% x 3
        let w80 = roundToNearest2_5(workingWeight * 0.80)
        if w80 > w60 {
            sets.append(WarmUpSet(weight: w80, reps: 3, label: "80%"))
        }

        return sets
    }

    private static func roundToNearest2_5(_ value: Double) -> Double {
        (value / 2.5).rounded() * 2.5
    }
}
