import Foundation
import HealthKit
import Observation
import SwiftUI
import WidgetKit
import os.log

private let logger = Logger(subsystem: "com.hbliznakov.WorkoutTracker", category: "WorkoutStore")

@Observable
@MainActor
final class WorkoutStore {
    static let shared = WorkoutStore()
    let sb = SupabaseClient.shared

    // MARK: - Loaded data
    var routines: [Routine] = []
    var history:  [Workout] = []
    var isLoading = false
    var errorMessage: String?

    // MARK: - Body weight
    var bodyWeightLog: [BodyWeight] = []

    // MARK: - Apple Health import
    var pendingHKWorkouts: [HKWorkoutEntry] = []
    var importingWorkoutId: UUID?
    var importError: String?

    var dismissedUUIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: UDKey.dismissedHKUUIDs) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: UDKey.dismissedHKUUIDs) }
    }

    // MARK: - Rest days
    var restDays: Set<Date> = []

    #if !SONYA
    // MARK: - Cardio tracking
    var cardioThisWeek: [Date] = []
    #endif

    // MARK: - Today's routine completion
    var todayRoutineCompleted: Bool = false

    // MARK: - Deload week tracking
    var weeksWithoutDeload: Int {
        get { UserDefaults.standard.integer(forKey: UDKey.deloadWeeks) }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.deloadWeeks) }
    }

    var isDeloadWeek: Bool {
        get { UserDefaults.standard.bool(forKey: UDKey.deloadActive) }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.deloadActive) }
    }

    var deloadSuggestionDismissed: Bool {
        get { UserDefaults.standard.bool(forKey: UDKey.deloadDismissed) }
        set { UserDefaults.standard.set(newValue, forKey: UDKey.deloadDismissed) }
    }

    /// Returns true when deload suggestion banner should be shown
    var shouldSuggestDeload: Bool {
        !isDeloadWeek && weeksWithoutDeload >= 2 && !deloadSuggestionDismissed
    }

    // MARK: - Active workout
    var activeWorkout: Workout?
    var activeExercises: [RoutineExercise] = []
    var sets:      [UUID: [SetState]] = [:]   // exerciseId → set states
    var lastSets:  [UUID: [SetState]] = [:]   // exerciseId → last session sets
    var restTimerSeconds: Int = 0
    var restTimerExerciseId: UUID?
    var restTimerName: String = ""
    var workoutStartTime: Date?
    var totalSetsLogged: Int = 0
    var totalVolume: Double  = 0
    var pendingRoutine: Routine?           // Set when workout prepared but not yet started
    var liveHeartRate: Double = 0
    var liveCalories: Double  = 0
    var restSkippedFromWatch: Bool = false

    // MARK: - Progression suggestions (computed after finishing a workout)
    var progressionSuggestions: [ProgressionSuggestion] = []

    // MARK: - Overload suggestions (2+ consecutive sessions at target reps)
    var overloadSuggestions: [OverloadSuggestion] = []

    private static let dismissedOverloadKey = "dismissed_overload_ids"
    var dismissedOverloadIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.dismissedOverloadKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.dismissedOverloadKey) }
    }

    func dismissOverloadSuggestion(_ suggestion: OverloadSuggestion) {
        dismissedOverloadIDs.insert(suggestion.id)
        withAnimation { overloadSuggestions.removeAll { $0.id == suggestion.id } }
    }

    func dismissAllOverloadSuggestions() {
        for s in overloadSuggestions { dismissedOverloadIDs.insert(s.id) }
        withAnimation { overloadSuggestions = [] }
    }

    // MARK: - Last finished workout summary (for share sheet)
    var lastFinishedSummary: WorkoutSummaryData?

    // MARK: - AI Analysis (post-workout blocking screen)
    var showPostWorkoutAnalysis = false
    var analysisWorkoutId: UUID?
    var analysisRoutineName: String = ""
    var analysisSets: [WorkoutSet] = []

    // MARK: - Cached AI weight insight (persists across navigation, refreshes daily)
    var cachedWeightInsight: WeightInsight?
    var weightInsightDate: String = ""

    // MARK: - User phase goals (Sonya build)
    var userPhaseGoals: UserPhaseGoals?

    // MARK: - Navigation
    var previousScreen: AppScreen = .home
    var activeScreen: AppScreen = .home {
        didSet { previousScreen = oldValue }
    }

    // MARK: - ISO formatter for inserts
    let isoFmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    // MARK: - Editable weekly schedule
    #if SONYA
    static let appGroupID = "group.com.hbliznakov.WorkoutTrackerSonya"
    #else
    static let appGroupID = "group.com.hbliznakov.WorkoutTracker"
    #endif
    static let sharedDefaults = UserDefaults(suiteName: appGroupID)

    var schedule: [String: String] = {
        if let data = UserDefaults(suiteName: appGroupID)?.data(forKey: "weeklySchedule"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return dict
        }
        if let data = UserDefaults.standard.data(forKey: "weeklySchedule"),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            return dict
        }
        return defaultWeeklySchedule
    }()

    // MARK: - Last performed dates (for Quick Start cards)
    var lastPerformedByRoutine: [String: Date] = [:]

    // MARK: - Routine Editor
    var editingExercises: [RoutineExercise] = []
    var allExercises: [Exercise] = []

    // MARK: - Load routines
    func loadRoutines(force: Bool = false) async {
        guard force || routines.isEmpty else { return }
        do {
            let fetched: [Routine] = try await sb.get("routines?select=*&order=name")
            routines = fetched
            LocalCache.shared.saveRoutines(fetched)
            syncScheduleToSupabase()
        } catch {
            routines = LocalCache.shared.loadRoutines() ?? []
            if routines.isEmpty { errorMessage = error.localizedDescription }
        }
    }

    // MARK: - Last performed dates
    func loadLastPerformed() async {
        struct RoutineDate: Decodable {
            let routineName: String
            let startedAt: Date
            enum CodingKeys: String, CodingKey {
                case routineName = "routine_name"
                case startedAt  = "started_at"
            }
        }
        guard let rows: [RoutineDate] = await sb.tryGet(
            "workouts?select=routine_name,started_at&finished_at=not.is.null&order=started_at.desc&limit=200"
        ) else { return }
        var result: [String: Date] = [:]
        for row in rows {
            if result[row.routineName] == nil {
                result[row.routineName] = row.startedAt
            }
        }
        lastPerformedByRoutine = result
    }

    // MARK: - Load history
    func loadHistory() async {
        isLoading = true
        defer { isLoading = false }
        do {
            history = try await sb.get(
                "workouts?select=id,routine_id,routine_name,started_at,finished_at,calories,avg_heart_rate" +
                "&finished_at=not.is.null&order=started_at.desc&limit=60"
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Start workout
    func startWorkout(routine: Routine) async {
        totalSetsLogged  = 0
        totalVolume      = 0
        sets             = [:]
        lastSets         = [:]
        workoutStartTime = nil
        pendingRoutine   = routine

        var exs: [RoutineExercise] = []
        if let fetched: [RoutineExercise] = await sb.tryGet(
            "routine_exercises?select=*,exercises(id,name,muscle_group,equipment)" +
            "&routine_id=eq.\(routine.id)&order=position"
        ) {
            exs = fetched
            LocalCache.shared.saveRoutineExercises(fetched, routineId: routine.id)
        } else if let cached = LocalCache.shared.loadRoutineExercises(routineId: routine.id) {
            exs = cached
        }

        var seen = Set<UUID>()
        activeExercises = exs.filter { re in
            guard seen.insert(re.exercises.id).inserted else { return false }
            return true
        }

        guard !activeExercises.isEmpty else {
            errorMessage = "No exercises found — check your connection."
            if let wkId = activeWorkout?.id {
                OfflineQueue.shared.dequeueWorkout(id: wkId)
            }
            activeWorkout = nil
            workoutStartTime = nil
            pendingRoutine = nil
            return
        }

        struct LastSetRow: Decodable {
            let exerciseId: UUID
            let workoutId:  UUID
            let weightKg:   Double
            let reps:       Int
            let setNumber:  Int
            enum CodingKeys: String, CodingKey {
                case exerciseId = "exercise_id"
                case workoutId  = "workout_id"
                case weightKg   = "weight_kg"
                case reps
                case setNumber  = "set_number"
            }
        }
        let exIds = activeExercises.map { $0.exercises.id.uuidString }.joined(separator: ",")
        let setLimit = max(500, activeExercises.count * 10)
        if !exIds.isEmpty,
           let rows: [LastSetRow] = await sb.tryGet(
               "workout_sets?select=exercise_id,workout_id,weight_kg,reps,set_number" +
               "&exercise_id=in.(\(exIds))&order=exercise_id,logged_at.desc&limit=\(setLimit)"
           ) {
            let byExercise = Dictionary(grouping: rows, by: \.exerciseId)
            var seeded: [UUID: [SetState]] = [:]
            var cachedSets: [UUID: [CachedSet]] = [:]
            for (eid, sets) in byExercise {
                guard let latestWorkoutId = sets.first?.workoutId else { continue }
                let sessionSets = sets
                    .filter { $0.workoutId == latestWorkoutId }
                    .sorted { $0.setNumber < $1.setNumber }
                seeded[eid] = sessionSets.map { SetState(weight: $0.weightKg, reps: $0.reps) }
                cachedSets[eid] = sessionSets.map {
                    CachedSet(exerciseId: $0.exerciseId, workoutId: $0.workoutId,
                              weightKg: $0.weightKg, reps: $0.reps, setNumber: $0.setNumber)
                }
            }
            lastSets = seeded
            LocalCache.shared.saveLastSets(cachedSets)
        } else if let cached = LocalCache.shared.loadLastSets() {
            var seeded: [UUID: [SetState]] = [:]
            for (eid, sets) in cached {
                let sorted = sets.sorted { $0.setNumber < $1.setNumber }
                seeded[eid] = sorted.map { SetState(weight: $0.weightKg, reps: $0.reps) }
            }
            lastSets = seeded
        }

        for re in activeExercises {
            let eid     = re.exercises.id
            let prev    = lastSets[eid] ?? []
            let tgt     = re.targetSets
            let minReps = re.targetRepsMin ?? re.targetRepsMax ?? 10

            sets[eid] = (0..<tgt).map { i in
                let ref        = prev.indices.contains(i) ? prev[i] : prev.last
                let lastWeight = ref?.weight ?? 20
                let lastReps   = ref?.reps   ?? minReps
                return SetState(weight: lastWeight, reps: lastReps)
            }
        }

        activeScreen = .workout
    }

    // MARK: - Begin workout tracking (timer + DB record)
    func beginWorkout() async {
        guard let routine = pendingRoutine, workoutStartTime == nil else { return }

        let now = Date()
        let nowStr = isoFmt.string(from: now)
        workoutStartTime = now

        let insert = WorkoutInsert(
            routineId: routine.id,
            routineName: routine.name,
            startedAt: nowStr
        )
        if let wk: Workout = try? await sb.post("workouts", body: insert, returning: Workout.self) {
            activeWorkout = wk
        } else {
            let localId = UUID()
            activeWorkout = Workout(
                id: localId,
                routineId: routine.id,
                routineName: routine.name,
                startedAt: now,
                finishedAt: nil,
                calories: nil,
                avgHeartRate: nil
            )
            OfflineQueue.shared.enqueueWorkout(
                .init(id: localId, routineId: routine.id, routineName: routine.name, startedAt: nowStr)
            )
        }

        PhoneConnectivityManager.shared.sendWorkoutStarted(routineName: routine.name)
    }

    // MARK: - Log a set
    func logSet(exerciseId: UUID, exerciseName: String, setIndex: Int) async {
        guard let wk = activeWorkout,
              var exSets = sets[exerciseId],
              exSets.indices.contains(setIndex),
              !exSets[setIndex].isDone
        else { return }

        let s = exSets[setIndex]
        exSets[setIndex].isDone = true
        sets[exerciseId] = exSets

        totalSetsLogged += 1
        totalVolume += s.weight * Double(s.reps)

        let exName  = exerciseName
        let nextEx  = activeExercises.first(where: {
            let id = $0.exercises.id
            return id != exerciseId && !(sets[id]?.allSatisfy(\.isDone) ?? true)
        })?.exercises.name ?? ""
        PhoneConnectivityManager.shared.sendExerciseUpdate(
            exerciseName:     exName,
            nextExerciseName: nextEx,
            setIndex:         setIndex + 1,
            targetSets:       sets[exerciseId]?.count ?? 0,
            weight:           s.weight,
            reps:             s.reps
        )

        let insert = WorkoutSetInsert(
            workoutId:    wk.id,
            exerciseId:   exerciseId,
            exerciseName: exerciseName,
            setNumber:    setIndex + 1,
            weightKg:     s.weight,
            reps:         s.reps,
            loggedAt:     isoFmt.string(from: Date())
        )
        do {
            try await sb.postBatch("workout_sets", body: [insert])
        } catch {
            OfflineQueue.shared.enqueue(insert)
        }
    }

    // MARK: - Unlog a set (undo)
    func unlogSet(exerciseId: UUID, setIndex: Int) async {
        guard let wk = activeWorkout,
              var exSets = sets[exerciseId],
              exSets.indices.contains(setIndex),
              exSets[setIndex].isDone
        else { return }

        let s = exSets[setIndex]
        exSets[setIndex].isDone = false
        sets[exerciseId] = exSets
        totalSetsLogged = max(0, totalSetsLogged - 1)
        totalVolume     = max(0, totalVolume - s.weight * Double(s.reps))

        let deleteResource = "workout_sets?workout_id=eq.\(wk.id)" +
            "&exercise_id=eq.\(exerciseId)" +
            "&set_number=eq.\(setIndex + 1)"
        do {
            try await sb.delete(deleteResource)
        } catch {
            OfflineQueue.shared.enqueueDelete(resource: deleteResource)
        }
    }

    // MARK: - Edit a completed set (update weight/reps in-place)
    func editSet(exerciseId: UUID, exerciseName: String, setIndex: Int, newWeight: Double, newReps: Int) async {
        guard let wk = activeWorkout,
              var exSets = sets[exerciseId],
              exSets.indices.contains(setIndex),
              exSets[setIndex].isDone
        else { return }

        let old = exSets[setIndex]
        let oldVolume = old.weight * Double(old.reps)
        let newVolume = newWeight * Double(newReps)

        // Update in-memory state
        exSets[setIndex].weight = newWeight
        exSets[setIndex].reps   = newReps
        sets[exerciseId] = exSets
        totalVolume = max(0, totalVolume - oldVolume) + newVolume

        // Delete old row + insert new row in Supabase
        let deleteResource = "workout_sets?workout_id=eq.\(wk.id)" +
            "&exercise_id=eq.\(exerciseId)" +
            "&set_number=eq.\(setIndex + 1)"
        let insert = WorkoutSetInsert(
            workoutId:    wk.id,
            exerciseId:   exerciseId,
            exerciseName: exerciseName,
            setNumber:    setIndex + 1,
            weightKg:     newWeight,
            reps:         newReps,
            loggedAt:     isoFmt.string(from: Date())
        )
        do {
            try await sb.delete(deleteResource)
            try await sb.postBatch("workout_sets", body: [insert])
        } catch {
            OfflineQueue.shared.enqueueDelete(resource: deleteResource)
            OfflineQueue.shared.enqueue(insert)
        }
    }

    // MARK: - Add extra set
    func addSet(exerciseId: UUID, after index: Int) {
        guard var exSets = sets[exerciseId] else { return }
        let ref = exSets[index]
        exSets.append(SetState(weight: ref.weight, reps: ref.reps))
        sets[exerciseId] = exSets
    }

    /// Add a drop set: reduce weight by ~20-30% (rounded to nearest 2.5kg), keep reps the same.
    func addDropSet(exerciseId: UUID) {
        guard var exSets = sets[exerciseId], let lastDone = exSets.last(where: { $0.isDone }) ?? exSets.last else { return }
        let dropWeight = max(0, (lastDone.weight * 0.75 / 2.5).rounded() * 2.5)
        exSets.append(SetState(weight: dropWeight, reps: lastDone.reps, isDropSet: true))
        sets[exerciseId] = exSets
    }

    func removeSet(exerciseId: UUID, setIndex: Int) {
        guard var exSets = sets[exerciseId],
              exSets.indices.contains(setIndex),
              !exSets[setIndex].isDone
        else { return }
        exSets.remove(at: setIndex)
        sets[exerciseId] = exSets
    }

    // MARK: - Add warm-up sets (prepend before working sets)
    func addWarmUpSets(exerciseId: UUID, warmUpSets: [WarmUpSet]) {
        guard var exSets = sets[exerciseId] else { return }
        let newSets = warmUpSets.map { SetState(weight: $0.weight, reps: $0.reps) }
        exSets.insert(contentsOf: newSets, at: 0)
        sets[exerciseId] = exSets
    }

    // MARK: - Finish workout
    func finishWorkout() async {
        guard let wk = activeWorkout else { return }
        let start = workoutStartTime ?? wk.startedAt
        let end   = Date()
        let finishedAtStr = isoFmt.string(from: end)
        do {
            struct FinishPatch: Encodable { let finished_at: String }
            try await sb.patch(
                "workouts?id=eq.\(wk.id)",
                body: FinishPatch(finished_at: finishedAtStr)
            )
        } catch {
            OfflineQueue.shared.enqueueFinish(workoutId: wk.id, finishedAt: finishedAtStr)
        }
        progressionSuggestions = computeProgressionSuggestions()

        Task { await checkOverloadSuggestions() }

        lastFinishedSummary = buildSummary(
            routineName: wk.routineName,
            date: start,
            start: start,
            end: end
        )

        writeWidgetData()

        await OfflineQueue.shared.flush()

        let workoutId = wk.id
        let capturedStart = start
        let capturedEnd = end

        // Capture sets for AI analysis before clearing state
        let capturedSets = buildWorkoutSets(workoutId: workoutId)
        let capturedRoutineName = wk.routineName

        PhoneHealthKitManager.shared.stopLiveMonitoring()
        PhoneConnectivityManager.shared.sendWorkoutFinished()
        activeWorkout    = nil
        activeExercises  = []
        sets             = [:]
        workoutStartTime = nil
        pendingRoutine   = nil
        liveHeartRate    = 0
        liveCalories     = 0

        todayRoutineCompleted = true

        // Show AI analysis screen if we have sets
        if !capturedSets.isEmpty, wk.routineId != nil {
            analysisWorkoutId = workoutId
            analysisRoutineName = capturedRoutineName
            analysisSets = capturedSets
            activeScreen = .home
            showPostWorkoutAnalysis = true
        } else {
            activeScreen = .home
        }

        Task {
            let stats = await loadWeekData()
            syncWeeklyCountToWidget(weekStats: stats)
        }

        Task {
            struct StatsPatch: Encodable {
                let calories: Int?
                let avgHeartRate: Int?
                enum CodingKeys: String, CodingKey {
                    case calories
                    case avgHeartRate = "avg_heart_rate"
                }
            }
            for delay in [30, 60, 120] {
                try? await Task.sleep(for: .seconds(delay))
                let (calories, avgHeartRate) = await PhoneHealthKitManager.shared.fetchStats(from: capturedStart, to: capturedEnd)
                guard calories != nil || avgHeartRate != nil else { continue }
                do {
                    try await sb.patch(
                        "workouts?id=eq.\(workoutId)",
                        body: StatsPatch(calories: calories, avgHeartRate: avgHeartRate)
                    )
                } catch {
                    print("[Supabase] HK stats patch failed: \(error.localizedDescription)")
                }
                return
            }
        }
    }

    // MARK: - Widget data

    func syncWeeklyCountToWidget(weekStats: [WorkoutWeekStats]) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        let cal = Calendar.current
        let trainingWeekdays: Set<Int> = [2, 3, 4, 5, 6, 7]
        var trainedWeekdays = Set<Int>()
        for ws in weekStats {
            let wd = cal.component(.weekday, from: ws.workout.startedAt)
            if trainingWeekdays.contains(wd) {
                trainedWeekdays.insert(wd)
            }
        }
        defaults.set(trainedWeekdays.count, forKey: "widgetTrainingDaysCompleted")

        let todayWorkouts = weekStats.filter { cal.isDateInToday($0.workout.startedAt) }
        let workoutDoneToday = !todayWorkouts.isEmpty
        defaults.set(workoutDoneToday, forKey: "widgetWorkoutDone")

        if let todayWS = todayWorkouts.last {
            let w = todayWS.workout
            let secs = Int((w.finishedAt ?? Date()).timeIntervalSince(w.startedAt))
            let mins = secs / 60
            let durStr = mins < 60 ? "\(mins)m" : "\(mins / 60)h \(mins % 60)m"
            let vol = todayWS.volume
            let volStr = vol >= 1000 ? String(format: "%.1fk", vol / 1000) : "\(Int(vol))kg"
            defaults.set(durStr, forKey: "widgetTodayDuration")
            defaults.set(volStr, forKey: "widgetTodayVolume")
        } else {
            defaults.removeObject(forKey: "widgetTodayDuration")
            defaults.removeObject(forKey: "widgetTodayVolume")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func writeWidgetData() {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        let start = workoutStartTime ?? activeWorkout?.startedAt ?? Date()
        let duration = Int(Date().timeIntervalSince(start))
        defaults.set(duration, forKey: "lastWorkoutDuration")
        defaults.set(totalVolume, forKey: "lastWorkoutVolume")
        defaults.set(Date().timeIntervalSince1970, forKey: "lastWorkoutDate")

        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Build workout summary (from active state, before clearing)
    private func buildSummary(routineName: String, date: Date, start: Date, end: Date) -> WorkoutSummaryData {
        let durationMins = Int(end.timeIntervalSince(start) / 60)
        var exerciseSummaries: [WorkoutSummaryData.ExerciseSummary] = []
        var totalSetsCount = 0

        for re in activeExercises {
            guard let exSets = sets[re.exercises.id] else { continue }
            let doneSets = exSets.filter(\.isDone)
            guard !doneSets.isEmpty else { continue }
            totalSetsCount += doneSets.count

            let best = doneSets.max(by: { $0.weight * Double($0.reps) < $1.weight * Double($1.reps) })!
            exerciseSummaries.append(.init(
                name: re.exercises.name,
                bestWeight: best.weight,
                bestReps: best.reps,
                setCount: doneSets.count
            ))
        }

        return WorkoutSummaryData(
            routineName: routineName,
            date: date,
            durationMinutes: durationMins,
            totalVolume: totalVolume,
            totalSets: totalSetsCount,
            prsHit: 0,
            exercises: exerciseSummaries
        )
    }

    // MARK: - Build WorkoutSet array from active state (for AI analysis)
    private func buildWorkoutSets(workoutId: UUID) -> [WorkoutSet] {
        var result: [WorkoutSet] = []
        for re in activeExercises {
            guard let exSets = sets[re.exercises.id] else { continue }
            for (i, s) in exSets.enumerated() where s.isDone {
                result.append(WorkoutSet(
                    id: UUID(),
                    workoutId: workoutId,
                    exerciseId: re.exercises.id,
                    exerciseName: re.exercises.name,
                    setNumber: i + 1,
                    weightKg: s.weight,
                    reps: s.reps,
                    loggedAt: Date()
                ))
            }
        }
        return result
    }

    // MARK: - Cancel prepared workout (never started, no DB record)
    func cancelPreparedWorkout() {
        activeExercises  = []
        sets             = [:]
        lastSets         = [:]
        pendingRoutine   = nil
        activeScreen     = .home
    }

    // MARK: - Discard workout (0 sets logged)
    func discardWorkout() async {
        guard let wk = activeWorkout else {
            cancelPreparedWorkout()
            return
        }
        PhoneConnectivityManager.shared.sendWorkoutDiscarded()
        do {
            try await sb.delete("workouts?id=eq.\(wk.id)")
        } catch {
            errorMessage = "Failed to discard workout: \(error.localizedDescription)"
        }
        OfflineQueue.shared.dequeueWorkout(id: wk.id)
        PhoneHealthKitManager.shared.stopLiveMonitoring()
        activeWorkout    = nil
        activeExercises  = []
        sets             = [:]
        workoutStartTime = nil
        pendingRoutine   = nil
        liveHeartRate    = 0
        liveCalories     = 0
        activeScreen     = .home
    }

    // MARK: - Start cardio session
    func startCardio(type: CardioType) async {
        let now = Date()
        let nowStr = isoFmt.string(from: now)
        let insert = WorkoutInsert(routineId: nil, routineName: type.name, startedAt: nowStr)

        var wk: Workout
        do {
            wk = try await sb.post("workouts", body: insert, returning: Workout.self)
        } catch {
            let offlineId = UUID()
            wk = Workout(id: offlineId, routineId: nil, routineName: type.name,
                         startedAt: now, finishedAt: nil, calories: nil, avgHeartRate: nil)
            OfflineQueue.shared.enqueueWorkout(
                OfflineQueue.PendingWorkout(id: offlineId, routineId: nil, routineName: type.name, startedAt: nowStr)
            )
        }
        activeWorkout    = wk
        workoutStartTime = now
        liveHeartRate    = 0
        liveCalories     = 0
        PhoneHealthKitManager.shared.startLiveMonitoring(from: now)
        await PhoneHealthKitManager.shared.startWatchApp(activityType: type.hkActivityType, isIndoor: type.isIndoor)
        PhoneConnectivityManager.shared.sendCardioStarted(
            name:            type.name,
            activityTypeRaw: type.hkActivityType.rawValue,
            isIndoor:        type.isIndoor
        )
        activeScreen = .cardio
    }

    // MARK: - Finish cardio session
    func finishCardio() async {
        guard let wk = activeWorkout else { return }
        let start = workoutStartTime ?? wk.startedAt
        let end   = Date()
        let finishedAtStr = isoFmt.string(from: end)
        do {
            struct FinishPatch: Encodable { let finished_at: String }
            try await sb.patch(
                "workouts?id=eq.\(wk.id)",
                body: FinishPatch(finished_at: finishedAtStr)
            )
        } catch {
            OfflineQueue.shared.enqueueFinish(workoutId: wk.id, finishedAt: finishedAtStr)
        }
        PhoneHealthKitManager.shared.stopLiveMonitoring()
        PhoneConnectivityManager.shared.sendWorkoutFinished()
        activeWorkout    = nil
        workoutStartTime = nil
        liveHeartRate    = 0
        liveCalories     = 0
        activeScreen     = .home

        #if !SONYA
        Task { await loadCardioThisWeek() }
        #endif

        let workoutId = wk.id
        Task {
            struct StatsPatch: Encodable {
                let calories: Int?
                let avgHeartRate: Int?
                enum CodingKeys: String, CodingKey {
                    case calories
                    case avgHeartRate = "avg_heart_rate"
                }
            }
            for delay in [10, 30] {
                try? await Task.sleep(for: .seconds(delay))
                let (calories, avgHeartRate) = await PhoneHealthKitManager.shared.fetchStats(from: start, to: end)
                guard calories != nil || avgHeartRate != nil else { continue }
                do {
                    try await sb.patch(
                        "workouts?id=eq.\(workoutId)",
                        body: StatsPatch(calories: calories, avgHeartRate: avgHeartRate)
                    )
                } catch {
                    print("[Supabase] cardio HK stats patch failed: \(error.localizedDescription)")
                }
                return
            }
        }
    }

    // MARK: - Delete workout from history
    func deleteWorkout(id: UUID) async {
        do {
            try await sb.delete("workout_sets?workout_id=eq.\(id)")
            try await sb.delete("workouts?id=eq.\(id)")
            history.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Load a single workout by id (detail view)
    func loadWorkout(id: UUID) async -> Workout? {
        do {
            let results: [Workout] = try await sb.get(
                "workouts?select=id,routine_id,routine_name,started_at,finished_at,calories,avg_heart_rate" +
                "&id=eq.\(id)"
            )
            return results.first
        } catch {
            errorMessage = "Failed to load workout: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: - Load sets for a single workout (detail view)
    func loadSets(workoutId: UUID) async -> [WorkoutSet] {
        do {
            return try await sb.get(
                "workout_sets?select=*&workout_id=eq.\(workoutId)" +
                "&order=exercise_name.asc,set_number.asc"
            )
        } catch {
            errorMessage = "Failed to load sets: \(error.localizedDescription)"
            return []
        }
    }

    // MARK: - Load current week's workouts with sets + volume
    func loadWeekData() async -> [WorkoutWeekStats] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: today)
        let daysToMon = weekday == 1 ? -6 : 2 - weekday
        guard let monday  = cal.date(byAdding: .day, value: daysToMon,     to: today),
              let nextMon = cal.date(byAdding: .day, value: daysToMon + 7, to: today) else { return [] }

        let start = isoFmt.string(from: monday)
        let end   = isoFmt.string(from: nextMon)

        guard let workouts: [Workout] = await sb.tryGet(
            "workouts?select=id,routine_id,routine_name,started_at,finished_at,calories,avg_heart_rate" +
            "&finished_at=not.is.null" +
            "&started_at=gte.\(start)&started_at=lt.\(end)" +
            "&order=started_at.asc"
        ), !workouts.isEmpty else { return [] }

        let ids = workouts.map { $0.id.uuidString }.joined(separator: ",")
        struct SetRow: Decodable {
            let workoutId: UUID
            let weightKg:  Double
            let reps:      Int
            let exercises: ExInfo?
            struct ExInfo: Decodable {
                let muscleGroup: String?
                enum CodingKeys: String, CodingKey { case muscleGroup = "muscle_group" }
            }
            enum CodingKeys: String, CodingKey {
                case workoutId = "workout_id"
                case weightKg  = "weight_kg"
                case reps
                case exercises
            }
        }
        let rows: [SetRow] = await sb.tryGet(
            "workout_sets?select=workout_id,weight_kg,reps,exercises(muscle_group)" +
            "&workout_id=in.(\(ids))"
        ) ?? []

        struct Agg {
            var sets: Int = 0
            var vol: Double = 0
            var muscleCounts: [String: Int] = [:]
        }
        var aggMap: [UUID: Agg] = [:]
        for r in rows {
            var a = aggMap[r.workoutId] ?? Agg()
            a.sets += 1
            a.vol  += r.weightKg * Double(r.reps)
            if let mg = r.exercises?.muscleGroup, !mg.isEmpty {
                a.muscleCounts[mg, default: 0] += 1
            }
            aggMap[r.workoutId] = a
        }

        return workouts.map { wk in
            let a = aggMap[wk.id] ?? Agg()
            let sorted = a.muscleCounts.sorted { $0.value > $1.value }
            let total  = sorted.reduce(0) { $0 + $1.value }
            let split  = sorted.map { (
                muscle: $0.key,
                sets:   $0.value,
                pct:    Double($0.value) / Double(max(total, 1)) * 100
            )}
            return WorkoutWeekStats(workout: wk, setsCount: a.sets,
                                    volume: a.vol, muscleSplit: split)
        }
    }

    // MARK: - Routine Editor methods

    func loadRoutineExercises(routineId: UUID) async {
        do {
            let exs: [RoutineExercise] = try await sb.get(
                "routine_exercises?select=*,exercises(id,name,muscle_group,equipment)" +
                "&routine_id=eq.\(routineId)&order=position"
            )
            editingExercises = exs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateRoutineExercise(id: UUID, update: RoutineExerciseUpdate) async {
        do {
            try await sb.patch("routine_exercises?id=eq.\(id)", body: update)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRoutineExercise(id: UUID) async {
        do {
            try await sb.delete("routine_exercises?id=eq.\(id)")
            editingExercises.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addRoutineExercise(routineId: UUID, exerciseId: UUID) async {
        let nextPos = (editingExercises.map(\.position).max() ?? 0) + 1
        #if SONYA
        let defaultRest = 60
        #else
        let defaultRest = 90
        #endif
        let insert = RoutineExerciseInsert(
            routineId: routineId,
            exerciseId: exerciseId,
            position: nextPos,
            targetSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 12,
            restSeconds: defaultRest,
            supersetGroup: nil,
            isWarmup: false,
            notes: nil
        )
        do {
            let added: RoutineExercise = try await sb.post(
                "routine_exercises?select=*,exercises(id,name,muscle_group,equipment)",
                body: insert, returning: RoutineExercise.self
            )
            editingExercises.append(added)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reorderRoutineExercises(routineId: UUID) async {
        var failed = false
        for (i, re) in editingExercises.enumerated() {
            let newPos = i + 1
            if re.position != newPos {
                let update = RoutineExerciseUpdate(position: newPos)
                do {
                    try await sb.patch("routine_exercises?id=eq.\(re.id)", body: update)
                } catch {
                    failed = true
                }
            }
        }
        if failed { errorMessage = "Some exercises failed to reorder" }
        await loadRoutineExercises(routineId: routineId)
    }

    func loadAllExercises() async {
        guard allExercises.isEmpty else { return }
        do {
            let exs: [Exercise] = try await sb.get("exercises?select=*&order=name")
            allExercises = exs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Routine CRUD

    func createRoutine(name: String) async -> Routine? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Routine name cannot be empty."; return nil }
        guard trimmed.count <= 50 else { errorMessage = "Routine name must be 50 characters or fewer."; return nil }
        guard !routines.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "A routine named \"\(trimmed)\" already exists."; return nil
        }
        let insert = RoutineInsert(name: trimmed, dayLabel: nil)
        do {
            let routine: Routine = try await sb.post("routines", body: insert, returning: Routine.self)
            routines.append(routine)
            return routine
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func duplicateRoutine(_ routine: Routine) async {
        let insert = RoutineInsert(name: "\(routine.name) (Copy)", dayLabel: routine.dayLabel)
        do {
            let newRoutine: Routine = try await sb.post("routines", body: insert, returning: Routine.self)
            let exs: [RoutineExercise] = try await sb.get(
                "routine_exercises?select=*,exercises(id,name,muscle_group,equipment)" +
                "&routine_id=eq.\(routine.id)&order=position"
            )
            for re in exs {
                let reInsert = RoutineExerciseInsert(
                    routineId: newRoutine.id,
                    exerciseId: re.exercises.id,
                    position: re.position,
                    targetSets: re.targetSets,
                    targetRepsMin: re.targetRepsMin,
                    targetRepsMax: re.targetRepsMax,
                    restSeconds: re.restSeconds,
                    supersetGroup: re.supersetGroup,
                    isWarmup: re.isWarmup,
                    notes: re.notes
                )
                _ = try await sb.post("routine_exercises", body: reInsert, returning: RoutineExercise.self)
            }
            routines.append(newRoutine)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteRoutine(id: UUID) async {
        do {
            try await sb.delete("routine_exercises?routine_id=eq.\(id)")
            try await sb.delete("routines?id=eq.\(id)")
            routines.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func renameRoutine(id: UUID, name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Routine name cannot be empty."; return }
        guard trimmed.count <= 50 else { errorMessage = "Routine name must be 50 characters or fewer."; return }
        guard !routines.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "A routine named \"\(trimmed)\" already exists."; return
        }
        let update = RoutineUpdate(name: trimmed)
        do {
            try await sb.patch("routines?id=eq.\(id)", body: update)
            if let idx = routines.firstIndex(where: { $0.id == id }) {
                routines[idx] = Routine(id: id, name: trimmed, dayLabel: routines[idx].dayLabel)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Exercise CRUD

    func createExercise(name: String, muscleGroup: String?, equipment: String?) async -> Exercise? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { errorMessage = "Exercise name cannot be empty."; return nil }
        guard trimmed.count <= 80 else { errorMessage = "Exercise name must be 80 characters or fewer."; return nil }
        guard !allExercises.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            errorMessage = "An exercise named \"\(trimmed)\" already exists."; return nil
        }
        let insert = ExerciseInsert(name: trimmed, muscleGroup: muscleGroup, equipment: equipment)
        do {
            let ex: Exercise = try await sb.post("exercises", body: insert, returning: Exercise.self)
            allExercises.append(ex)
            allExercises.sort { $0.name < $1.name }
            return ex
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func updateExercise(id: UUID, name: String?, muscleGroup: String?, equipment: String?) async {
        if let name = name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { errorMessage = "Exercise name cannot be empty."; return }
            guard trimmed.count <= 80 else { errorMessage = "Exercise name must be 80 characters or fewer."; return }
            guard !allExercises.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
                errorMessage = "An exercise named \"\(trimmed)\" already exists."; return
            }
        }
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let update = ExerciseUpdate(name: trimmedName, muscleGroup: muscleGroup, equipment: equipment)
        do {
            try await sb.patch("exercises?id=eq.\(id)", body: update)
            if let idx = allExercises.firstIndex(where: { $0.id == id }) {
                allExercises[idx] = Exercise(
                    id: id,
                    name: trimmedName ?? allExercises[idx].name,
                    muscleGroup: muscleGroup ?? allExercises[idx].muscleGroup,
                    equipment: equipment ?? allExercises[idx].equipment
                )
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteExercise(id: UUID) async {
        do {
            try await sb.delete("exercises?id=eq.\(id)")
            allExercises.removeAll { $0.id == id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadAllExercises() async {
        do {
            let exs: [Exercise] = try await sb.get("exercises?select=*&order=name")
            allExercises = exs
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Weekly stats model
struct WorkoutWeekStats {
    let workout: Workout
    let setsCount: Int
    let volume: Double
    let muscleSplit: [(muscle: String, sets: Int, pct: Double)]
}

// MARK: - Muscle recovery model
struct MuscleRecovery {
    let muscle: String
    let daysSince: Int
    var recoveryColor: String {
        switch daysSince {
        case 0, 1: return "ef4444"
        case 2:    return "f59e0b"
        default:   return "22c55e"
        }
    }
}

enum AppScreen {
    case home, choose, workout, cardio, history, detail(UUID), prs, week, body, progress(String), editRoutine(UUID), exercises, scheduleEditor, photos, photoCompare, muscleBalance, overloadTracker, prTimeline, durationAnalytics, exerciseSubstitutions, muscleVolume, bodyComposition, reports
}
