import SwiftUI

enum HeatmapPeriod: String, CaseIterable {
    case weeks4  = "4W"
    case months3 = "3M"
    case months6 = "6M"
    var numWeeks: Int {
        switch self { case .weeks4: return 4; case .months3: return 13; case .months6: return 26 }
    }
}

struct HistoryView: View {
    @Environment(WorkoutStore.self) var store

    private static let monthFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM"; return f
    }()
    private static let dMMMFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    @State private var workoutDates:    Set<Date>      = []
    @State private var heatmapExpanded: Bool           = true
    @State private var heatmapLoaded:   Bool           = false
    @State private var heatmapPeriod:   HeatmapPeriod  = .months3

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 0) {
                    consistencyCard.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 8)

                    pendingWorkoutsSection
                        .padding(.horizontal, 14).padding(.top, 8)

                    if store.isLoading {
                        ProgressView().tint(Theme.accent).padding(40)
                    } else if store.history.isEmpty {
                        VStack(spacing: 8) {
                            Text("📋").font(.system(size: 40))
                            Text("No workouts logged yet.").foregroundColor(Theme.subtle)
                        }.padding(40)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(store.history) { wk in
                                histRow(wk)
                                Divider().padding(.leading, 68).background(Theme.border)
                            }
                        }
                        .background(Theme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                        .padding(14)
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) { AppTabBar(active: .history) }
        .task {
            await store.loadHistory()
            async let rd: ()  = store.loadRestDays()
            async let wd      = store.loadWorkoutDates(days: 182)
            async let hk: ()  = store.loadPendingHKWorkouts()
            let (_, dates, _) = await (rd, wd, hk)
            workoutDates  = dates
            heatmapLoaded = true
        }
        .navigationTitle("History")
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

    // MARK: - Consistency heatmap card

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { heatmapExpanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Text("Consistency")
                            .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1.5)
                            .foregroundColor(Theme.subtle)
                        Image(systemName: heatmapExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(Color(hex: "475569"))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                if heatmapExpanded {
                    HStack(spacing: 4) {
                        ForEach(HeatmapPeriod.allCases, id: \.self) { p in
                            Button { withAnimation(.easeInOut(duration: 0.15)) { heatmapPeriod = p } } label: {
                                Text(p.rawValue)
                                    .font(.system(size: 11, weight: .semibold))
                                    .padding(.horizontal, 10).padding(.vertical, 4)
                                    .background(heatmapPeriod == p ? Theme.accent : Theme.bg)
                                    .foregroundColor(heatmapPeriod == p ? .black : Theme.muted)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)

            if heatmapExpanded {
                if heatmapLoaded {
                    heatmapGrid
                        .padding(.horizontal, 12).padding(.bottom, 12)
                } else {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity).padding(24)
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
    }

    @ViewBuilder
    private var heatmapGrid: some View {
        let cal      = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let numWeeks = heatmapPeriod.numWeeks
        let numDays  = numWeeks * 7
        // Anchor: find the Sunday of the current week as the last column
        let weekday  = cal.component(.weekday, from: today) // Sun=1..Sat=7
        let daysToSun = (7 - weekday) % 7
        let lastSun  = cal.date(byAdding: .day, value: daysToSun, to: today)!
        let gridStart = cal.date(byAdding: .day, value: -(numDays - 1), to: lastSun)!

        let cellSize: CGFloat  = 12
        let cellGap:  CGFloat  = 3
        let dayLabels = ["M", "", "W", "", "F", "", "S"]
        let monthFmt = Self.monthFmt

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 0) {
                // Day labels column
                VStack(spacing: cellGap) {
                    Text("").font(.system(size: 8)).frame(height: 12) // month label spacer
                    ForEach(0..<7, id: \.self) { r in
                        Text(dayLabels[r])
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Color(hex: "475569"))
                            .frame(width: 12, height: cellSize)
                    }
                }
                .padding(.trailing, 4)

                // Weeks
                ForEach(0..<numWeeks, id: \.self) { col in
                    VStack(spacing: cellGap) {
                        // Month label above first week of each month
                        let colStartDate = cal.date(byAdding: .day, value: col * 7, to: gridStart)!
                        let prevColDate  = col == 0 ? colStartDate :
                            cal.date(byAdding: .day, value: (col - 1) * 7, to: gridStart)!
                        let showMonth = col == 0 ||
                            cal.component(.month, from: colStartDate) != cal.component(.month, from: prevColDate)
                        Text(showMonth ? monthFmt.string(from: colStartDate) : "")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundColor(Theme.muted)
                            .frame(height: 12)

                        // 7 cells Mon–Sun
                        ForEach(0..<7, id: \.self) { row in
                            let dayOffset = col * 7 + row
                            let cellDate  = cal.date(byAdding: .day, value: dayOffset, to: gridStart)!
                            let isFuture  = cellDate > today
                            let isTrained = workoutDates.contains(cellDate)
                            let isRest    = store.restDays.contains(cellDate)
                            let color: Color = isFuture  ? Theme.surface :
                                               isTrained ? Theme.accent :
                                               isRest    ? Color(hex: "475569") :
                                                           Theme.border
                            RoundedRectangle(cornerRadius: 2)
                                .fill(color)
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                    if col < numWeeks - 1 {
                        Spacer().frame(width: cellGap)
                    }
                }
            }
        }

        // Legend
        HStack(spacing: 14) {
            heatmapLegendDot("22c55e", "Trained")
            heatmapLegendDot("475569", "Rest day")
            heatmapLegendDot("334155", "Skipped")
        }
        .padding(.top, 8)
    }

    private func heatmapLegendDot(_ hex: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(Color(hex: hex)).frame(width: 10, height: 10)
            Text(label).font(.caption2).foregroundColor(Theme.muted)
        }
    }

    // MARK: - Pending Apple Health workouts

    private var pendingWorkoutsSection: some View {
        Group {
            if !store.pendingHKWorkouts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("APPLE HEALTH — NOT SYNCED")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "f59e0b"))
                            .tracking(1.2)
                        Spacer()
                        Text("\(store.pendingHKWorkouts.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color(hex: "f59e0b"))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Color(hex: "f59e0b").opacity(0.15))
                            .clipShape(Capsule())
                    }

                    if let err = store.importError {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(Color(hex: "ef4444"))
                            .padding(.horizontal, 4)
                    }

                    VStack(spacing: 0) {
                        ForEach(store.pendingHKWorkouts) { entry in
                            PendingWorkoutRow(
                                entry: entry,
                                isImporting: store.importingWorkoutId == entry.id,
                                onSync:    { Task { await store.importWorkout(entry) } },
                                onDismiss: { store.dismissWorkout(entry) }
                            )
                            if entry.id != store.pendingHKWorkouts.last?.id {
                                Divider()
                                    .background(Theme.border)
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "f59e0b").opacity(0.4), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func cardioIconName(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("cycl") || n.contains("bike")                           { return "figure.indoor.cycle" }
        if n.contains("treadmill") || (n.contains("indoor") && n.contains("run")) { return "figure.run" }
        if n.contains("run")                                                   { return "figure.run" }
        if n.contains("step") || n.contains("stair")                          { return "figure.stair.stepper" }
        if n.contains("elliptical")                                            { return "figure.elliptical" }
        if n.contains("row")                                                   { return "oar.2.crossed" }
        if n.contains("walk")                                                  { return "figure.walk" }
        return "figure.run"
    }

    private func histRow(_ wk: Workout) -> some View {
        let isCardio = wk.routineId == nil
        return Button {
            store.activeScreen = .detail(wk.id)
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isCardio ? Color(hex: "38bdf8").opacity(0.15) : Theme.accent.opacity(0.15))
                        .frame(width: 40, height: 40)
                    if isCardio {
                        Image(systemName: cardioIconName(wk.routineName))
                            .font(.system(size: 18))
                            .foregroundColor(Color(hex: "38bdf8"))
                    } else {
                        Text("💪").font(.system(size: 18))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(wk.routineName).font(.subheadline).fontWeight(.bold)
                    Text("\(wk.dateLabel) · \(wk.duration)").font(.caption).foregroundColor(Theme.subtle)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .trailing) {
            Button {
                Task { await store.deleteWorkout(id: wk.id) }
            } label: {
                Image(systemName: "trash").foregroundColor(Theme.border)
                    .padding(.horizontal, 16).padding(.vertical, 13)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

}

// MARK: - Pending Apple Health workout row

private struct PendingWorkoutRow: View {
    let entry: HKWorkoutEntry
    let isImporting: Bool
    let onSync: () -> Void
    let onDismiss: () -> Void

    private static let dMMMFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()

    private var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(entry.startedAt)     { return "Today" }
        if cal.isDateInYesterday(entry.startedAt) { return "Yesterday" }
        return Self.dMMMFmt.string(from: entry.startedAt)
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.emoji)
                .font(.system(size: 22))
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.activityName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Color(hex: "e2e8f0"))
                Text("\(dateLabel) · \(entry.duration)")
                    .font(.caption2)
                    .foregroundColor(Color(hex: "475569"))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if let cal = entry.calories {
                    Text("\(cal) kcal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                if let hr = entry.avgHeartRate {
                    Text("\(hr) bpm avg")
                        .font(.caption2)
                        .foregroundColor(Theme.muted)
                }
            }

            Button(action: onSync) {
                Group {
                    if isImporting {
                        ProgressView()
                            .tint(Color(hex: "f59e0b"))
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Color(hex: "f59e0b"))
                    }
                }
                .frame(width: 32, height: 32)
            }
            .disabled(isImporting)
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Color(hex: "475569"))
                    .frame(width: 32, height: 32)
            }
            .disabled(isImporting)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
