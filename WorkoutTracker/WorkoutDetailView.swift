import SwiftUI

struct WorkoutDetailView: View {
    @Environment(WorkoutStore.self) var store
    let workoutId: UUID
    @State private var sets: [WorkoutSet] = []
    @State private var muscleSplit: [(muscle: String, sets: Int, pct: Double)] = []
    @State private var workout: Workout?
    @State private var loading = true
    @State private var showShareSheet = false
    @State private var showAIAnalysis = false
    @State private var hasAIAnalysis = false
    @State private var aiAnalysis: AIAnalysisResult?

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if loading {
                ProgressView().tint(Theme.accent)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        statsCard
                        if !muscleSplit.isEmpty { muscleSplitCard }
                        if let ai = aiAnalysis { aiSummaryCard(ai) }
                        if workout?.routineId != nil { exercisesSection }

                        // AI Analysis button (for strength workouts without existing analysis)
                        if workout?.routineId != nil, !sets.isEmpty, aiAnalysis == nil {
                            Button {
                                showAIAnalysis = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "brain.head.profile")
                                        .font(.system(size: 16, weight: .bold))
                                    Text("Get AI Analysis")
                                        .font(.headline).fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 14)
                                .background(
                                    LinearGradient(
                                        colors: [Color(hex: "8b5cf6"), Color(hex: "6366f1")],
                                        startPoint: .leading, endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 14)
                        }

                        Button {
                            Task {
                                await store.deleteWorkout(id: workoutId)
                                store.activeScreen = store.previousScreen
                            }
                        } label: {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete Workout")
                            }
                            .font(.headline).fontWeight(.bold)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(Color(hex: "ef4444"))
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .padding(.horizontal, 14)
                    }
                    .padding(.top, 12).padding(.bottom, 32)
                }
            }
        }
        .task {
            async let setsResult    = store.loadSets(workoutId: workoutId)
            async let splitResult   = store.loadMuscleSplit(workoutId: workoutId)
            async let workoutResult = store.loadWorkout(id: workoutId)
            sets       = await setsResult
            muscleSplit = await splitResult
            workout     = await workoutResult
            loading     = false
            if let result = await store.loadExistingAnalysis(workoutId: workoutId) {
                aiAnalysis = result
                hasAIAnalysis = true
            }
        }
        .navigationTitle(workout?.routineName ?? "Session")
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
            ToolbarItem(placement: .navigationBarTrailing) {
                if workout?.routineId != nil {
                    Button { showShareSheet = true } label: {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundColor(Theme.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let wk = workout {
                let summary = store.buildSummaryFromSets(workout: wk, sets: sets)
                WorkoutSummaryShareView(summary: summary) {
                    showShareSheet = false
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .fullScreenCover(isPresented: $showAIAnalysis) {
            PostWorkoutAnalysisView(
                workoutId: workoutId,
                routineName: workout?.routineName ?? "",
                sets: sets,
                onDismiss: {
                    showAIAnalysis = false
                    hasAIAnalysis = true
                    Task {
                        if let result = await store.loadExistingAnalysis(workoutId: workoutId) {
                            aiAnalysis = result
                        }
                    }
                }
            )
            .environment(store)
        }
    }

    private var statsCard: some View {
        let wk = workout
        let isCardio = wk?.routineId == nil
        let totalVol = sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        return VStack(spacing: 0) {
            // Top row: cardio shows duration only; strength shows sets + vol + duration
            if isCardio {
                HStack(spacing: 0) {
                    statPill(wk?.duration ?? "—", "Duration")
                }
            } else {
                HStack(spacing: 0) {
                    statPill("\(sets.count)", "Sets")
                    Divider().frame(height: 40)
                    statPill(totalVol >= 1000 ? String(format: "%.1fk", totalVol / 1000) : "\(Int(totalVol))", "kg vol")
                    Divider().frame(height: 40)
                    statPill(wk?.duration ?? "—", "Duration")
                }
            }
            if wk?.calories != nil || wk?.avgHeartRate != nil {
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(spacing: 0) {
                    if let cal = wk?.calories {
                        statPillColored("\(cal)", "kcal", Color(hex: "fbbf24"))
                        if wk?.avgHeartRate != nil {
                            Divider().frame(height: 40)
                        }
                    }
                    if let hr = wk?.avgHeartRate {
                        statPillColored("\(hr)", "avg bpm", Color(hex: "ef4444"))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    private func statPill(_ value: String, _ label: String) -> some View {
        statPillColored(value, label, Theme.accent)
    }

    private func statPillColored(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3).fontWeight(.black).foregroundColor(color)
            Text(label).font(.system(size: 9, weight: .bold)).textCase(.uppercase)
                .foregroundColor(Theme.subtle)
        }.frame(maxWidth: .infinity)
    }

    // MARK: - AI Summary Card

    private func aiRatingInfo(_ rating: String) -> (String, String) {
        switch rating {
        case "excellent":         return ("EXCELLENT", "22c55e")
        case "good":              return ("GOOD", "3b82f6")
        case "average":           return ("AVERAGE", "f59e0b")
        case "needs_improvement": return ("NEEDS WORK", "ef4444")
        default:                  return (rating.uppercased(), "94a3b8")
        }
    }

    private func aiSummaryCard(_ ai: AIAnalysisResult) -> some View {
        let (ratingText, ratingColor) = aiRatingInfo(ai.overallRating)
        return VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "a855f7"))
                    Text("AI Analysis")
                        .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                        .foregroundColor(Theme.subtle)
                }
                Spacer()
                Button {
                    Task { await refreshAnalysis() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Theme.subtle)
                }
                Text(ratingText)
                    .font(.system(size: 9, weight: .black)).tracking(0.5)
                    .foregroundColor(Color(hex: ratingColor))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: ratingColor).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Summary text
            Text(ai.summary)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Color(hex: "e2e8f0"))
                .fixedSize(horizontal: false, vertical: true)

            // Strengths & Weaknesses inline
            if !ai.strengths.isEmpty || !ai.weaknesses.isEmpty {
                HStack(alignment: .top, spacing: 14) {
                    if !ai.strengths.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Strengths")
                                    .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.5)
                            }
                            .foregroundColor(Color(hex: "22c55e"))
                            ForEach(ai.strengths, id: \.self) { s in
                                Text(s)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "cbd5e1"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !ai.weaknesses.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.down.circle.fill")
                                    .font(.system(size: 9, weight: .bold))
                                Text("Improve")
                                    .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.5)
                            }
                            .foregroundColor(Color(hex: "f59e0b"))
                            ForEach(ai.weaknesses, id: \.self) { w in
                                Text(w)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(Color(hex: "cbd5e1"))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // Volume analysis inline
            if let vol = ai.volumeAnalysis {
                Rectangle().fill(Theme.border).frame(height: 1)
                HStack(spacing: 12) {
                    let todayStr = vol.todayVolume >= 1000 ? String(format: "%.1fk", vol.todayVolume / 1000) : "\(Int(vol.todayVolume))"
                    Text(todayStr).font(.system(size: 13, weight: .black)).foregroundColor(Theme.accent)
                    + Text(" kg vol").font(.system(size: 10, weight: .semibold)).foregroundColor(Theme.muted)
                    if let pct = vol.changePct {
                        let isUp = pct >= 0
                        HStack(spacing: 2) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(String(format: "%+.1f%%", pct))
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(Color(hex: isUp ? "22c55e" : "ef4444"))
                    }
                    Spacer()
                }
            }

            // Plateau alerts inline
            if let alerts = ai.plateauAlerts, !alerts.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text("Plateaus")
                            .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.5)
                    }
                    .foregroundColor(Color(hex: "ef4444"))
                    ForEach(alerts) { alert in
                        Text("\(alert.exerciseName): \(alert.suggestion)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "cbd5e1"))
                    }
                }
            }

            // Key suggestions preview
            if !ai.suggestions.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1)
                VStack(spacing: 6) {
                    ForEach(ai.suggestions) { s in
                        HStack(spacing: 6) {
                            Text(s.exerciseName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            let curW = s.currentWeight == 0 ? "BW" : "\(s.currentWeight.clean)kg"
                            let sugW = s.suggestedWeight == 0 ? "BW" : "\(s.suggestedWeight.clean)kg"
                            Text("\(curW)\u{00D7}\(s.currentReps)")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(Theme.muted)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(Color(hex: s.actionColor))
                            Text("\(sugW)\u{00D7}\(s.suggestedReps)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: s.actionColor))
                        }
                    }
                }
            }

            // Next session targets inline
            if let targets = ai.nextSessionTargets, !targets.isEmpty {
                Rectangle().fill(Theme.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 3) {
                        Image(systemName: "target")
                            .font(.system(size: 8, weight: .bold))
                        Text("Next Session")
                            .font(.system(size: 9, weight: .bold)).textCase(.uppercase).tracking(0.5)
                    }
                    .foregroundColor(Color(hex: "22c55e"))
                    ForEach(targets) { t in
                        HStack(spacing: 4) {
                            Text(t.exerciseName)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Spacer()
                            let w = t.targetWeight == 0 ? "BW" : "\(t.targetWeight.clean)kg"
                            Text("\(w)\u{00D7}\(t.targetReps)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(hex: "22c55e"))
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [Color(hex: "8b5cf6").opacity(0.06), Theme.surface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "8b5cf6").opacity(0.3)))
        .padding(.horizontal, 14)
    }

    // MARK: - Muscle Split Card

    private var muscleSplitCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Muscle Split")
                .font(.caption).fontWeight(.bold)
                .textCase(.uppercase).tracking(1)
                .foregroundColor(Theme.subtle)

            ForEach(muscleSplit, id: \.muscle) { item in
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
                                .frame(width: max(4, geo.size.width * CGFloat(item.pct / 100)), height: 8)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    private func muscleColor(_ muscle: String) -> Color {
        let m = muscle.lowercased()
        if m.contains("chest") || m.contains("pec")          { return Theme.accent }
        if m.contains("back") || m.contains("lat")           { return Color(hex: "3b82f6") }
        if m.contains("shoulder") || m.contains("delt")      { return Color(hex: "a855f7") }
        if m.contains("tricep")                               { return Color(hex: "f97316") }
        if m.contains("bicep")                                { return Color(hex: "ec4899") }
        if m.contains("quad") || m.contains("leg")           { return Color(hex: "ef4444") }
        if m.contains("hamstring")                            { return Color(hex: "dc2626") }
        if m.contains("glute")                                { return Color(hex: "f59e0b") }
        if m.contains("calf") || m.contains("calves")        { return Color(hex: "14b8a6") }
        if m.contains("core") || m.contains("ab")            { return Color(hex: "eab308") }
        return Theme.muted
    }

    // MARK: - Exercises Section

    private var exercisesSection: some View {
        let grouped = Dictionary(grouping: sets, by: \.exerciseName)
        let orderedNames = grouped.keys.sorted {
            let t0 = grouped[$0]?.map(\.loggedAt).min() ?? .distantPast
            let t1 = grouped[$1]?.map(\.loggedAt).min() ?? .distantPast
            return t0 < t1
        }
        return VStack(spacing: 10) {
            ForEach(orderedNames, id: \.self) { name in
                exerciseCard(name: name, exSets: grouped[name] ?? [])
            }
        }
    }

    private func exerciseCard(name: String, exSets: [WorkoutSet]) -> some View {
        let sortedSets = exSets.sorted { $0.setNumber < $1.setNumber }
        let bestIdx = sortedSets.indices.max(by: {
            sortedSets[$0].weightKg * Double(sortedSets[$0].reps) <
            sortedSets[$1].weightKg * Double(sortedSets[$1].reps)
        })

        return VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(hex: "e2e8f0"))
                Spacer()
                Text("\(sortedSets.count) set\(sortedSets.count == 1 ? "" : "s")")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Rectangle()
                .fill(Theme.border)
                .frame(height: 1)

            // Set rows
            ForEach(Array(sortedSets.enumerated()), id: \.element.id) { i, s in
                let isBest = i == bestIdx
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // Set number badge
                        ZStack {
                            Circle()
                                .fill(isBest ? Color(hex: "f59e0b").opacity(0.2) : Theme.bg)
                                .frame(width: 28, height: 28)
                            Text("\(s.setNumber)")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(isBest ? Color(hex: "f59e0b") : Theme.muted)
                        }

                        // Weight
                        if s.weightKg == 0 {
                            Text("BW")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(Theme.accent)
                        } else {
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text(s.weightKg.clean)
                                    .font(.system(size: 20, weight: .black))
                                    .foregroundColor(Theme.accent)
                                Text("kg")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Theme.muted)
                            }
                        }

                        Text("×")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(hex: "475569"))

                        // Reps
                        HStack(alignment: .lastTextBaseline, spacing: 2) {
                            Text("\(s.reps)")
                                .font(.system(size: 20, weight: .black))
                                .foregroundColor(.white)
                            Text("reps")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(Theme.muted)
                        }

                        Spacer()

                        if isBest {
                            Text("BEST")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                                .foregroundColor(Color(hex: "f59e0b"))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color(hex: "f59e0b").opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(isBest ? Color(hex: "f59e0b").opacity(0.04) : Color.clear)

                    if i < sortedSets.count - 1 {
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                            .padding(.leading, 54)
                    }
                }
            }
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
        .padding(.horizontal, 14)
    }

    // MARK: - Refresh AI Analysis

    private func refreshAnalysis() async {
        aiAnalysis = nil
        await store.deleteAnalysisCache(workoutId: workoutId)
        let result = await store.requestAIAnalysis(
            workoutId: workoutId,
            routineName: workout?.routineName ?? "",
            sets: sets
        )
        aiAnalysis = result
        hasAIAnalysis = result != nil
    }
}