import Foundation
import SwiftUI
import os.log

// MARK: - Analytics, PRs, Streaks, Recovery, Progression & Overload

extension WorkoutStore {

    // MARK: - Last week's total volume

    func loadLastWeekVolume() async -> Double {
        let cal      = Calendar.current
        let today    = cal.startOfDay(for: Date())
        let weekday  = cal.component(.weekday, from: today)
        let daysToMon = weekday == 1 ? -6 : 2 - weekday
        guard let thisMon  = cal.date(byAdding: .day, value: daysToMon,     to: today),
              let lastMon  = cal.date(byAdding: .day, value: daysToMon - 7, to: today) else { return 0 }

        struct VolumeRow: Decodable {
            let weightKg: Double; let reps: Int
            enum CodingKeys: String, CodingKey { case weightKg = "weight_kg"; case reps }
        }
        guard let rows: [VolumeRow] = await sb.tryGet(
            "workout_sets?select=weight_kg,reps" +
            "&logged_at=gte.\(isoFmt.string(from: lastMon))" +
            "&logged_at=lt.\(isoFmt.string(from: thisMon))"
        ) else { return 0 }
        return rows.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    }

    // MARK: - Training streak (rest days neutral)

    func computeStreak() async -> Int {
        struct StreakRow: Decodable {
            let loggedAt: Date
            enum CodingKeys: String, CodingKey { case loggedAt = "logged_at" }
        }
        guard let rows: [StreakRow] = await sb.tryGet(
            "workout_sets?select=logged_at&order=logged_at.desc&limit=2000"
        ) else { return 0 }

        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        var uniqueDays = Set<Date>()
        for row in rows { uniqueDays.insert(cal.startOfDay(for: row.loggedAt)) }

        guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return 0 }
        let todayActive   = uniqueDays.contains(today)   || restDays.contains(today)
        let yesterdayActive = uniqueDays.contains(yesterday) || restDays.contains(yesterday)
        guard todayActive || yesterdayActive else { return 0 }

        var streak   = 0
        var checkDay = todayActive ? today : yesterday
        for _ in 0..<365 {
            if uniqueDays.contains(checkDay) {
                streak  += 1
            } else if restDays.contains(checkDay) {
                // Rest day: neutral — skip, don't break
            } else {
                break
            }
            guard let prevDay = cal.date(byAdding: .day, value: -1, to: checkDay) else { break }
            checkDay = prevDay
        }
        return streak
    }

    // MARK: - Muscle recovery (last 14 days)

    func loadRecovery() async -> [MuscleRecovery] {
        struct RecoveryRow: Decodable {
            let loggedAt:  Date
            let exercises: ExInfo?
            struct ExInfo: Decodable {
                let muscleGroup: String?
                enum CodingKeys: String, CodingKey { case muscleGroup = "muscle_group" }
            }
            enum CodingKeys: String, CodingKey {
                case loggedAt  = "logged_at"
                case exercises
            }
        }
        let cutoff = isoFmt.string(from: Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date())
        guard let rows: [RecoveryRow] = await sb.tryGet(
            "workout_sets?select=logged_at,exercises(muscle_group)" +
            "&logged_at=gte.\(cutoff)&order=logged_at.desc&limit=500"
        ) else { return [] }

        let cal   = Calendar.current
        let today = cal.startOfDay(for: Date())
        var seen  = Set<String>()
        var result: [MuscleRecovery] = []
        for row in rows {
            guard let muscle = row.exercises?.muscleGroup,
                  !muscle.isEmpty, muscle != "Other",
                  seen.insert(muscle).inserted
            else { continue }
            let days = cal.dateComponents([.day], from: cal.startOfDay(for: row.loggedAt), to: today).day ?? 0
            result.append(MuscleRecovery(muscle: muscle, daysSince: days))
        }
        return result.sorted { $0.muscle < $1.muscle }
    }

    // MARK: - Workout dates for heatmap

    func loadWorkoutDates(days: Int) async -> Set<Date> {
        struct DateRow: Decodable {
            let startedAt: Date
            enum CodingKeys: String, CodingKey { case startedAt = "started_at" }
        }
        let cutoff = isoFmt.string(from: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        guard let rows: [DateRow] = await sb.tryGet(
            "workouts?select=started_at&finished_at=not.is.null" +
            "&started_at=gte.\(cutoff)&order=started_at.asc"
        ) else { return [] }
        let cal = Calendar.current
        return Set(rows.map { cal.startOfDay(for: $0.startedAt) })
    }

    // MARK: - Top exercises for correlation picker

    func loadTopExercises(limit: Int) async -> [(label: String, fullName: String)] {
        struct SetName: Decodable {
            let exerciseName: String
            let weightKg: Double
            enum CodingKeys: String, CodingKey {
                case exerciseName = "exercise_name"
                case weightKg = "weight_kg"
            }
        }
        let cutoff = isoFmt.string(from: Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date())
        guard let rows: [SetName] = await sb.tryGet(
            "workout_sets?select=exercise_name,weight_kg" +
            "&logged_at=gte.\(cutoff)&weight_kg=gt.0&order=logged_at.desc&limit=2000"
        ) else { return [] }

        var counts: [String: Int] = [:]
        var maxWeight: [String: Double] = [:]
        for row in rows {
            counts[row.exerciseName, default: 0] += 1
            maxWeight[row.exerciseName] = max(maxWeight[row.exerciseName] ?? 0, row.weightKg)
        }

        let sorted = counts.keys.sorted { a, b in
            let scoreA = Double(counts[a] ?? 0) * (maxWeight[a] ?? 0)
            let scoreB = Double(counts[b] ?? 0) * (maxWeight[b] ?? 0)
            return scoreA > scoreB
        }

        return Array(sorted.prefix(limit)).map { name in
            let label = shortLabel(for: name)
            return (label: label, fullName: name)
        }
    }

    private func shortLabel(for name: String) -> String {
        let n = name.lowercased()
        if n.contains("incline") && n.contains("bench")  { return "Incline Bench" }
        if n.contains("overhead press") || n.contains("ohp") { return "OHP" }
        if n.contains("romanian") || n.contains("rdl")   { return "RDL" }
        if n.contains("hack squat")                       { return "Hack Squat" }
        if n.contains("hip thrust")                       { return "Hip Thrust" }
        if n.contains("t-bar")                            { return "T-Bar Row" }
        if n.contains("bench press") && !n.contains("incline") { return "Bench Press" }
        if n.contains("lat pulldown")                     { return "Lat Pulldown" }
        if n.contains("cable row")                        { return "Cable Row" }
        if n.contains("chest press")                      { return "Chest Press" }
        let words = name.split(separator: " ").prefix(2).joined(separator: " ")
        return words
    }

    // MARK: - e1RM history for a named exercise

    func loadExerciseE1rm(name: String, days: Int) async -> [(date: Date, e1rm: Double)] {
        struct SetRow: Decodable {
            let workoutId: UUID
            let weightKg:  Double
            let reps:      Int
            let loggedAt:  Date
            enum CodingKeys: String, CodingKey {
                case workoutId = "workout_id"
                case weightKg  = "weight_kg"
                case reps
                case loggedAt  = "logged_at"
            }
        }
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return [] }
        let cutoff = isoFmt.string(from: Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date())
        guard let rows: [SetRow] = await sb.tryGet(
            "workout_sets?select=workout_id,weight_kg,reps,logged_at" +
            "&exercise_name=eq.\(encoded)" +
            "&logged_at=gte.\(cutoff)&order=logged_at.asc"
        ) else { return [] }

        var bestByWorkout: [UUID: (e1rm: Double, date: Date)] = [:]
        for row in rows {
            let e1rm = row.weightKg * (1 + Double(row.reps) / 30.0)
            if let existing = bestByWorkout[row.workoutId] {
                if e1rm > existing.e1rm { bestByWorkout[row.workoutId] = (e1rm, row.loggedAt) }
            } else {
                bestByWorkout[row.workoutId] = (e1rm, row.loggedAt)
            }
        }
        return bestByWorkout.values
            .map { (date: $0.date, e1rm: $0.e1rm) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Detect most recent all-time PR (set within last 14 days)

    func detectRecentPR() async -> (exercise: String, weight: Double, reps: Int, date: Date)? {
        struct SetRow: Decodable {
            let exerciseName: String; let weightKg: Double; let reps: Int; let loggedAt: Date
            enum CodingKeys: String, CodingKey {
                case exerciseName = "exercise_name"; case weightKg = "weight_kg"
                case reps; case loggedAt = "logged_at"
            }
        }
        let cutoffPR = isoFmt.string(from: Calendar.current.date(byAdding: .day, value: -365, to: Date()) ?? Date())
        guard let rows: [SetRow] = await sb.tryGet(
            "workout_sets?select=exercise_name,weight_kg,reps,logged_at" +
            "&logged_at=gte.\(cutoffPR)" +
            "&order=exercise_name.asc,weight_kg.desc,reps.desc&limit=5000"
        ) else { return nil }

        let cutoff = Calendar.current.date(byAdding: .day, value: -14, to: Date()) ?? Date()
        var seen   = Set<String>()
        var recent: [(exercise: String, weight: Double, reps: Int, date: Date)] = []
        for row in rows {
            guard seen.insert(row.exerciseName).inserted else { continue }
            if row.loggedAt >= cutoff {
                recent.append((row.exerciseName, row.weightKg, row.reps, row.loggedAt))
            }
        }
        return recent.max(by: { $0.date < $1.date })
    }

    // MARK: - Progression suggestions (computed after finishing a workout)

    func computeProgressionSuggestions() -> [ProgressionSuggestion] {
        var suggestions: [ProgressionSuggestion] = []
        for re in activeExercises where !re.isWarmup {
            guard let maxReps = re.targetRepsMax, maxReps > 0,
                  let exSets = sets[re.exercises.id],
                  !exSets.isEmpty
            else { continue }

            let doneSets = exSets.filter(\.isDone)
            guard doneSets.count >= re.targetSets else { continue }

            let weight = doneSets[0].weight
            let allHitMax = doneSets.allSatisfy { $0.reps >= maxReps && $0.weight == weight }
            guard allHitMax, weight > 0 else { continue }

            suggestions.append(ProgressionSuggestion(
                exerciseName: re.exercises.name,
                currentWeight: weight,
                repsHit: doneSets.map(\.reps).min() ?? maxReps,
                targetRepsMax: maxReps
            ))
        }
        return suggestions
    }

    // MARK: - Overload detection (2+ consecutive sessions hitting target reps)

    private static let compoundKeywords = [
        "bench", "squat", "press", "ohp", "overhead", "rdl", "romanian", "deadlift",
        "row", "hip thrust", "hack", "t-bar", "incline bench"
    ]

    private func isCompound(_ name: String) -> Bool {
        let lower = name.lowercased()
        return Self.compoundKeywords.contains { lower.contains($0) }
    }

    func checkOverloadSuggestions() async {
        struct RERow: Decodable {
            let exercises: ExRef
            let targetRepsMax: Int?
            struct ExRef: Decodable {
                let id: UUID
                let name: String
            }
            enum CodingKeys: String, CodingKey {
                case exercises
                case targetRepsMax = "target_reps_max"
            }
        }
        guard let reRows: [RERow] = await sb.tryGet(
            "routine_exercises?select=target_reps_max,exercises(id,name)&is_warmup=eq.false"
        ) else { return }

        var targetRepsMap: [UUID: Int] = [:]
        var exerciseNames: [UUID: String] = [:]
        for re in reRows {
            if let max = re.targetRepsMax, max > 0 {
                targetRepsMap[re.exercises.id] = max
                exerciseNames[re.exercises.id] = re.exercises.name
            }
        }

        struct HistorySetRow: Decodable {
            let workoutId: UUID
            let exerciseId: UUID
            let exerciseName: String
            let weightKg: Double
            let reps: Int
            let loggedAt: Date
            enum CodingKeys: String, CodingKey {
                case workoutId    = "workout_id"
                case exerciseId   = "exercise_id"
                case exerciseName = "exercise_name"
                case weightKg     = "weight_kg"
                case reps
                case loggedAt     = "logged_at"
            }
        }
        let cutoff = isoFmt.string(from: Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date())
        guard let setRows: [HistorySetRow] = await sb.tryGet(
            "workout_sets?select=workout_id,exercise_id,exercise_name,weight_kg,reps,logged_at" +
            "&logged_at=gte.\(cutoff)&weight_kg=gt.0&order=logged_at.desc&limit=5000"
        ) else { return }

        let byExercise = Dictionary(grouping: setRows, by: \.exerciseId)
        let dismissed = dismissedOverloadIDs
        var suggestions: [OverloadSuggestion] = []

        for (exerciseId, allSets) in byExercise {
            guard let targetMax = targetRepsMap[exerciseId], targetMax > 0 else { continue }
            let name = exerciseNames[exerciseId] ?? allSets.first?.exerciseName ?? "Unknown"

            let byWorkout = Dictionary(grouping: allSets, by: \.workoutId)
            let sessions = byWorkout.values
                .map { sets -> (weight: Double, allHitTarget: Bool, date: Date) in
                    let maxDate = sets.map(\.loggedAt).max() ?? Date.distantPast
                    let primaryWeight = Dictionary(grouping: sets, by: \.weightKg)
                        .max(by: { $0.value.count < $1.value.count })?.key ?? sets[0].weightKg
                    let relevantSets = sets.filter { $0.weightKg == primaryWeight }
                    let allHit = relevantSets.allSatisfy { $0.reps >= targetMax }
                    return (weight: primaryWeight, allHitTarget: allHit, date: maxDate)
                }
                .sorted { $0.date > $1.date }

            guard sessions.count >= 2 else { continue }

            let currentWeight = sessions[0].weight
            var consecutive = 0
            for session in sessions {
                if session.weight == currentWeight && session.allHitTarget {
                    consecutive += 1
                } else {
                    break
                }
            }

            guard consecutive >= 2, currentWeight > 0 else { continue }

            let bump = isCompound(name) ? 2.5 : 1.25
            let suggested = currentWeight + bump
            let suggestionId = "\(name)_\(currentWeight)"

            guard !dismissed.contains(suggestionId) else { continue }

            suggestions.append(OverloadSuggestion(
                id: suggestionId,
                exerciseName: name,
                currentWeight: currentWeight,
                suggestedWeight: suggested,
                consecutiveSessions: consecutive
            ))
        }

        overloadSuggestions = suggestions.sorted { $0.exerciseName < $1.exerciseName }
    }

    // MARK: - Muscle split for detail view

    func loadMuscleSplit(workoutId: UUID) async -> [(muscle: String, sets: Int, pct: Double)] {
        struct SetMuscleRow: Decodable {
            let exercises: ExMuscle?
            struct ExMuscle: Decodable {
                let muscleGroup: String?
                enum CodingKeys: String, CodingKey { case muscleGroup = "muscle_group" }
            }
        }
        let rows: [SetMuscleRow]
        do {
            rows = try await sb.get(
                "workout_sets?select=exercises(muscle_group)&workout_id=eq.\(workoutId)"
            )
        } catch {
            errorMessage = "Failed to load muscle split: \(error.localizedDescription)"
            return []
        }

        var counts: [String: Int] = [:]
        for row in rows {
            let muscle = row.exercises?.muscleGroup ?? "Other"
            if !muscle.isEmpty { counts[muscle, default: 0] += 1 }
        }
        let total = counts.values.reduce(0, +)
        guard total > 0 else { return [] }
        return counts
            .map { (muscle: $0.key, sets: $0.value, pct: Double($0.value) / Double(total) * 100) }
            .sorted { $0.sets > $1.sets }
    }

    // MARK: - Build summary from loaded sets (for detail view / history)

    func buildSummaryFromSets(workout: Workout, sets: [WorkoutSet]) -> WorkoutSummaryData {
        let durationMins: Int
        if let fin = workout.finishedAt {
            durationMins = Int(fin.timeIntervalSince(workout.startedAt) / 60)
        } else {
            durationMins = 0
        }

        let grouped = Dictionary(grouping: sets, by: \.exerciseName)
        let orderedNames = grouped.keys.sorted {
            let t0 = grouped[$0]?.map(\.loggedAt).min() ?? .distantPast
            let t1 = grouped[$1]?.map(\.loggedAt).min() ?? .distantPast
            return t0 < t1
        }

        var exerciseSummaries: [WorkoutSummaryData.ExerciseSummary] = []
        for name in orderedNames {
            let exSets = grouped[name]!
            let best = exSets.max(by: { $0.weightKg * Double($0.reps) < $1.weightKg * Double($1.reps) })!
            exerciseSummaries.append(.init(
                name: name,
                bestWeight: best.weightKg,
                bestReps: best.reps,
                setCount: exSets.count
            ))
        }

        let totalVol = sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }

        return WorkoutSummaryData(
            routineName: workout.routineName,
            date: workout.startedAt,
            durationMinutes: durationMins,
            totalVolume: totalVol,
            totalSets: sets.count,
            prsHit: 0,
            exercises: exerciseSummaries
        )
    }
}
