#if !SONYA
import SwiftUI

struct CardioWeekCard: View {
    let sessions: [Date]

    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"]
    private let cardioBlue = Color(hex: "38bdf8")

    private var phase: CardioPhase { CardioPhase.current() }
    private var goal: Int { phase.weeklyGoal }

    // Monday-based day indices (0=Mon … 6=Sun) that have a cardio session
    private var completedDayIndices: Set<Int> {
        let cal = Calendar.current
        var indices = Set<Int>()
        for date in sessions {
            let wd = cal.component(.weekday, from: date) // 1=Sun … 7=Sat
            let idx = wd == 1 ? 6 : wd - 2              // Mon=0 … Sun=6
            indices.insert(idx)
        }
        return indices
    }

    private var todayIndex: Int {
        let wd = Calendar.current.component(.weekday, from: Date())
        return wd == 1 ? 6 : wd - 2
    }

    var body: some View {
        let done = sessions.count
        let completed = completedDayIndices

        VStack(spacing: 12) {
            // Header
            HStack {
                Image(systemName: "figure.run")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(cardioBlue)
                Text("Cardio This Week")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(done) / \(goal)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(done >= goal ? Color(hex: "4ade80") : cardioBlue)
            }

            // Day dots
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 6) {
                        Text(dayLabels[i])
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(i == todayIndex ? .white : Theme.muted)

                        ZStack {
                            Circle()
                                .fill(completed.contains(i) ? cardioBlue : Theme.border)
                                .frame(width: 28, height: 28)

                            if completed.contains(i) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.black)
                            } else if i == todayIndex {
                                Circle()
                                    .stroke(cardioBlue, lineWidth: 1.5)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Theme.border)
                        .frame(height: 6)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(done >= goal ? Color(hex: "4ade80") : cardioBlue)
                        .frame(width: geo.size.width * min(1, CGFloat(done) / CGFloat(max(goal, 1))), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
#endif
