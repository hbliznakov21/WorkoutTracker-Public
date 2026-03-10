import Foundation

/// Queues failed Supabase set inserts, workout creates, and workout finishes locally, retries when network returns.
@MainActor
final class OfflineQueue {
    static let shared = OfflineQueue()

    private let key = "offline_pending_sets"
    private let finishKey = "offline_pending_finishes"
    private let workoutKey = "offline_pending_workouts"
    private let deleteKey = "offline_pending_deletes"
    private let retryCountKey = "offline_retry_counts"
    private let sb = SupabaseClient.shared
    private var isFlushing = false
    static let maxRetries = 5

    // MARK: - Pending models

    struct PendingFinish: Codable {
        let workoutId: UUID
        let finishedAt: String
    }

    struct PendingWorkout: Codable {
        let id: UUID
        let routineId: UUID?
        let routineName: String
        let startedAt: String
    }

    // MARK: - Retry tracking
    private func retryCounts() -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: retryCountKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Int].self, from: data)) ?? [:]
    }

    private func saveRetryCounts(_ counts: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counts) else {
            print("[OfflineQueue] Failed to encode retry counts")
            return
        }
        UserDefaults.standard.set(data, forKey: retryCountKey)
    }

    private func incrementRetry(for key: String) -> Bool {
        var counts = retryCounts()
        let current = (counts[key] ?? 0) + 1
        counts[key] = current
        saveRetryCounts(counts)
        return current <= Self.maxRetries
    }

    private func clearRetry(for key: String) {
        var counts = retryCounts()
        counts.removeValue(forKey: key)
        saveRetryCounts(counts)
    }

    // MARK: - Queue a failed set insert
    func enqueue(_ insert: WorkoutSetInsert) {
        var pending = loadSets()
        pending.append(insert)
        saveSets(pending)
    }

    // MARK: - Queue a failed workout finish
    func enqueueFinish(workoutId: UUID, finishedAt: String) {
        var pending = loadFinishes()
        pending.append(PendingFinish(workoutId: workoutId, finishedAt: finishedAt))
        saveFinishes(pending)
    }

    // MARK: - Queue a failed workout creation
    func enqueueWorkout(_ pending: PendingWorkout) {
        var list = loadWorkouts()
        list.append(pending)
        saveWorkouts(list)
    }

    // MARK: - Remove a queued workout (e.g. if workout start aborted)
    func dequeueWorkout(id: UUID) {
        var list = loadWorkouts()
        list.removeAll { $0.id == id }
        saveWorkouts(list)
    }

    // MARK: - Queue a failed delete
    func enqueueDelete(resource: String) {
        var pending = loadDeletes()
        pending.append(resource)
        saveDeletes(pending)
    }

    var pendingCount: Int { loadSets().count + loadFinishes().count + loadWorkouts().count + loadDeletes().count }

    // MARK: - Flush all pending operations to Supabase
    // Order: creates → finishes → sets (workout must exist before finish/sets reference it)
    func flush() async {
        guard !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Snapshot pending items atomically before processing
        let pendingWorkouts = loadWorkouts()
        let pendingSets = loadSets()
        let pendingFinishes = loadFinishes()
        let pendingDeletes = loadDeletes()
        guard !pendingSets.isEmpty || !pendingFinishes.isEmpty || !pendingWorkouts.isEmpty || !pendingDeletes.isEmpty else { return }

        // Track IDs we're processing to avoid re-processing items added during flush
        let processingWorkoutIds = Set(pendingWorkouts.map(\.id))

        // 1. Flush workout creates first — sets and finishes reference the workout
        var failedWorkoutIds = Set<UUID>()
        var droppedWorkoutIds = Set<UUID>()   // permanently dropped after max retries
        for wk in pendingWorkouts {
            let retryKey = "wk_\(wk.id)"
            guard incrementRetry(for: retryKey) else {
                // Max retries exceeded — drop this workout and its orphaned sets/finishes
                clearRetry(for: retryKey)
                droppedWorkoutIds.insert(wk.id)
                continue
            }
            do {
                let insert = WorkoutInsert(
                    id: wk.id,
                    routineId: wk.routineId,
                    routineName: wk.routineName,
                    startedAt: wk.startedAt
                )
                try await sb.postBatch("workouts", body: [insert])
                clearRetry(for: retryKey)
            } catch {
                failedWorkoutIds.insert(wk.id)
            }
        }
        // Merge: keep failed + any new items added during flush
        let newWorkouts = loadWorkouts().filter { !processingWorkoutIds.contains($0.id) }
        saveWorkouts(pendingWorkouts.filter { failedWorkoutIds.contains($0.id) } + newWorkouts)

        // 2. Flush finishes (skip if parent workout failed; drop if permanently dropped)
        var remainingFinishes: [PendingFinish] = []
        for finish in pendingFinishes {
            if droppedWorkoutIds.contains(finish.workoutId) { continue }
            if failedWorkoutIds.contains(finish.workoutId) {
                remainingFinishes.append(finish)
                continue
            }
            let finRetryKey = "fin_\(finish.workoutId)"
            guard incrementRetry(for: finRetryKey) else {
                clearRetry(for: finRetryKey)
                continue
            }
            do {
                struct FinishPatch: Encodable { let finished_at: String }
                try await sb.patch(
                    "workouts?id=eq.\(finish.workoutId)",
                    body: FinishPatch(finished_at: finish.finishedAt)
                )
                clearRetry(for: finRetryKey)
            } catch {
                remainingFinishes.append(finish)
            }
        }
        let newFinishes = loadFinishes().filter { f in !pendingFinishes.contains(where: { $0.workoutId == f.workoutId }) }
        saveFinishes(remainingFinishes + newFinishes)

        // 3. Flush sets in batches per workout (skip if parent workout failed)
        var remainingSets: [WorkoutSetInsert] = []
        let setsByWorkout = Dictionary(grouping: pendingSets, by: \.workoutId)
        for (workoutId, sets) in setsByWorkout {
            if droppedWorkoutIds.contains(workoutId) { continue }
            if failedWorkoutIds.contains(workoutId) {
                remainingSets.append(contentsOf: sets)
                continue
            }
            let setsRetryKey = "sets_\(workoutId)"
            guard incrementRetry(for: setsRetryKey) else {
                clearRetry(for: setsRetryKey)
                continue
            }
            do {
                try await sb.postBatch("workout_sets", body: sets)
                clearRetry(for: setsRetryKey)
            } catch {
                remainingSets.append(contentsOf: sets)
            }
        }
        let newSets = loadSets().filter { s in !pendingSets.contains(where: { $0.workoutId == s.workoutId && $0.exerciseId == s.exerciseId && $0.setNumber == s.setNumber }) }
        saveSets(remainingSets + newSets)

        // 4. Flush deletes
        var remainingDeletes: [String] = []
        for resource in pendingDeletes {
            do {
                try await sb.delete(resource)
            } catch {
                remainingDeletes.append(resource)
            }
        }
        let newDeletes = loadDeletes().filter { !pendingDeletes.contains($0) }
        saveDeletes(remainingDeletes + newDeletes)
    }

    // MARK: - Sets persistence
    private func loadSets() -> [WorkoutSetInsert] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WorkoutSetInsert].self, from: data)) ?? []
    }

    private func saveSets(_ items: [WorkoutSetInsert]) {
        if items.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            guard let data = try? JSONEncoder().encode(items) else {
                print("[OfflineQueue] Failed to encode pending sets (\(items.count) items)")
                return
            }
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    // MARK: - Finishes persistence
    private func loadFinishes() -> [PendingFinish] {
        guard let data = UserDefaults.standard.data(forKey: finishKey) else { return [] }
        return (try? JSONDecoder().decode([PendingFinish].self, from: data)) ?? []
    }

    private func saveFinishes(_ items: [PendingFinish]) {
        if items.isEmpty {
            UserDefaults.standard.removeObject(forKey: finishKey)
        } else {
            guard let data = try? JSONEncoder().encode(items) else {
                print("[OfflineQueue] Failed to encode pending finishes (\(items.count) items)")
                return
            }
            UserDefaults.standard.set(data, forKey: finishKey)
        }
    }

    // MARK: - Workouts persistence
    private func loadWorkouts() -> [PendingWorkout] {
        guard let data = UserDefaults.standard.data(forKey: workoutKey) else { return [] }
        return (try? JSONDecoder().decode([PendingWorkout].self, from: data)) ?? []
    }

    private func saveWorkouts(_ items: [PendingWorkout]) {
        if items.isEmpty {
            UserDefaults.standard.removeObject(forKey: workoutKey)
        } else {
            guard let data = try? JSONEncoder().encode(items) else {
                print("[OfflineQueue] Failed to encode pending workouts (\(items.count) items)")
                return
            }
            UserDefaults.standard.set(data, forKey: workoutKey)
        }
    }

    // MARK: - Deletes persistence
    private func loadDeletes() -> [String] {
        guard let data = UserDefaults.standard.data(forKey: deleteKey) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func saveDeletes(_ items: [String]) {
        if items.isEmpty {
            UserDefaults.standard.removeObject(forKey: deleteKey)
        } else {
            guard let data = try? JSONEncoder().encode(items) else {
                print("[OfflineQueue] Failed to encode pending deletes (\(items.count) items)")
                return
            }
            UserDefaults.standard.set(data, forKey: deleteKey)
        }
    }
}
