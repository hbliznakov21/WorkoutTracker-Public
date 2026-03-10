import SwiftUI
import Charts

struct BodyView: View {
    @Environment(WorkoutStore.self) var store
    @State private var period:              Period = .month
    @State private var isSyncing:           Bool   = false
    @State private var correlationExercise: String = ""
    @State private var e1rmData:            [(date: Date, e1rm: Double)] = []
    @State private var correlationOptions:  [(label: String, fullName: String)] = []
    @State private var selectedEntry:       BodyWeight? = nil
    @State private var weightInsight:       WeightInsight? = nil
    @State private var weightInsightLoading = false
    #if SONYA
    @State private var showGoalsEditor = false
    #endif

    // MARK: - Period

    enum Period: String, CaseIterable {
        case week    = "Week"
        case month   = "Month"
        case quarter = "90 Days"

        var days: Int {
            switch self {
            case .week:    return 7
            case .month:   return 30
            case .quarter: return 90
            }
        }
        var rollingWindow: Int {
            switch self { case .week: return 3; default: return 7 }
        }
        var axisStride: Int {
            switch self { case .week: return 1; case .month: return 7; case .quarter: return 14 }
        }
        var recentCount: Int {
            switch self { case .week: return 7; default: return 14 }
        }
        var avgLabel: String {
            switch self { case .week: return "3-day avg"; default: return "7-day avg" }
        }
    }

    // MARK: - Computed data

    private var periodEntries: [BodyWeight] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -period.days, to: Date())
        else { return store.bodyWeightLog }
        return store.bodyWeightLog.filter { $0.loggedAt >= cutoff }
    }

    private var periodStats: (min: Double, max: Double, avg: Double)? {
        let w = periodEntries.map(\.weightKg)
        guard !w.isEmpty else { return nil }
        return (w.min()!, w.max()!, w.reduce(0, +) / Double(w.count))
    }

    private var trend: Double? {
        let e = periodEntries
        guard e.count >= 3 else { return nil }
        let n   = Double(e.count)
        let xs  = (0..<e.count).map(Double.init)
        let ys  = e.map(\.weightKg)
        let sx  = xs.reduce(0, +);  let sy = ys.reduce(0, +)
        let sxy = zip(xs, ys).map(*).reduce(0, +)
        let sx2 = xs.map { $0 * $0 }.reduce(0, +)
        let d   = n * sx2 - sx * sx
        guard d != 0 else { return nil }
        return (n * sxy - sx * sy) / d * 7
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 16) {
                    syncStatusCard.padding(.top, 8)

                    if !store.bodyWeightLog.isEmpty {
                        if weightInsightLoading {
                            weightInsightLoadingCard
                        } else if let insight = weightInsight {
                            weightInsightCard(insight)
                        }
                        periodPicker
                        chartCard
                        statsRow
                        #if SONYA
                        goalsCard
                        #endif
                        if !correlationOptions.isEmpty {
                            correlationCard
                        }
                        recentCard
                    } else if !isSyncing {
                        VStack(spacing: 8) {
                            Text("⚖️").font(.system(size: 40))
                            Text("No weight data found in Apple Health.\nMake sure your Withings scale is synced.")
                                .font(.subheadline)
                                .foregroundColor(Theme.subtle)
                                .multilineTextAlignment(.center)
                        }
                        .padding(40)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom) { AppTabBar(active: .body) }
        .task { await sync() }
        .onChange(of: correlationExercise) { _, _ in
            Task {
                let fullName = correlationOptions.first { $0.label == correlationExercise }?.fullName ?? correlationExercise
                e1rmData = await store.loadExerciseE1rm(name: fullName, days: 90)
            }
        }
        .navigationTitle("Body Weight")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { store.activeScreen = .home } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .foregroundColor(Theme.accent)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { Task { await sync() } } label: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundColor(Theme.accent)
                }
                .disabled(isSyncing)
            }
        }
    }

    private func sync() async {
        isSyncing = true
        await store.loadBodyWeight()

        // Load top exercises for correlation if not yet loaded
        if correlationOptions.isEmpty {
            correlationOptions = await store.loadTopExercises(limit: 4)
            if let first = correlationOptions.first {
                correlationExercise = first.label
            }
        }

        if !correlationExercise.isEmpty {
            let fullName = correlationOptions.first { $0.label == correlationExercise }?.fullName ?? correlationExercise
            e1rmData = await store.loadExerciseE1rm(name: fullName, days: 90)
        }
        isSyncing = false

        #if SONYA
        await store.loadUserPhaseGoals()
        #endif

        // Load AI weight insight
        if store.bodyWeightLog.count >= 5, weightInsight == nil {
            weightInsightLoading = true
            weightInsight = await store.generateWeightInsight()
            weightInsightLoading = false
        }
    }

    // MARK: - Sync status card

    private var syncStatusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "heart.fill")
                .font(.system(size: 15))
                .foregroundColor(Color(hex: "ef4444"))
            VStack(alignment: .leading, spacing: 2) {
                Text("Synced from Apple Health")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "e2e8f0"))
                Text("Withings → Health → this app · last 90 days")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "475569"))
            }
            Spacer()
            if let latest = store.bodyWeightLog.last {
                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(latest.weightKg.clean) kg")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.white)
                    Text(latest.dayLabel)
                        .font(.caption2)
                        .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Period picker

    private var periodPicker: some View {
        HStack(spacing: 8) {
            ForEach(Period.allCases, id: \.self) { p in
                Button { withAnimation(.easeInOut(duration: 0.2)) { period = p } } label: {
                    Text(p.rawValue)
                        .font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 16).padding(.vertical, 7)
                        .background(period == p ? Theme.accent : Color.clear)
                        .foregroundColor(period == p ? .black : Theme.subtle)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(period == p ? Color.clear : Theme.border))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Chart card

    private var chartCard: some View {
        let entries = periodEntries
        let rolling = rollingAverage(entries, window: period.rollingWindow)
        let weights = entries.map(\.weightKg)
        let minW    = (weights.min() ?? 70) - 1.0
        let maxW    = (weights.max() ?? 70) + 1.0

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(period == .week ? "This Week" : period == .month ? "Last 30 Days" : "Last 90 Days")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                    .foregroundColor(Theme.subtle)
                Spacer()
                if let t = trend {
                    HStack(spacing: 4) {
                        Image(systemName: t >= 0 ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                        Text(String(format: "%+.2f kg/wk", t))
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(t >= 0 ? Color(hex: "f59e0b") : Theme.accent)
                }
            }

            if entries.isEmpty {
                Text("No data for this period.")
                    .font(.caption).foregroundColor(Color(hex: "475569"))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .frame(height: 180)
            } else {
                Chart {
                    ForEach(entries) { e in
                        PointMark(
                            x: .value("Date", e.loggedAt, unit: .day),
                            y: .value("Weight", e.weightKg)
                        )
                        .foregroundStyle(Color(hex: "475569"))
                        .symbolSize(period == .week ? 50 : 25)
                    }

                    // Connect dots with a faint line in week view
                    if period == .week {
                        ForEach(entries) { e in
                            LineMark(
                                x: .value("Date", e.loggedAt, unit: .day),
                                y: .value("Weight", e.weightKg)
                            )
                            .foregroundStyle(Theme.border)
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .interpolationMethod(.linear)
                        }
                    }

                    ForEach(rolling, id: \.date) { r in
                        LineMark(
                            x: .value("Date", r.date, unit: .day),
                            y: .value(period.avgLabel, r.avg)
                        )
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2.5))
                        .interpolationMethod(.catmullRom)
                    }

                    // Selected data point rule line + annotation
                    if let sel = selectedEntry {
                        RuleMark(x: .value("Selected", sel.loggedAt, unit: .day))
                            .foregroundStyle(Theme.subtle.opacity(0.5))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .annotation(position: .top, spacing: 4) {
                                VStack(spacing: 2) {
                                    Text("\(sel.weightKg.clean) kg")
                                        .font(.system(size: 12, weight: .black))
                                        .foregroundColor(.white)
                                    Text(sel.dayLabel)
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
                .chartYScale(domain: minW...maxW)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: period.axisStride)) { val in
                        if let d = val.as(Date.self) {
                            AxisValueLabel {
                                if period == .week {
                                    Text(d, format: .dateTime.weekday(.abbreviated))
                                        .font(.system(size: 9))
                                } else {
                                    Text(d, format: .dateTime.month(.abbreviated).day())
                                        .font(.system(size: 9))
                                }
                            }
                            .foregroundStyle(Theme.muted)
                        }
                        AxisGridLine().foregroundStyle(
                            period == .week ? Theme.border : Theme.surface
                        )
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { val in
                        if let v = val.as(Double.self) {
                            AxisValueLabel {
                                Text(String(format: "%.1f", v)).font(.system(size: 9))
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
                                        // Find nearest entry
                                        selectedEntry = entries.min(by: {
                                            abs($0.loggedAt.timeIntervalSince(date)) < abs($1.loggedAt.timeIntervalSince(date))
                                        })
                                        Haptics.selection()
                                    }
                                    .onEnded { _ in
                                        selectedEntry = nil
                                    }
                            )
                    }
                }
                .frame(height: 180)

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: "475569")).frame(width: 7, height: 7)
                        Text("Daily").font(.caption2).foregroundColor(Theme.muted)
                    }
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2).fill(Theme.accent)
                            .frame(width: 14, height: 3)
                        Text(period.avgLabel).font(.caption2).foregroundColor(Theme.subtle)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Stats row (min / avg / max for period)

    private var statsRow: some View {
        Group {
            if let s = periodStats {
                HStack(spacing: 0) {
                    statCell("Low", String(format: "%.1f", s.min), Theme.accent)
                    Rectangle().fill(Theme.border).frame(width: 1, height: 36)
                    statCell("Avg", String(format: "%.1f", s.avg), Theme.subtle)
                    Rectangle().fill(Theme.border).frame(width: 1, height: 36)
                    statCell("High", String(format: "%.1f", s.max), Color(hex: "f59e0b"))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                .padding(.horizontal, 14)
            }
        }
    }

    private func statCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(1)
                .foregroundColor(Theme.muted)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Recent entries card

    private var recentCard: some View {
        let entries = periodEntries.suffix(period.recentCount).reversed()
        return VStack(alignment: .leading, spacing: 0) {
            Text("Entries")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)
                .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 10)

            ForEach(Array(entries)) { e in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.dayLabel)
                            .font(.subheadline).foregroundColor(Theme.subtle)
                        if period == .week {
                            Text(e.loggedAt, format: .dateTime.weekday(.wide))
                                .font(.caption2).foregroundColor(Color(hex: "475569"))
                        }
                    }
                    Spacer()
                    Text("\(e.weightKg.clean) kg")
                        .font(.system(size: 16, weight: .bold)).foregroundColor(.white)
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

    // MARK: - Weight vs Strength correlation card

    private var correlationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weight vs Strength")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)

            // Segmented picker
            HStack(spacing: 8) {
                ForEach(correlationOptions, id: \.label) { opt in
                    Button {
                        correlationExercise = opt.label
                    } label: {
                        Text(opt.label)
                            .font(.caption).fontWeight(.semibold)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(correlationExercise == opt.label ? Color(hex: "f59e0b") : Color.clear)
                            .foregroundColor(correlationExercise == opt.label ? .black : Theme.subtle)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(correlationExercise == opt.label ? Color.clear : Theme.border))
                    }
                }
                Spacer()
            }

            correlationChartView
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    @ViewBuilder
    private var correlationChartView: some View {
        let bwEntries  = store.bodyWeightLog.suffix(90)
        let bwValues   = bwEntries.map(\.weightKg)
        let e1rmValues = e1rmData.map(\.e1rm)
        let allValues  = bwValues + e1rmValues

        if allValues.isEmpty {
            Text("No data available.")
                .font(.caption).foregroundColor(Color(hex: "475569"))
                .frame(maxWidth: .infinity, alignment: .center).frame(height: 180)
        } else {
            let minY = (allValues.min() ?? 60) - 5
            let maxY = (allValues.max() ?? 80) + 5
            let axFmt: DateFormatter = {
                let f = DateFormatter(); f.dateFormat = "d MMM"; return f
            }()

            Chart {
                ForEach(Array(bwEntries), id: \.loggedAt) { e in
                    LineMark(
                        x: .value("Date", e.loggedAt, unit: .day),
                        y: .value("Body weight", e.weightKg),
                        series: .value("Series", "bw")
                    )
                    .foregroundStyle(Color(hex: "38bdf8"))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                }

                ForEach(e1rmData, id: \.date) { pt in
                    LineMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("e1RM", pt.e1rm),
                        series: .value("Series", "e1rm")
                    )
                    .foregroundStyle(Color(hex: "f59e0b"))
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("Date", pt.date, unit: .day),
                        y: .value("e1RM", pt.e1rm)
                    )
                    .foregroundStyle(Color(hex: "f59e0b"))
                    .symbolSize(20)
                }
            }
            .chartYScale(domain: minY...maxY)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 14)) { val in
                    if let d = val.as(Date.self) {
                        AxisValueLabel {
                            Text(axFmt.string(from: d)).font(.system(size: 9))
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
                            Text(String(format: "%.0f", v)).font(.system(size: 9))
                        }
                        .foregroundStyle(Theme.muted)
                    }
                    AxisGridLine().foregroundStyle(Theme.border)
                }
            }
            .frame(height: 180)

            // Legend
            HStack(spacing: 16) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "38bdf8"))
                        .frame(width: 14, height: 3)
                    Text("Body weight").font(.caption2).foregroundColor(Theme.muted)
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 2).fill(Color(hex: "f59e0b"))
                        .frame(width: 14, height: 3)
                    Text(correlationExercise + " e1RM").font(.caption2).foregroundColor(Theme.subtle)
                }
            }
        }
    }

    // MARK: - AI Weight Insight

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
                Button {
                    weightInsight = nil
                    store.cachedWeightInsight = nil
                    store.weightInsightDate = ""
                    Task {
                        try? await store.sb.delete("session_goals?routine_name=eq.weight_insight")
                        weightInsightLoading = true
                        weightInsight = await store.generateWeightInsight()
                        weightInsightLoading = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.subtle)
                }
                Text(insight.actionLabel)
                    .font(.system(size: 9, weight: .black)).tracking(0.5)
                    .foregroundColor(Color(hex: insight.actionColor))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: insight.actionColor).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
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
    }

    // MARK: - Goals Card (Sonya build)

    #if SONYA
    private var goalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "a855f7"))
                Text("My Goals")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
                Spacer()
                Button {
                    showGoalsEditor = true
                } label: {
                    Text(store.userPhaseGoals == nil ? "Set Up" : "Edit")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(hex: "a855f7"))
                }
            }

            if let goals = store.userPhaseGoals {
                HStack(spacing: 12) {
                    VStack(spacing: 3) {
                        Text(goals.phaseLabel)
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(Color(hex: goals.phaseColor))
                        Text("Phase")
                            .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.5)
                            .foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle().fill(Theme.border).frame(width: 1, height: 30)

                    VStack(spacing: 3) {
                        Text("\(goals.targetCalories)")
                            .font(.system(size: 13, weight: .black))
                            .foregroundColor(.white)
                        Text("Cal")
                            .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.5)
                            .foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)

                    Rectangle().fill(Theme.border).frame(width: 1, height: 30)

                    VStack(spacing: 3) {
                        Text("\(goals.targetProtein)P/\(goals.targetCarbs)C/\(goals.targetFat)F")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(Theme.subtle)
                        Text("Macros")
                            .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.5)
                            .foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity)
                }

                // End date
                let fmt = DateFormatter()
                let _ = fmt.dateFormat = "yyyy-MM-dd"
                let _ = fmt.locale = Locale(identifier: "en_US_POSIX")
                if let endDate = fmt.date(from: goals.endDate) {
                    let daysLeft = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: endDate).day ?? 0
                    HStack {
                        Spacer()
                        Text(daysLeft > 0 ? "\(daysLeft) days remaining" : "Phase ended")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(daysLeft > 0 ? Theme.subtle : Color(hex: "ef4444"))
                        Spacer()
                    }
                }
            } else {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Text("Set your phase & macro targets")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Theme.subtle)
                        Text("AI analysis will use this for personalized advice")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
        .sheet(isPresented: $showGoalsEditor) {
            GoalsEditorSheet(currentGoals: store.userPhaseGoals) { goals in
                Task {
                    await store.saveUserPhaseGoals(goals)
                    // Re-trigger AI analysis with new goals context
                    weightInsight = nil
                    weightInsightLoading = true
                    weightInsight = await store.generateWeightInsight()
                    weightInsightLoading = false
                }
            }
        }
    }
    #endif

    // MARK: - Helpers

    private struct RollingPoint { let date: Date; let avg: Double }

    private func rollingAverage(_ entries: [BodyWeight], window: Int) -> [RollingPoint] {
        entries.enumerated().map { (i, e) in
            let slice = entries[max(0, i - window + 1)...i]
            let avg   = slice.map(\.weightKg).reduce(0, +) / Double(slice.count)
            return RollingPoint(date: e.loggedAt, avg: avg)
        }
    }

}

