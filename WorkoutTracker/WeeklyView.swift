import SwiftUI

struct WeeklyView: View {
    @Environment(WorkoutStore.self) var store
    @State private var weekStats: [WorkoutWeekStats] = []
    @State private var isLoading = true

    private let dayAbbr  = ["M", "T", "W", "T", "F", "S", "S"]
    private let dayNames = ["Monday","Tuesday","Wednesday","Thursday","Friday","Saturday","Sunday"]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            Group {
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            Text(weekRangeLabel)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(Theme.subtle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16)
                                .padding(.top, 6)
                                .padding(.bottom, 2)

                            ForEach(0..<7, id: \.self) { i in
                                dayCard(index: i)
                            }

                            if !weekStats.isEmpty {
                                summaryCard.padding(.top, 4)
                                muscleBalanceButton.padding(.top, 4)
                            }
                        }
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { AppTabBar(active: .home) }
        .task {
            if weekStats.isEmpty { isLoading = true }
            async let ws = store.loadWeekData()
            async let rd: () = store.loadRestDays()
            weekStats = await ws
            await rd
            isLoading = false
        }
        .navigationTitle("This Week")
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
        }
    }

    // MARK: - Day card (compact)

    private func dayCard(index: Int) -> some View {
        let date      = weekDate(offset: index)
        let cal       = Calendar.current
        let isToday   = cal.isDateInToday(date)
        let isPast    = date < cal.startOfDay(for: Date()) && !isToday
        let dayName   = dayNames[index]
        let scheduled = store.schedule[dayName] ?? "Rest"
        let isScheduledRest = scheduled == "Rest"
        let isMarkedRest    = store.restDays.contains(cal.startOfDay(for: date))
        let isRest          = isScheduledRest || isMarkedRest
        let dayStats  = weekStats.filter { cal.isDate($0.workout.startedAt, inSameDayAs: date) }
        let isDone    = !dayStats.isEmpty

        return HStack(alignment: .top, spacing: 12) {
            // Day badge
            VStack(spacing: 1) {
                Text(dayAbbr[index])
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(isToday ? .black : Theme.muted)
                Text("\(cal.component(.day, from: date))")
                    .font(.system(size: 18, weight: .black))
                    .foregroundColor(isToday ? .black : Color(hex: "e2e8f0"))
            }
            .frame(width: 38, height: 46)
            .background(isToday ? Theme.accent : Theme.bg)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Content
            VStack(alignment: .leading, spacing: isDone && dayStats.count > 1 ? 8 : 3) {
                if isDone {
                    ForEach(Array(dayStats.enumerated()), id: \.offset) { _, s in
                        workoutRow(s, showDivider: dayStats.count > 1)
                    }
                } else if isMarkedRest && !isScheduledRest {
                    HStack(spacing: 5) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "475569"))
                        Text("Rest Day")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(hex: "475569"))
                    }
                    Text("Skipped \(scheduled)")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.border)
                } else if isScheduledRest {
                    Text("Rest")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "475569"))
                    Text("Recovery day")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.border)
                } else {
                    Text(scheduled)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(hex: "e2e8f0"))
                }
            }

            Spacer()

            // Status indicator
            if isDone {
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(Theme.accent)
                    if dayStats.count > 1 {
                        Text("\(dayStats.count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.accent)
                    }
                }
            } else if isMarkedRest && !isScheduledRest {
                Image(systemName: "moon.zzz.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Color(hex: "475569"))
            } else if isToday && !isRest {
                Text("TODAY")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(Color(hex: "f59e0b"))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(Color(hex: "f59e0b").opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(isDone ? Theme.accent.opacity(0.05) : Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isDone ? Theme.accent.opacity(0.35) : Theme.border,
                    lineWidth: 1
                )
        )
        .opacity(isPast && !isDone ? 0.4 : 1.0)
        .padding(.horizontal, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if let first = dayStats.first { store.activeScreen = .detail(first.workout.id) }
        }
    }

    // MARK: - Single workout row within a day card

    private func workoutRow(_ s: WorkoutWeekStats, showDivider: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(s.workout.routineName ?? "Workout")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Color(hex: "e2e8f0"))
            HStack(spacing: 5) {
                if s.setsCount > 0 {
                    Text("\(s.setsCount) sets")
                    Text("·").foregroundColor(Color(hex: "475569"))
                    Text(fmtVol(s.volume))
                    Text("·").foregroundColor(Color(hex: "475569"))
                }
                Text(s.workout.duration)
            }
            .font(.system(size: 11))
            .foregroundColor(Theme.subtle)
        }
    }

    // MARK: - Summary + weekly muscle split card

    private var summaryCard: some View {
        let totalSets = weekStats.reduce(0)   { $0 + $1.setsCount }
        let totalVol  = weekStats.reduce(0.0) { $0 + $1.volume }
        let totalSecs = weekStats.reduce(0.0) { total, s in
            guard let end = s.workout.finishedAt else { return total }
            return total + end.timeIntervalSince(s.workout.startedAt)
        }
        let weekSplit = weekMuscleSplit

        return VStack(alignment: .leading, spacing: 14) {
            // ── Totals row ───────────────────────────────────────────
            Text("Week Total")
                .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                .foregroundColor(Theme.subtle)

            HStack(spacing: 0) {
                statCell("\(weekStats.count)", "SESSIONS")
                statCell("\(totalSets)", "SETS")
                statCell(fmtVolShort(totalVol), "KG VOL")
                statCell(fmtTotalTime(totalSecs), "TIME")
            }

            // ── Muscle split ─────────────────────────────────────────
            if !weekSplit.isEmpty {
                Divider().background(Theme.border)

                Text("Muscle Split")
                    .font(.caption).fontWeight(.bold)
                    .textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)

                VStack(spacing: 8) {
                    ForEach(weekSplit, id: \.muscle) { item in
                        HStack(spacing: 10) {
                            Text(item.muscle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 88, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Theme.bg)
                                        .frame(height: 8)
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(muscleColor(item.muscle))
                                        .frame(
                                            width: max(4, geo.size.width * CGFloat(item.pct / 100)),
                                            height: 8
                                        )
                                        .animation(.easeOut(duration: 0.5), value: item.pct)
                                }
                            }
                            .frame(height: 8)

                            HStack(spacing: 3) {
                                Text("\(item.sets)s")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(muscleColor(item.muscle))
                                Text("·")
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(hex: "475569"))
                                Text("\(Int(item.pct))%")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Theme.subtle)
                            }
                            .frame(width: 58, alignment: .trailing)
                        }
                        .frame(height: 16)
                    }
                }
            }

            // ── Volume Targets ────────────────────────────────────────
            let targetItems = volumeTargetItems
            if !targetItems.isEmpty {
                Divider().background(Theme.border)

                Text("Volume Targets")
                    .font(.caption).fontWeight(.bold)
                    .textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)

                VStack(spacing: 8) {
                    ForEach(targetItems, id: \.muscle) { item in
                        HStack(spacing: 10) {
                            Text(item.muscle)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 88, alignment: .leading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)

                            GeometryReader { geo in
                                let cap  = Double(item.target.upperBound) + 2
                                let fill = CGFloat(min(item.sets, Int(cap))) / CGFloat(cap)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Theme.bg)
                                        .frame(height: 8)
                                    // target minimum marker line
                                    let minFrac = CGFloat(item.target.lowerBound) / CGFloat(cap)
                                    Rectangle()
                                        .fill(Color.white.opacity(0.15))
                                        .frame(width: 1.5, height: 12)
                                        .offset(x: geo.size.width * minFrac - 0.75, y: -2)
                                    // actual fill
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(volumeBarColor(sets: item.sets, target: item.target))
                                        .frame(width: max(4, geo.size.width * fill), height: 8)
                                        .animation(.easeOut(duration: 0.5), value: item.sets)
                                }
                            }
                            .frame(height: 12)

                            Text("\(item.sets)/\(item.target.lowerBound)-\(item.target.upperBound)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(volumeBarColor(sets: item.sets, target: item.target))
                                .frame(width: 58, alignment: .trailing)
                        }
                        .frame(height: 16)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // Aggregate muscle sets across all workouts this week
    private var weekMuscleSplit: [(muscle: String, sets: Int, pct: Double)] {
        var counts: [String: Int] = [:]
        for ws in weekStats {
            for item in ws.muscleSplit {
                counts[item.muscle, default: 0] += item.sets
            }
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return counts
            .map { (muscle: $0.key, sets: $0.value, pct: Double($0.value) / Double(total) * 100) }
            .sorted { $0.sets > $1.sets }
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .black))
                .foregroundColor(Theme.accent)
            Text(label)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(Theme.subtle)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Muscle balance link

    private var muscleBalanceButton: some View {
        Button { store.activeScreen = .muscleBalance } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 16))
                    .foregroundColor(Theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Muscle Balance Score")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text("See how balanced your weekly volume is")
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
    }

    // MARK: - Volume targets helpers

    private var volumeTargetItems: [(muscle: String, sets: Int, target: ClosedRange<Int>)] {
        weekMuscleSplit.compactMap { item in
            guard let t = volumeTarget(for: item.muscle) else { return nil }
            return (item.muscle, item.sets, t)
        }
    }

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

    private func volumeBarColor(sets: Int, target: ClosedRange<Int>) -> Color {
        if sets >= target.lowerBound              { return Theme.accent }  // at/above min
        if sets >= target.lowerBound * 2 / 3     { return Color(hex: "f59e0b") }  // ≥67% of min
        return Color(hex: "ef4444")                                                 // below 67%
    }


    // MARK: - Helpers

    private func weekDate(offset: Int) -> Date {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysToMon = weekday == 1 ? -6 : 2 - weekday
        return cal.date(byAdding: .day, value: daysToMon + offset, to: today)!
    }

    private var weekRangeLabel: String {
        let monday = weekDate(offset: 0)
        let sunday = weekDate(offset: 6)
        let startFmt = DateFormatter()
        startFmt.dateFormat = "MMM d"
        let endFmt = DateFormatter()
        endFmt.dateFormat = "d, yyyy"
        return "\(startFmt.string(from: monday)) – \(endFmt.string(from: sunday))"
    }

    private func fmtVol(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk kg", v / 1000) : "\(Int(v)) kg"
    }

    private func fmtVolShort(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))"
    }

    private func fmtTotalTime(_ secs: Double) -> String {
        let m = Int(secs / 60)
        return m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
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
