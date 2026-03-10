import SwiftUI

struct MuscleBalanceView: View {
    @Environment(WorkoutStore.self) var store

    @State private var muscleData: [(muscle: String, sets: Int)] = []
    @State private var isLoading = true

    private var balanceItems: [BalanceItem] {
        muscleData.compactMap { item in
            guard let target = volumeTarget(for: item.muscle) else { return nil }
            let score = muscleScore(sets: item.sets, target: target)
            return BalanceItem(
                muscle: item.muscle,
                sets: item.sets,
                target: target,
                score: score
            )
        }.sorted { $0.muscle < $1.muscle }
    }

    private var overallScore: Int {
        guard !balanceItems.isEmpty else { return 0 }
        let total = balanceItems.reduce(0.0) { $0 + $1.score }
        return Int((total / Double(balanceItems.count)).rounded())
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if isLoading {
                ProgressView().tint(Theme.accent)
            } else if muscleData.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.pie")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.border)
                    Text("No data this week")
                        .font(.headline).foregroundColor(Theme.subtle)
                    Text("Complete some workouts and your muscle balance will appear here.")
                        .font(.caption).foregroundColor(Theme.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        scoreRing.padding(.top, 12)
                        muscleList
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .task { await loadWeekMuscleData() }
        .navigationTitle("Muscle Balance")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.activeScreen = store.previousScreen } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Week")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
        }
    }

    // MARK: - Data loading

    private func loadWeekMuscleData() async {
        let weekStats = await store.loadWeekData()
        var counts: [String: Int] = [:]
        for ws in weekStats {
            for item in ws.muscleSplit {
                counts[item.muscle, default: 0] += item.sets
            }
        }
        muscleData = counts
            .map { (muscle: $0.key, sets: $0.value) }
            .sorted { $0.sets > $1.sets }
        isLoading = false
    }

    // MARK: - Score ring

    private var scoreRing: some View {
        let color = scoreColor(overallScore)
        return VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Theme.border, lineWidth: 10)
                    .frame(width: 140, height: 140)
                Circle()
                    .trim(from: 0, to: CGFloat(overallScore) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 140, height: 140)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.8), value: overallScore)
                VStack(spacing: 2) {
                    Text("\(overallScore)")
                        .font(.system(size: 42, weight: .black))
                        .foregroundColor(color)
                    Text("BALANCE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundColor(Theme.subtle)
                }
            }
            Text(scoreLabel(overallScore))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(color)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Muscle list

    private var muscleList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Muscle Groups")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            ForEach(balanceItems) { item in
                muscleRow(item)
                if item.id != balanceItems.last?.id {
                    Divider().padding(.leading, 16).background(Theme.border)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    private func muscleRow(_ item: BalanceItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(muscleColor(item.muscle))
                    .frame(width: 8, height: 8)
                Text(item.muscle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(item.sets) sets")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(barColor(item))
                Text("\(item.target.lowerBound)-\(item.target.upperBound)")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.muted)
            }

            GeometryReader { geo in
                let cap = Double(item.target.upperBound) + 4
                let fillFrac = CGFloat(min(Double(item.sets), cap)) / CGFloat(cap)
                let minFrac = CGFloat(item.target.lowerBound) / CGFloat(cap)
                let maxFrac = CGFloat(item.target.upperBound) / CGFloat(cap)

                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.bg)
                        .frame(height: 8)

                    // Target range zone
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent.opacity(0.1))
                        .frame(
                            width: geo.size.width * (maxFrac - minFrac),
                            height: 8
                        )
                        .offset(x: geo.size.width * minFrac)

                    // Min marker
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1.5, height: 12)
                        .offset(x: geo.size.width * minFrac - 0.75, y: -2)

                    // Max marker
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 1.5, height: 12)
                        .offset(x: geo.size.width * maxFrac - 0.75, y: -2)

                    // Actual fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor(item))
                        .frame(width: max(4, geo.size.width * fillFrac), height: 8)
                        .animation(.easeOut(duration: 0.5), value: item.sets)
                }
            }
            .frame(height: 12)

            // Score badge
            HStack(spacing: 4) {
                Text("Score: \(Int(item.score.rounded()))%")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(barColor(item))
                if item.sets < item.target.lowerBound {
                    Text("Need \(item.target.lowerBound - item.sets) more sets")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.muted)
                } else if item.sets > item.target.upperBound {
                    Text("Over by \(item.sets - item.target.upperBound) sets")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "f59e0b"))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    // MARK: - Scoring

    private func muscleScore(sets: Int, target: ClosedRange<Int>) -> Double {
        if target.contains(sets) { return 100 }
        if sets < target.lowerBound {
            return Double(sets) / Double(target.lowerBound) * 100
        }
        // Over maximum — penalize
        let over = sets - target.upperBound
        return max(0, 100 - Double(over) * 10)
    }

    private func barColor(_ item: BalanceItem) -> Color {
        if item.score >= 90 { return Theme.accent }
        if item.score >= 60 { return Color(hex: "f59e0b") }
        return Color(hex: "ef4444")
    }

    private func scoreColor(_ score: Int) -> Color {
        if score > 80 { return Theme.accent }
        if score >= 60 { return Color(hex: "f59e0b") }
        return Color(hex: "ef4444")
    }

    private func scoreLabel(_ score: Int) -> String {
        if score > 80 { return "Well Balanced" }
        if score >= 60 { return "Needs Attention" }
        return "Imbalanced"
    }

    // MARK: - Volume targets (same as WeeklyView)

    private func volumeTarget(for muscle: String) -> ClosedRange<Int>? {
        let m = muscle.lowercased()
        if m.contains("chest") || m.contains("pec")       { return 10...16 }
        if m.contains("back")  || m.contains("lat")       { return 14...20 }
        if m.contains("shoulder") || m.contains("delt")   { return 10...14 }
        if m.contains("tricep")                            { return 8...14 }
        if m.contains("bicep")                             { return 8...14 }
        if m.contains("quad") || m.contains("leg")        { return 10...16 }
        if m.contains("hamstring")                         { return 6...12 }
        if m.contains("glute")                             { return 8...14 }
        if m.contains("calf")                              { return 6...10 }
        if m.contains("core") || m.contains("ab")         { return 6...12 }
        if m.contains("forearm")                           { return 4...8 }
        return nil
    }

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

// MARK: - Balance item model

private struct BalanceItem: Identifiable {
    let id = UUID()
    let muscle: String
    let sets: Int
    let target: ClosedRange<Int>
    let score: Double
}
