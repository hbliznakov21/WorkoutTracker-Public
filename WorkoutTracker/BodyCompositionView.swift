import SwiftUI
import Charts

// MARK: - Body Composition Trends

struct BodyCompositionView: View {
    @Environment(WorkoutStore.self) var store
    @Environment(PhotoStore.self) var photoStore

    @State private var periodDays: Int = 30
    @State private var weeklyVolumes: [WeekVolume] = []
    @State private var isLoading = true

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    header
                    metricsCards
                    periodPicker
                    weightChart
                    volumeChart
                    if !photoStore.allDates.isEmpty {
                        photoTimeline
                    }
                }
                .padding(.bottom, 32)
            }
        }
        .task { await loadData() }
        .onChange(of: periodDays) { Task { await loadData() } }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button { store.activeScreen = .home } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            Spacer()
            Text("Body Composition")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
            Spacer()
            // Balance the back button
            Color.clear.frame(width: 24, height: 24)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Key Metrics Cards

    private var metricsCards: some View {
        let cols = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
        return LazyVGrid(columns: cols, spacing: 10) {
            metricCard(
                title: "Current Weight",
                value: currentWeightText,
                detail: weightDeltaText,
                detailColor: weightDeltaColor,
                icon: "scalemass.fill",
                iconColor: Color(hex: "38bdf8")
            )
            metricCard(
                title: "Weekly Volume",
                value: thisWeekVolumeText,
                detail: volumeChangeText,
                detailColor: volumeChangeColor,
                icon: "dumbbell.fill",
                iconColor: Color(hex: "a855f7")
            )
            metricCard(
                title: "Photo Sessions",
                value: "\(photoStore.allDates.count)",
                detail: photoStore.allDates.isEmpty ? "No photos yet" : "Latest: \(photoStore.allDates.first ?? "")",
                detailColor: Theme.subtle,
                icon: "camera.fill",
                iconColor: Color(hex: "f59e0b")
            )
            metricCard(
                title: "Days in Phase",
                value: "\(daysInPhase)",
                detail: phaseLabel,
                detailColor: Theme.accent,
                icon: "calendar",
                iconColor: Theme.accent
            )
        }
        .padding(.horizontal, 14)
    }

    private func metricCard(title: String, value: String, detail: String, detailColor: Color, icon: String, iconColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Theme.subtle)
            }
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(.white)
            Text(detail)
                .font(.system(size: 11))
                .foregroundColor(detailColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border))
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        Picker("Period", selection: $periodDays) {
            Text("30 days").tag(30)
            Text("60 days").tag(60)
            Text("90 days").tag(90)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14)
    }

    // MARK: - Weight Trend Chart

    private var weightChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weight Trend")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            if filteredWeights.isEmpty {
                emptyChartPlaceholder("No weight data for this period")
            } else {
                Chart {
                    ForEach(filteredWeights) { w in
                        LineMark(
                            x: .value("Date", w.loggedAt),
                            y: .value("kg", w.weightKg)
                        )
                        .foregroundStyle(Color(hex: "38bdf8"))
                        .lineStyle(StrokeStyle(lineWidth: 2))

                        PointMark(
                            x: .value("Date", w.loggedAt),
                            y: .value("kg", w.weightKg)
                        )
                        .foregroundStyle(Color(hex: "38bdf8"))
                        .symbolSize(20)
                    }

                    ForEach(rollingAverage, id: \.date) { pt in
                        LineMark(
                            x: .value("Date", pt.date),
                            y: .value("kg", pt.avg),
                            series: .value("Series", "avg")
                        )
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                    }
                }
                .chartYScale(domain: weightYDomain)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) {
                        AxisGridLine().foregroundStyle(Theme.border)
                        AxisValueLabel().foregroundStyle(Theme.subtle)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(Theme.border)
                        AxisValueLabel().foregroundStyle(Theme.subtle)
                    }
                }
                .frame(height: 200)
                .chartLegend(.hidden)
                .overlay(alignment: .topTrailing) {
                    legendView
                }
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    private var legendView: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 4) {
                Circle().fill(Color(hex: "38bdf8")).frame(width: 6, height: 6)
                Text("Daily").font(.system(size: 9)).foregroundColor(Theme.subtle)
            }
            HStack(spacing: 4) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text("7-day avg").font(.system(size: 9)).foregroundColor(Theme.subtle)
            }
        }
        .padding(6)
    }

    // MARK: - Volume Chart

    private var volumeChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Weekly Volume")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)

            if filteredVolumes.isEmpty {
                emptyChartPlaceholder("No workouts in this period")
            } else {
                Chart {
                    ForEach(filteredVolumes) { wv in
                        BarMark(
                            x: .value("Week", wv.weekLabel),
                            y: .value("kg", wv.volume)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color(hex: "a855f7"), Color(hex: "7c3aed")],
                                startPoint: .top, endPoint: .bottom
                            )
                        )
                        .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks { AxisValueLabel().foregroundStyle(Theme.subtle) }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) {
                        AxisGridLine().foregroundStyle(Theme.border)
                        AxisValueLabel().foregroundStyle(Theme.subtle)
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Photo Timeline

    private var photoTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Photo Timeline")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.leading, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filteredPhotoDates, id: \.self) { date in
                        Button {
                            store.activeScreen = .photos
                        } label: {
                            photoThumbnail(date: date)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusMd))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    private func photoThumbnail(date: String) -> some View {
        let frontEntry = photoStore.entries(for: date).first(where: { $0.pose == "front" })
            ?? photoStore.entries(for: date).first

        return VStack(spacing: 4) {
            Group {
                if let entry = frontEntry, let img = photoStore.loadImage(for: entry) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Theme.muted)
                }
            }
            .frame(width: 64, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSm))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusSm).stroke(Theme.border))

            Text(shortDateLabel(date))
                .font(.system(size: 10))
                .foregroundColor(Theme.subtle)
        }
    }

    // MARK: - Empty placeholder

    private func emptyChartPlaceholder(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(Theme.muted)
            .frame(height: 120)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Data loading

    private func loadData() async {
        isLoading = true
        await loadWeeklyVolumes()
        isLoading = false
    }

    private func loadWeeklyVolumes() async {
        let cutoff = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date()) ?? Date()
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let cutoffStr = iso.string(from: cutoff)

        // Fetch all workout_sets in the period
        let resource = "workout_sets?select=weight_kg,reps,logged_at&logged_at=gte.\(cutoffStr)&order=logged_at.asc"
        struct SetRow: Decodable {
            let weightKg: Double
            let reps: Int
            let loggedAt: Date
            enum CodingKeys: String, CodingKey {
                case weightKg = "weight_kg"
                case reps
                case loggedAt = "logged_at"
            }
        }

        guard let rows: [SetRow] = await SupabaseClient.shared.tryGet(resource) else {
            weeklyVolumes = []
            return
        }

        // Group by ISO week
        let cal = Calendar(identifier: .iso8601)
        var weekMap: [String: Double] = [:]
        var weekDates: [String: Date] = [:]

        for row in rows {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: row.loggedAt)
            let key = "\(comps.yearForWeekOfYear ?? 0)-W\(String(format: "%02d", comps.weekOfYear ?? 0))"
            weekMap[key, default: 0] += row.weightKg * Double(row.reps)
            if weekDates[key] == nil {
                weekDates[key] = cal.date(from: comps)
            }
        }

        let fmt = DateFormatter()
        fmt.dateFormat = "d MMM"

        weeklyVolumes = weekMap.keys.sorted().map { key in
            let mondayDate = weekDates[key] ?? Date()
            return WeekVolume(
                weekKey: key,
                weekLabel: fmt.string(from: mondayDate),
                volume: weekMap[key] ?? 0,
                weekStart: mondayDate
            )
        }
    }

    // MARK: - Computed helpers

    private var filteredWeights: [BodyWeight] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date()) ?? Date()
        return store.bodyWeightLog
            .filter { $0.loggedAt >= cutoff }
            .sorted { $0.loggedAt < $1.loggedAt }
    }

    private var rollingAverage: [(date: Date, avg: Double)] {
        let sorted = filteredWeights
        guard sorted.count >= 2 else { return [] }
        var result: [(date: Date, avg: Double)] = []
        for i in 0..<sorted.count {
            let windowStart = max(0, i - 6)
            let window = sorted[windowStart...i]
            let avg = window.map(\.weightKg).reduce(0, +) / Double(window.count)
            result.append((date: sorted[i].loggedAt, avg: avg))
        }
        return result
    }

    private var weightYDomain: ClosedRange<Double> {
        let weights = filteredWeights.map(\.weightKg)
        guard let lo = weights.min(), let hi = weights.max() else { return 60...80 }
        let pad = max((hi - lo) * 0.1, 0.5)
        return (lo - pad)...(hi + pad)
    }

    private var filteredVolumes: [WeekVolume] {
        weeklyVolumes
    }

    private var filteredPhotoDates: [String] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -periodDays, to: Date()) ?? Date()
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let cutoffStr = fmt.string(from: cutoff)
        return photoStore.allDates.filter { $0 >= cutoffStr }
    }

    // MARK: - Metric computed values

    private var currentWeightText: String {
        guard let latest = store.bodyWeightLog.last else { return "--" }
        return String(format: "%.1f kg", latest.weightKg)
    }

    private var weightDeltaText: String {
        let sorted = store.bodyWeightLog.sorted { $0.loggedAt < $1.loggedAt }
        guard let latest = sorted.last else { return "No data" }
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let older = sorted.last(where: { $0.loggedAt <= sevenDaysAgo })
        guard let prev = older else { return "7d: --" }
        let delta = latest.weightKg - prev.weightKg
        let sign = delta >= 0 ? "+" : ""
        return "7d: \(sign)\(String(format: "%.1f", delta)) kg"
    }

    private var weightDeltaColor: Color {
        let sorted = store.bodyWeightLog.sorted { $0.loggedAt < $1.loggedAt }
        guard let latest = sorted.last else { return Theme.subtle }
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        guard let prev = sorted.last(where: { $0.loggedAt <= sevenDaysAgo }) else { return Theme.subtle }
        let delta = latest.weightKg - prev.weightKg
        return delta <= 0 ? Theme.accent : Color(hex: "ef4444")
    }

    private var thisWeekVolumeText: String {
        guard let current = weeklyVolumes.last else { return "--" }
        return formatVolume(current.volume)
    }

    private var volumeChangeText: String {
        guard weeklyVolumes.count >= 2 else { return "vs last: --" }
        let current = weeklyVolumes[weeklyVolumes.count - 1].volume
        let previous = weeklyVolumes[weeklyVolumes.count - 2].volume
        guard previous > 0 else { return "vs last: --" }
        let pct = ((current - previous) / previous) * 100
        let sign = pct >= 0 ? "+" : ""
        return "vs last: \(sign)\(String(format: "%.0f", pct))%"
    }

    private var volumeChangeColor: Color {
        guard weeklyVolumes.count >= 2 else { return Theme.subtle }
        let current = weeklyVolumes[weeklyVolumes.count - 1].volume
        let previous = weeklyVolumes[weeklyVolumes.count - 2].volume
        return current >= previous ? Theme.accent : Color(hex: "ef4444")
    }

    private var daysInPhase: Int {
        // Cut started Feb 9, 2026
        let cal = Calendar.current
        var comps = DateComponents()
        comps.year = 2026; comps.month = 2; comps.day = 9
        guard let start = cal.date(from: comps) else { return 0 }
        return max(0, cal.dateComponents([.day], from: start, to: Date()).day ?? 0)
    }

    private var phaseLabel: String {
        if daysInPhase <= 30 { return "Mini Cut" }
        return "Reverse Diet"
    }

    private func formatVolume(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.0fk kg", v / 1000) : String(format: "%.0f kg", v)
    }

    private func shortDateLabel(_ dateStr: String) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        guard let d = fmt.date(from: dateStr) else { return dateStr }
        let out = DateFormatter()
        out.dateFormat = "d MMM"
        return out.string(from: d)
    }
}

// MARK: - Week Volume model

struct WeekVolume: Identifiable {
    let id = UUID()
    let weekKey: String
    let weekLabel: String
    let volume: Double
    let weekStart: Date
}
