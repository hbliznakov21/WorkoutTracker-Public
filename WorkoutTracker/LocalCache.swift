import Foundation

/// JSON file-based cache in Application Support/WorkoutCache/.
/// All methods are synchronous, never throw — cache miss returns nil.
final class LocalCache {
    static let shared = LocalCache()

    private let dir: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        dir = appSupport.appendingPathComponent("WorkoutCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    // MARK: - Routines

    func saveRoutines(_ routines: [Routine]) {
        write(routines, to: "routines.json")
    }

    func loadRoutines() -> [Routine]? {
        read([Routine].self, from: "routines.json")
    }

    // MARK: - Routine exercises

    func saveRoutineExercises(_ exercises: [RoutineExercise], routineId: UUID) {
        write(exercises, to: "routine_\(routineId.uuidString).json")
    }

    func loadRoutineExercises(routineId: UUID) -> [RoutineExercise]? {
        read([RoutineExercise].self, from: "routine_\(routineId.uuidString).json")
    }

    // MARK: - Last sets (exerciseId → sets from last session)

    func saveLastSets(_ sets: [UUID: [CachedSet]]) {
        // Merge into existing cache so Pull day doesn't erase Push day data
        var merged = loadLastSets() ?? [:]
        for (eid, newSets) in sets { merged[eid] = newSets }
        write(merged, to: "last_sets.json")
    }

    func loadLastSets() -> [UUID: [CachedSet]]? {
        read([UUID: [CachedSet]].self, from: "last_sets.json")
    }

    // MARK: - Private helpers

    private func write<T: Encodable>(_ value: T, to filename: String) {
        let url = dir.appendingPathComponent(filename)
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from filename: String) -> T? {
        let url = dir.appendingPathComponent(filename)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Cached set model

struct CachedSet: Codable {
    let exerciseId: UUID
    let workoutId: UUID
    let weightKg: Double
    let reps: Int
    let setNumber: Int
}
