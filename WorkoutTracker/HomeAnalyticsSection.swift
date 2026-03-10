import SwiftUI

// MARK: - Analytics Section
/// Bottom area of HomeView: volume card, recovery card, and navigation buttons
/// for overload tracker, duration analytics, muscle volume, body composition,
/// and PR timeline.

struct HomeAnalyticsSection: View {
    @Environment(WorkoutStore.self) var store

    let weekStats: [WorkoutWeekStats]
    let lastWeekVol: Double
    let recoveryData: [MuscleRecovery]

    private var thisWeekVolume: Double { weekStats.reduce(0) { $0 + $1.volume } }

    private func volLabel(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.0f k", v / 1000) : String(format: "%.0f", v)
    }

    var body: some View {
        VStack(spacing: 0) {
            volumeCard
            if !recoveryData.isEmpty {
                recoveryCard
            }
            overloadTrackerButton
            durationAnalyticsButton
            muscleVolumeButton
            bodyCompositionButton
            prTimelineButton
        }
    }

    // MARK: - Volume Card

    private var volumeCard: some View {
        let vol = thisWeekVolume
        let pct: Double? = lastWeekVol > 0 ? (vol - lastWeekVol) / lastWeekVol * 100 : nil

        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Volume")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                    .foregroundColor(Theme.subtle)
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text(vol > 0 ? "\(volLabel(vol)) kg" : "--")
                        .font(.system(size: 28, weight: .black))
                        .foregroundColor(.white)
                    if vol > 0 {
                        Text("this week")
                            .font(.caption2)
                            .foregroundColor(Color(hex: "475569"))
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                if let p = pct {
                    HStack(spacing: 3) {
                        Image(systemName: p >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 10, weight: .bold))
                        Text(String(format: "%+.0f%%", p))
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(p >= 0 ? Theme.accent : Color(hex: "f87171"))
                }
                if lastWeekVol > 0 {
                    Text("vs \(volLabel(lastWeekVol)) kg last wk")
                        .font(.caption2)
                        .foregroundColor(Color(hex: "475569"))
                }
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Muscle Recovery Card

    private var recoveryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Muscle Recovery")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recoveryData, id: \.muscle) { item in
                        HStack(spacing: 6) {
                            Text(item.muscle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Color(hex: "e2e8f0"))
                            Text(item.daysSince == 0 ? "today" : "\(item.daysSince)d")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(Color(hex: item.recoveryColor))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: item.recoveryColor).opacity(0.15))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Theme.bg)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(hex: item.recoveryColor).opacity(0.5), lineWidth: 1)
                        )
                    }
                }
                .padding(.horizontal, 2)
            }

            HStack(spacing: 14) {
                legendDot("ef4444", "0\u{2013}1d fresh")
                legendDot("f59e0b", "2d partial")
                legendDot("22c55e", "3d+ ready")
            }
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func legendDot(_ hex: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Color(hex: hex)).frame(width: 7, height: 7)
            Text(label).font(.caption2).foregroundColor(Theme.muted)
        }
    }

    // MARK: - Navigation Buttons

    private var overloadTrackerButton: some View {
        navButton(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: "38bdf8",
            title: "Overload Tracker",
            subtitle: "Track progression across all exercises",
            screen: .overloadTracker
        )
    }

    private var durationAnalyticsButton: some View {
        navButton(
            icon: "clock.arrow.circlepath",
            iconColor: "a855f7",
            title: "Duration Analytics",
            subtitle: "Workout duration trends over time",
            screen: .durationAnalytics
        )
    }

    private var muscleVolumeButton: some View {
        navButton(
            icon: "figure.strengthtraining.traditional",
            iconColor: "34d399",
            title: "Muscle Volume",
            subtitle: "Weekly sets per muscle group",
            screen: .muscleVolume
        )
    }

    private var bodyCompositionButton: some View {
        navButton(
            icon: "waveform.path.ecg",
            iconColor: "f472b6",
            title: "Body Composition",
            subtitle: "Weight, volume & photo trends",
            screen: .bodyComposition
        )
    }

    private var prTimelineButton: some View {
        navButton(
            icon: "trophy.fill",
            iconColor: "f59e0b",
            title: "PR Timeline",
            subtitle: "Chronological history of all Personal Records",
            screen: .prTimeline
        )
    }

    private func navButton(icon: String, iconColor: String, title: String, subtitle: String, screen: AppScreen) -> some View {
        Button { store.activeScreen = screen } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: iconColor))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.subtle)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }
}
