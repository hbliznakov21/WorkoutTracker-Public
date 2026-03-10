import SwiftUI

// MARK: - Stats Section
/// Middle area of HomeView: streak/week row, PR card, body weight card,
/// photo comparison card.

struct HomeStatsSection: View {
    @Environment(WorkoutStore.self) var store
    @Environment(PhotoStore.self) var photoStore

    @Binding var showQuickCamera: Bool

    @State private var weightInsight: WeightInsight?
    @State private var weightInsightLoading = false
    @State private var weightInsightDismissed = false

    var body: some View {
        VStack(spacing: 0) {
            #if !SONYA
            CardioWeekCard(sessions: store.cardioThisWeek)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            #endif
            if !store.bodyWeightLog.isEmpty {
                bodyWeightCard
            }
            if weightInsightLoading {
                weightInsightLoadingCard
            } else if let insight = weightInsight, !weightInsightDismissed {
                weightInsightCard(insight)
            }
            photoComparisonCard
        }
        .padding(.top, 10)
        .task {
            guard store.bodyWeightLog.count >= 5 else { return }
            weightInsightLoading = true
            weightInsight = await store.generateWeightInsight()
            weightInsightLoading = false
        }
        .onChange(of: store.bodyWeightLog.count) { _, count in
            guard count >= 5, weightInsight == nil, !weightInsightLoading else { return }
            weightInsightLoading = true
            Task {
                weightInsight = await store.generateWeightInsight()
                weightInsightLoading = false
            }
        }
    }

    // MARK: - Weight AI Insight

    private var weightInsightLoadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color(hex: "a855f7"))
                .scaleEffect(0.8)
            Text("AI analyzing weight trend...")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.subtle)
            Spacer()
        }
        .padding(12)
        .background(Color(hex: "a855f7").opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "a855f7").opacity(0.2)))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private func weightInsightCard(_ insight: WeightInsight) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "a855f7"))
                Text("AI Weight Analysis")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
                Spacer()
                Text(insight.actionLabel)
                    .font(.system(size: 9, weight: .black)).tracking(0.5)
                    .foregroundColor(Color(hex: insight.actionColor))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: insight.actionColor).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                Button {
                    withAnimation { weightInsightDismissed = true }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.muted)
                }
            }

            Text(insight.suggestion)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(hex: "e2e8f0"))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    Image(systemName: insight.weeklyRate >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%+.2f kg/wk", insight.weeklyRate))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundColor(Color(hex: insight.actionColor))

                if insight.confidence != "high" {
                    HStack(spacing: 3) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                        Text("\(insight.confidence) confidence")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(hex: "a855f7").opacity(0.06), Theme.surface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "a855f7").opacity(0.3)))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Body weight card

    private var recentWeights: [BodyWeight] { Array(store.bodyWeightLog.suffix(14)) }

    private var sevenDayAvg: Double? {
        let w = store.bodyWeightLog.suffix(7).map(\.weightKg)
        guard !w.isEmpty else { return nil }
        return w.reduce(0, +) / Double(w.count)
    }

    private var weeklyTrend: Double? {
        let e = Array(store.bodyWeightLog.suffix(30))
        guard e.count >= 3 else { return nil }
        let n   = Double(e.count)
        let xs  = (0..<e.count).map(Double.init)
        let ys  = e.map(\.weightKg)
        let sx  = xs.reduce(0, +); let sy = ys.reduce(0, +)
        let sxy = zip(xs, ys).map(*).reduce(0, +)
        let sx2 = xs.map { $0 * $0 }.reduce(0, +)
        let d   = n * sx2 - sx * sx
        guard d != 0 else { return nil }
        return (n * sxy - sx * sy) / d * 7
    }

    private var bodyWeightCard: some View {
        let latest = store.bodyWeightLog.last
        return VStack(alignment: .leading, spacing: 10) {
            Text("Body Weight")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(latest.map { "\($0.weightKg.clean) kg" } ?? "--")
                        .font(.system(size: 30, weight: .black))
                        .foregroundColor(.white)
                    Text(latest?.dayLabel ?? "")
                        .font(.caption2)
                        .foregroundColor(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    if let t = weeklyTrend {
                        HStack(spacing: 3) {
                            Image(systemName: t >= 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(format: "%+.2f kg/wk", t))
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(t >= 0 ? Color(hex: "f59e0b") : Theme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background((t >= 0 ? Color(hex: "f59e0b") : Theme.accent).opacity(0.12))
                        .clipShape(Capsule())
                    }
                    if let a = sevenDayAvg {
                        Text(String(format: "avg %.1f kg", a))
                            .font(.caption2)
                            .foregroundColor(Color(hex: "475569"))
                    }
                }
            }
            sparkline
        }
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
        .onTapGesture { store.activeScreen = .body }
    }

    @ViewBuilder
    private var sparkline: some View {
        let weights = recentWeights.map(\.weightKg)
        if weights.count >= 2 {
            let minW  = weights.min() ?? 0
            let maxW  = weights.max() ?? 0
            let range = max(maxW - minW, 0.5)
            GeometryReader { geo in
                let w    = geo.size.width
                let h    = geo.size.height
                let step = w / CGFloat(weights.count - 1)
                Path { path in
                    for (i, weight) in weights.enumerated() {
                        let x = CGFloat(i) * step
                        let y = h - CGFloat((weight - minW) / range) * (h - 6) - 3
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else      { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Theme.accent,
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if let last = weights.last {
                    let x = CGFloat(weights.count - 1) * step
                    let y = h - CGFloat((last - minW) / range) * (h - 6) - 3
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 7, height: 7)
                        .position(x: x, y: y)
                }
            }
            .frame(height: 40)
        }
    }

    // MARK: - Photo Comparison Card

    private var photoComparisonCard: some View {
        let dates = photoStore.allDates
        let oldestDate = dates.last
        let latestDate = dates.first

        return Group {
            if dates.count >= 2, let oldest = oldestDate, let latest = latestDate, oldest != latest {
                let oldestEntry = photoStore.entries(for: oldest).first
                let latestEntry = photoStore.entries(for: latest).first

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Progress Photos")
                            .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                            .foregroundColor(Theme.subtle)
                        Spacer()
                        Button { showQuickCamera = true } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.accent)
                        }
                    }

                    HStack(spacing: 12) {
                        photoThumbnailColumn(label: "Start", dateStr: oldest, entry: oldestEntry)
                        photoThumbnailColumn(label: "Latest", dateStr: latest, entry: latestEntry)
                    }

                    if let daysBetween = daysBetweenDates(oldest, latest) {
                        HStack {
                            Spacer()
                            Text(progressDurationLabel(daysBetween))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Theme.muted)
                            Spacer()
                        }
                    }

                    Button { store.activeScreen = .photoCompare } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "slider.horizontal.below.rectangle")
                                .font(.system(size: 12, weight: .bold))
                            Text("Compare")
                                .font(.system(size: 13, weight: .bold))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent)
                        .foregroundColor(.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .onTapGesture { store.activeScreen = .photos }

            } else if dates.count == 1, let only = dates.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Progress Photos")
                            .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                            .foregroundColor(Theme.subtle)
                        Spacer()
                        Button { showQuickCamera = true } label: {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(Theme.accent)
                        }
                    }
                    HStack(spacing: 12) {
                        if let entry = photoStore.entries(for: only).first,
                           let img = photoStore.loadImage(for: entry) {
                            Image(uiImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 80, height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1 session captured")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                            Text("Take another to see your progress side by side")
                                .font(.system(size: 11))
                                .foregroundColor(Theme.subtle)
                        }
                    }
                }
                .padding(16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .onTapGesture { store.activeScreen = .photos }

            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.border)
                    Text("Take your first progress photo")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Theme.muted)
                    Text("Track your transformation with weekly photos")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "475569"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
                .onTapGesture { store.activeScreen = .photos }
            }
        }
    }

    private func photoThumbnailColumn(label: String, dateStr: String, entry: PhotoEntry?) -> some View {
        VStack(spacing: 6) {
            if let entry = entry, let img = photoStore.loadImage(for: entry) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 120, height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.bg)
                    .frame(width: 120, height: 120)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundColor(Theme.muted)
                    )
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border, lineWidth: 1))
            }
            Text(label)
                .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(1)
                .foregroundColor(Theme.subtle)
            Text(photoDisplayDate(dateStr))
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "e2e8f0"))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Photo helpers

    private static let photoISOFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    private static let photoDisplayFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    private func photoDisplayDate(_ dateStr: String) -> String {
        guard let date = Self.photoISOFmt.date(from: dateStr) else { return dateStr }
        return Self.photoDisplayFmt.string(from: date)
    }

    private func daysBetweenDates(_ from: String, _ to: String) -> Int? {
        guard let d1 = Self.photoISOFmt.date(from: from),
              let d2 = Self.photoISOFmt.date(from: to) else { return nil }
        return Calendar.current.dateComponents([.day], from: d1, to: d2).day
    }

    private func progressDurationLabel(_ days: Int) -> String {
        if days < 7 {
            return "\(days) day\(days == 1 ? "" : "s") apart"
        } else {
            let weeks = days / 7
            let remaining = days % 7
            if remaining == 0 {
                return "\(weeks) week\(weeks == 1 ? "" : "s") progress"
            } else {
                return "\(days) days apart"
            }
        }
    }

}
