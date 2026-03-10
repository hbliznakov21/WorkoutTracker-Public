import SwiftUI
import AudioToolbox
import UIKit

struct ActiveWorkoutView: View {
    @Environment(WorkoutStore.self) var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var elapsed: String = "0:00"
    @State private var timer: Timer?
    @State private var restSeconds: Int = 0
    @State private var restTotalSeconds: Int = 0
    @State private var restTimer: Timer?
    @State private var restEndTime: TimeInterval = 0
    @State private var restExerciseId: UUID?
    @State private var restExerciseName: String = ""
    @State private var showFinishAlert = false
    @State private var restOverrides: [UUID: Int] = [:]
    @State private var sessionGoals: SessionGoalsResult?
    @State private var goalsLoading = false

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg
            VStack(spacing: 0) {
                WorkoutHeader(
                    elapsed: elapsed,
                    showFinishAlert: $showFinishAlert
                )
                ScrollView {
                    VStack(spacing: 14) {
                        if store.isDeloadWeek {
                            deloadModeBanner
                        }

                        if goalsLoading {
                            goalsLoadingCard
                        } else if let goals = sessionGoals, !allGoalsAnswered {
                            aiGoalsCard(goals)
                        }

                        // Start button — shown when workout is prepared but not yet started
                        if store.workoutStartTime == nil {
                            Button {
                                Haptics.medium()
                                Task { await store.beginWorkout() }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 18))
                                    Text("Start Workout")
                                        .font(.headline).fontWeight(.bold)
                                }
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(Theme.accent)
                                .foregroundColor(.black)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 14)
                            .transition(.opacity.combined(with: .scale))
                        }

                        ForEach(groupedExercises, id: \.id) { group in
                            if group.exercises.count > 1 {
                                InterleavedSupersetBlock(
                                    exercises: group.exercises,
                                    store: store,
                                    onLogSet: { re, idx in
                                        Haptics.medium()
                                        Task { await store.logSet(
                                            exerciseId: re.exercises.id,
                                            exerciseName: re.exercises.name,
                                            setIndex: idx
                                        )}
                                        let allDoneAfterLog = store.sets[re.exercises.id]?.allSatisfy(\.isDone) ?? false
                                        if store.workoutStartTime != nil, !allDoneAfterLog, shouldStartRest(for: re) {
                                            startRest(id: re.exercises.id, name: re.exercises.name)
                                        }
                                    },
                                    onUnlogSet: { re, idx in
                                        if restExerciseId == re.exercises.id { stopRest() }
                                        Task { await store.unlogSet(exerciseId: re.exercises.id, setIndex: idx) }
                                    },
                                    onEditSet: { re, idx, w, r in
                                        Task { await store.editSet(
                                            exerciseId: re.exercises.id,
                                            exerciseName: re.exercises.name,
                                            setIndex: idx,
                                            newWeight: w,
                                            newReps: r
                                        )}
                                    },
                                    restOverrides: restOverrides,
                                    onRestChanged: { re, newVal in
                                        restOverrides[re.exercises.id] = newVal
                                    },
                                    defaultRestSecs: { re in defaultRestSecs(for: re) }
                                )
                            } else if let re = group.exercises.first {
                                exerciseBlock(for: re)
                            }
                        }
                        if store.workoutStartTime != nil {
                            Button {
                                showFinishAlert = true
                            } label: {
                                Text("Finish Workout")
                                    .font(.headline).fontWeight(.bold)
                                    .frame(maxWidth: .infinity).padding(.vertical, 16)
                                    .background(Color(hex: "ef4444"))
                                    .foregroundColor(.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .padding(.horizontal, 14).padding(.bottom, 24)
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if let routine = store.pendingRoutine {
                goalsLoading = true
                sessionGoals = await store.generateSessionGoals(
                    routineName: routine.name,
                    exercises: store.activeExercises
                )
                goalsLoading = false
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
                .foregroundColor(Theme.accent)
            }
        }
        // Rest timer bar slides up from bottom
        .safeAreaInset(edge: .bottom) {
            if restSeconds > 0 {
                RestTimerBar(
                    restSeconds: restSeconds,
                    restTotalSeconds: restTotalSeconds,
                    restExerciseName: restExerciseName,
                    onAdjust: { adjustRest($0) },
                    onSkip: { stopRest() }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear { startElapsedTimer() }
        .onDisappear { timer?.invalidate(); restTimer?.invalidate() }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active, restEndTime > 0 {
                let remaining = Int(restEndTime - Date().timeIntervalSince1970)
                if remaining <= 0 {
                    // Timer expired while in background
                    AudioServicesPlaySystemSound(SystemSoundID(1322))
                    Haptics.triplePulse()
                    stopRest()
                } else {
                    // Still running — update display and restart tick timer
                    restSeconds = remaining
                    restTimer?.invalidate()
                    restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                        let left = max(0, Int(restEndTime - Date().timeIntervalSince1970))
                        if left <= 0 {
                            AudioServicesPlaySystemSound(SystemSoundID(1322))
                            Haptics.triplePulse()
                            stopRest()
                        } else {
                            restSeconds = left
                        }
                    }
                }
            }
        }
        .onChange(of: store.restSkippedFromWatch) { _, skipped in
            if skipped {
                store.restSkippedFromWatch = false
                stopRest()
            }
        }
        .alert("Finish workout?", isPresented: $showFinishAlert) {
            if store.workoutStartTime == nil {
                Button("Leave", role: .destructive) { store.cancelPreparedWorkout() }
                Button("Stay", role: .cancel) {}
            } else if store.totalSetsLogged == 0 {
                Button("Discard", role: .destructive) { Task { await store.discardWorkout() } }
            } else {
                Button("Save & Finish") { Haptics.success(); Task { await store.finishWorkout() } }
                Button("Cancel", role: .cancel) {}
            }
        } message: {
            if store.workoutStartTime == nil {
                Text("Workout not started yet. Leave?")
            } else {
                Text(store.totalSetsLogged == 0
                     ? "No sets logged \u{2014} this workout will be discarded."
                     : "\(store.totalSetsLogged) sets \u{00B7} \(formattedVolume) kg volume")
            }
        }
    }

    // MARK: - Timer helpers

    private func startElapsedTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in
                guard let start = store.workoutStartTime else { return }
                let s = Int(Date().timeIntervalSince(start))
                elapsed = "\(s / 60):\(String(format: "%02d", s % 60))"
            }
        }
    }

    private func startRest(id: UUID, name: String) {
        restTimer?.invalidate()
        restExerciseId   = id
        restExerciseName = name
        let re           = store.activeExercises.first { $0.exercises.id == id }
        let secs         = restOverrides[id] ?? defaultRestSecs(for: re)
        restSeconds      = secs
        restTotalSeconds = secs
        restEndTime      = Date().timeIntervalSince1970 + Double(secs)
        PhoneConnectivityManager.shared.sendRestStart(seconds: secs, endTime: restEndTime)
        restTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            let left = max(0, Int(restEndTime - Date().timeIntervalSince1970))
            if left <= 0 {
                AudioServicesPlaySystemSound(SystemSoundID(1322))
                Haptics.triplePulse()
                stopRest()
            } else {
                restSeconds = left
            }
        }
    }

    private func stopRest() {
        restTimer?.invalidate()
        restTimer = nil
        restSeconds = 0
        restEndTime = 0
        restExerciseId = nil
        PhoneConnectivityManager.shared.sendRestStop()
    }

    private func adjustRest(_ delta: Int) {
        restSeconds = max(5, restSeconds + delta)
        restEndTime = Date().timeIntervalSince1970 + Double(restSeconds)
        PhoneConnectivityManager.shared.sendRestStart(seconds: restSeconds, endTime: restEndTime)
    }

    // Only start rest on the LAST exercise in a superset group.
    // Supports formats: "SS1A"/"SS1B" (prefixed+letter), "1A"/"1B" (number+letter),
    // "A"/"A" (single-letter shared), "SS2"/"SS2" (shared string, no letter suffix).
    private func shouldStartRest(for re: RoutineExercise) -> Bool {
        guard let sg = re.supersetGroup, !sg.isEmpty else { return true }

        // Check if the last character is a letter (e.g., "1A", "SS1B")
        if let lastChar = sg.last, lastChar.isLetter {
            let prefix = String(sg.dropLast())

            // Single-letter groups (e.g. "A","A"): all exercises share the same letter.
            if prefix.isEmpty {
                let sameGroup = store.activeExercises.filter { $0.supersetGroup == sg }
                guard let lastPos = sameGroup.map(\.position).max() else { return true }
                return re.position >= lastPos
            }

            // Prefixed groups (e.g. "SS1A","SS1B", "1A","1B"): rest after the highest letter.
            let groupMembers = store.activeExercises
                .compactMap { ex -> Character? in
                    guard let g = ex.supersetGroup, g.hasPrefix(prefix),
                          let c = g.last, c.isLetter else { return nil }
                    return c
                }
            guard let maxLetter = groupMembers.max() else { return true }
            return lastChar >= maxLetter
        }

        // Shared group string (e.g. "SS2","SS2"): all members have the same string.
        // Rest after the last positional exercise in the group.
        let sameGroup = store.activeExercises.filter { $0.supersetGroup == sg }
        guard let lastPos = sameGroup.map(\.position).max() else { return true }
        return re.position >= lastPos
    }

    private func effectiveRestSecs(for re: RoutineExercise) -> Int {
        restOverrides[re.exercises.id] ?? defaultRestSecs(for: re)
    }

    private func defaultRestSecs(for re: RoutineExercise?) -> Int {
        #if SONYA
        re?.restSeconds ?? 60
        #else
        re?.restSeconds ?? 90
        #endif
    }

    private var formattedVolume: String {
        store.totalVolume >= 1000
            ? String(format: "%.1fk", store.totalVolume / 1000)
            : "\(Int(store.totalVolume))"
    }

    // MARK: - Exercise block builder

    private func exerciseBlock(for re: RoutineExercise) -> some View {
        ExerciseBlock(
            re: re,
            onLogSet: { idx in
                Haptics.medium()
                Task { await store.logSet(
                    exerciseId: re.exercises.id,
                    exerciseName: re.exercises.name,
                    setIndex: idx
                )}
                let allDoneAfterLog = store.sets[re.exercises.id]?.allSatisfy(\.isDone) ?? false
                if store.workoutStartTime != nil, !allDoneAfterLog, shouldStartRest(for: re) {
                    startRest(id: re.exercises.id, name: re.exercises.name)
                }
            },
            onUnlogSet: { idx in
                if restExerciseId == re.exercises.id { stopRest() }
                Task { await store.unlogSet(exerciseId: re.exercises.id, setIndex: idx) }
            },
            onEditSet: { idx, newWeight, newReps in
                Task { await store.editSet(
                    exerciseId: re.exercises.id,
                    exerciseName: re.exercises.name,
                    setIndex: idx,
                    newWeight: newWeight,
                    newReps: newReps
                )}
            },
            onAddSet: { store.addSet(exerciseId: re.exercises.id, after: $0) },
            onRemoveSet: { store.removeSet(exerciseId: re.exercises.id, setIndex: $0) },
            onDropSet: { store.addDropSet(exerciseId: re.exercises.id) },
            restSeconds: effectiveRestSecs(for: re),
            onRestChanged: { newVal in
                restOverrides[re.exercises.id] = newVal
            }
        )
    }

    // MARK: - Superset grouping

    private struct ExerciseGroup: Identifiable {
        let id: String
        let label: String
        let exercises: [RoutineExercise]
    }

    /// Groups consecutive exercises by superset group.
    /// Returns groups of 1 (standalone) or 2+ (superset).
    private var groupedExercises: [ExerciseGroup] {
        var result: [ExerciseGroup] = []
        var i = 0
        let exs = store.activeExercises
        while i < exs.count {
            let re = exs[i]
            let key = supersetGroupKey(for: re)
            if let key {
                // Collect all consecutive exercises with the same group key
                var group = [re]
                var j = i + 1
                while j < exs.count, supersetGroupKey(for: exs[j]) == key {
                    group.append(exs[j])
                    j += 1
                }
                if group.count > 1 {
                    result.append(ExerciseGroup(
                        id: "ss-\(key)-\(i)",
                        label: "SUPERSET",
                        exercises: group
                    ))
                    i = j
                } else {
                    result.append(ExerciseGroup(id: re.id.uuidString, label: "", exercises: [re]))
                    i += 1
                }
            } else {
                result.append(ExerciseGroup(id: re.id.uuidString, label: "", exercises: [re]))
                i += 1
            }
        }
        return result
    }

    /// Normalizes superset group to a common key for grouping.
    /// "A","A" → "A" | "SS1A","SS1B" → "SS1" | "1A","1B" → "1" | "SS2","SS2" → "SS2"
    private func supersetGroupKey(for re: RoutineExercise) -> String? {
        guard let sg = re.supersetGroup, !sg.isEmpty else { return nil }
        if let lastChar = sg.last, lastChar.isLetter {
            let prefix = String(sg.dropLast())
            if prefix.isEmpty {
                // Single letter like "A" — key is the letter itself
                return sg
            }
            // Prefixed like "SS1A" → key is "SS1"
            return prefix
        }
        // Shared string like "SS2"
        return sg
    }

    // MARK: - AI Goals Card

    @State private var goalsExpanded = true
    @State private var goalStatuses: [String: String] = [:]  // exerciseName -> "accepted"/"declined"

    private var allGoalsAnswered: Bool {
        guard let goals = sessionGoals else { return false }
        return !goals.goals.isEmpty && goals.goals.allSatisfy { goalStatuses[$0.exerciseName] != nil }
    }

    private var goalsLoadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(Color(hex: "a855f7"))
                .scaleEffect(0.8)
            Text("AI analyzing your exercises...")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.subtle)
            Spacer()
        }
        .padding(12)
        .background(Color(hex: "a855f7").opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "a855f7").opacity(0.2)))
        .padding(.horizontal, 12)
    }

    private func aiGoalsCard(_ result: SessionGoalsResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color(hex: "a855f7"))
                Text("AI Session Goals")
                    .font(.system(size: 10, weight: .bold)).textCase(.uppercase).tracking(1)
                    .foregroundColor(Theme.subtle)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { goalsExpanded.toggle() }
                } label: {
                    Image(systemName: goalsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.muted)
                }
                Button {
                    Task { await refreshSessionGoals() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Theme.muted)
                }
                .disabled(goalsLoading)
                Button {
                    withAnimation { sessionGoals = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Theme.muted)
                }
            }

            // Summary + Apply All
            HStack {
                Text(result.summary)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "e2e8f0"))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if result.goals.contains(where: { goalStatuses[$0.exerciseName] == nil }) {
                    Button {
                        for goal in result.goals where goalStatuses[goal.exerciseName] == nil {
                            acceptGoal(goal)
                        }
                    } label: {
                        Text("Apply All")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(hex: "22c55e"))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Per-exercise goals
            if goalsExpanded {
                VStack(spacing: 8) {
                    ForEach(result.goals) { goal in
                        let status = goalStatuses[goal.exerciseName]
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(goal.exerciseName)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Spacer()
                                let w = goal.suggestedWeight == 0 ? "BW" : "\(goal.suggestedWeight.clean)kg"
                                Text("\(w) \u{00D7} \(goal.suggestedReps)")
                                    .font(.system(size: 11, weight: .black))
                                    .foregroundColor(Theme.accent)
                                Text(goal.actionLabel)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(Color(hex: goal.actionColor))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(Color(hex: goal.actionColor).opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }

                            // Drop set info
                            if let dsW = goal.dropSetWeight, let dsR = goal.dropSetReps {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.down.circle.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(Color(hex: "a855f7"))
                                    Text("Drop set: \(dsW.clean)kg \u{00D7} \(dsR)")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(Color(hex: "a855f7"))
                                }
                            }

                            Text(goal.reasoning)
                                .font(.system(size: 10))
                                .foregroundColor(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)

                            if status == nil {
                                HStack(spacing: 8) {
                                    Button {
                                        acceptGoal(goal)
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 9, weight: .bold))
                                            Text("Apply")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .foregroundColor(.black)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Color(hex: "22c55e"))
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                    }
                                    Button {
                                        withAnimation { goalStatuses[goal.exerciseName] = "declined" }
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 9, weight: .bold))
                                            Text("Skip")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .foregroundColor(Theme.subtle)
                                        .padding(.horizontal, 10).padding(.vertical, 5)
                                        .background(Theme.bg)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
                                    }
                                }
                            } else {
                                HStack(spacing: 3) {
                                    Image(systemName: status == "accepted" ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .font(.system(size: 10))
                                    Text(status == "accepted" ? "Applied" : "Skipped")
                                        .font(.system(size: 10, weight: .semibold))
                                }
                                .foregroundColor(status == "accepted" ? Color(hex: "22c55e") : Theme.muted)
                            }
                        }
                        .padding(8)
                        .background(Theme.surface.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                // Collapsed: show compact summary row
                HStack(spacing: 12) {
                    ForEach(Array(result.goals.prefix(4)), id: \.exerciseName) { goal in
                        HStack(spacing: 2) {
                            Circle()
                                .fill(Color(hex: goal.actionColor))
                                .frame(width: 5, height: 5)
                            Text(shortName(goal.exerciseName))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Theme.muted)
                                .lineLimit(1)
                        }
                    }
                    if result.goals.count > 4 {
                        Text("+\(result.goals.count - 4)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Theme.muted)
                    }
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [Color(hex: "a855f7").opacity(0.06), Theme.surface],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(hex: "a855f7").opacity(0.3)))
        .padding(.horizontal, 12)
    }

    private func acceptGoal(_ goal: SessionGoal) {
        // Find the exercise in activeExercises by name
        guard let re = store.activeExercises.first(where: { $0.exercises.name == goal.exerciseName }) else { return }
        let eid = re.exercises.id

        // Update all sets for this exercise to the suggested weight/reps
        if var sets = store.sets[eid] {
            for i in sets.indices where !sets[i].isDone {
                if goal.suggestedWeight > 0 {
                    sets[i].weight = goal.suggestedWeight
                }
                sets[i].reps = goal.suggestedReps
            }
            // Add a drop set if the AI suggests one
            if goal.action == "add_drop_set",
               let dsWeight = goal.dropSetWeight, let dsReps = goal.dropSetReps {
                sets.append(SetState(weight: dsWeight, reps: dsReps, isDropSet: true))
            }
            store.sets[eid] = sets
        }

        withAnimation { goalStatuses[goal.exerciseName] = "accepted" }
        Haptics.medium()
    }

    private func refreshSessionGoals() async {
        guard let routine = store.pendingRoutine else { return }
        goalsLoading = true
        sessionGoals = nil
        goalStatuses = [:]
        await store.deleteSessionGoalsCache(routineName: routine.name)
        sessionGoals = await store.generateSessionGoals(
            routineName: routine.name,
            exercises: store.activeExercises
        )
        goalsLoading = false
    }

    private func shortName(_ name: String) -> String {
        let words = name.split(separator: " ")
        if words.count <= 2 { return name }
        return words.prefix(2).joined(separator: " ")
    }

    // MARK: - Deload mode banner

    private var deloadModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.2.circlepath")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(Color(hex: "38bdf8"))
            Text("DELOAD WEEK")
                .font(.system(size: 10, weight: .bold)).tracking(1)
                .foregroundColor(Color(hex: "38bdf8"))
            Text("Same weight, 50% sets")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.subtle)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(hex: "38bdf8").opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(hex: "38bdf8").opacity(0.2)))
        .padding(.horizontal, 12)
    }
}

// MARK: - Superset Group Block

struct SupersetGroupBlock<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            // Superset header
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "38bdf8"))
                Text(label)
                    .font(.system(size: 9, weight: .black)).tracking(1.5)
                    .foregroundColor(Color(hex: "38bdf8"))
                Rectangle()
                    .fill(Color(hex: "38bdf8").opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Exercise blocks inside — reduced horizontal padding so they nest visually
            VStack(spacing: 8) {
                content
            }
            .padding(.bottom, 8)
        }
        .background(Color(hex: "38bdf8").opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "38bdf8").opacity(0.25), lineWidth: 1.5)
        )
        .padding(.horizontal, 4)
    }
}

// MARK: - Interleaved Superset Block

struct InterleavedSupersetBlock: View {
    let exercises: [RoutineExercise]
    let store: WorkoutStore
    let onLogSet: (RoutineExercise, Int) -> Void
    let onUnlogSet: (RoutineExercise, Int) -> Void
    let onEditSet: (RoutineExercise, Int, Double, Int) -> Void
    let restOverrides: [UUID: Int]
    let onRestChanged: (RoutineExercise, Int) -> Void
    let defaultRestSecs: (RoutineExercise?) -> Int

    private var maxSets: Int {
        exercises.map { store.sets[$0.exercises.id]?.count ?? $0.targetSets }.max() ?? 3
    }

    var body: some View {
        VStack(spacing: 0) {
            // Superset header
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(Color(hex: "38bdf8"))
                Text("SUPERSET")
                    .font(.system(size: 9, weight: .black)).tracking(1.5)
                    .foregroundColor(Color(hex: "38bdf8"))
                Rectangle()
                    .fill(Color(hex: "38bdf8").opacity(0.3))
                    .frame(height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Exercise name headers
            HStack(spacing: 8) {
                ForEach(exercises) { re in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(re.exercises.name)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            if let videoURL = ExerciseVideoLinks.url(for: re.exercises.name) {
                                Link(destination: videoURL) {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 13))
                                        .foregroundColor(Color(hex: "38bdf8"))
                                }
                            }
                        }
                        Text("\(re.targetSets)s \u{00D7} \(re.targetRepsMin ?? 0)\u{2013}\(re.targetRepsMax ?? 0)")
                            .font(.system(size: 10))
                            .foregroundColor(Theme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)

            // Rounds
            ForEach(0..<maxSets, id: \.self) { round in
                VStack(spacing: 0) {
                    // Round label
                    HStack(spacing: 4) {
                        Text("ROUND \(round + 1)")
                            .font(.system(size: 8, weight: .black)).tracking(1)
                            .foregroundColor(Color(hex: "38bdf8").opacity(0.6))
                        Rectangle()
                            .fill(Color(hex: "38bdf8").opacity(0.15))
                            .frame(height: 1)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)

                    // One row per exercise in this round
                    ForEach(exercises) { re in
                        let exId = re.exercises.id
                        let sets = store.sets[exId] ?? []
                        if round < sets.count {
                            interleavedSetRow(re: re, setIndex: round, sets: sets)
                        }
                    }
                }
            }

            Spacer().frame(height: 8)
        }
        .background(Color(hex: "38bdf8").opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color(hex: "38bdf8").opacity(0.25), lineWidth: 1.5)
        )
        .padding(.horizontal, 4)
    }

    private func interleavedSetRow(re: RoutineExercise, setIndex: Int, sets: [SetState]) -> some View {
        let exId = re.exercises.id
        let isBodyweight = re.exercises.equipment?.lowercased() == "bodyweight"
        let isCable: Bool = {
            let eq = re.exercises.equipment?.lowercased() ?? ""
            return eq.contains("cable") || eq.contains("machine")
        }()
        let lastSets = store.lastSets[exId] ?? []

        return HStack(spacing: 6) {
            // Abbreviated exercise name
            Text(abbreviate(re.exercises.name))
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.subtle)
                .frame(width: 56, alignment: .leading)
                .lineLimit(1)

            SetRow(
                setNumber: setIndex + 1,
                state: Binding(
                    get: {
                        guard let arr = store.sets[exId], arr.indices.contains(setIndex) else {
                            return SetState(weight: 20, reps: 10)
                        }
                        return arr[setIndex]
                    },
                    set: {
                        guard store.sets[exId]?.indices.contains(setIndex) == true else { return }
                        store.sets[exId]?[setIndex] = $0
                    }
                ),
                lastSet: lastSets.indices.contains(setIndex) ? lastSets[setIndex] : nil,
                isBodyweight: isBodyweight,
                isCableMachine: isCable,
                targetRepsMin: re.targetRepsMin,
                targetRepsMax: re.targetRepsMax,
                onLog: {
                    if isBodyweight {
                        store.sets[exId]?[setIndex].weight = 0
                    }
                    onLogSet(re, setIndex)
                },
                onUnlog: { onUnlogSet(re, setIndex) },
                onEdit: { w, r in onEditSet(re, setIndex, w, r) }
            )
        }
        .padding(.horizontal, 6)
    }

    private func abbreviate(_ name: String) -> String {
        // Strip parenthetical content: "Back Extensions (Glutes)" → "Back Extensions"
        let cleaned = name.replacingOccurrences(of: "\\s*\\(.*?\\)", with: "", options: .regularExpression)
        let words = cleaned.split(separator: " ").map(String.init)
        if words.count <= 2 { return cleaned }
        // For 3+ words: use first word truncated + first letters of rest
        // e.g. "Rope Hammer Curls" → "Rope HC", "Seated Wide Row" → "Seat WR"
        let first = String(words[0].prefix(4))
        let rest = words.dropFirst().map { String($0.prefix(1)) }.joined()
        return "\(first) \(rest)"
    }
}
