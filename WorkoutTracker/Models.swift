import Foundation
import HealthKit

// MARK: - Routine
struct Routine: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let dayLabel: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case dayLabel = "day_label"
    }
}

// MARK: - Routine insert / update
struct RoutineInsert: Encodable {
    let name: String
    let dayLabel: String?

    enum CodingKeys: String, CodingKey {
        case name
        case dayLabel = "day_label"
    }
}

struct RoutineUpdate: Encodable {
    var name: String?
    var dayLabel: String?

    enum CodingKeys: String, CodingKey {
        case name
        case dayLabel = "day_label"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = name     { try c.encode(v, forKey: .name) }
        if let v = dayLabel { try c.encode(v, forKey: .dayLabel) }
    }
}

// MARK: - Exercise
struct Exercise: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let muscleGroup: String?
    let equipment: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case muscleGroup = "muscle_group"
        case equipment
    }
}

// MARK: - Exercise insert / update
struct ExerciseInsert: Encodable {
    let name: String
    let muscleGroup: String?
    let equipment: String?

    enum CodingKeys: String, CodingKey {
        case name
        case muscleGroup = "muscle_group"
        case equipment
    }
}

struct ExerciseUpdate: Encodable {
    var name: String?
    var muscleGroup: String?
    var equipment: String?

    enum CodingKeys: String, CodingKey {
        case name
        case muscleGroup = "muscle_group"
        case equipment
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = name        { try c.encode(v, forKey: .name) }
        if let v = muscleGroup { try c.encode(v, forKey: .muscleGroup) }
        if let v = equipment   { try c.encode(v, forKey: .equipment) }
    }
}

// MARK: - RoutineExercise (joined with exercises table)
struct RoutineExercise: Identifiable, Codable {
    let id: UUID
    let routineId: UUID
    let position: Int
    let targetSets: Int
    let targetRepsMin: Int?
    let targetRepsMax: Int?
    let notes: String?
    let supersetGroup: String?
    let isWarmup: Bool
    let restSeconds: Int?
    let exercises: Exercise

    enum CodingKeys: String, CodingKey {
        case id
        case routineId      = "routine_id"
        case position
        case targetSets     = "target_sets"
        case targetRepsMin  = "target_reps_min"
        case targetRepsMax  = "target_reps_max"
        case notes
        case supersetGroup  = "superset_group"
        case isWarmup       = "is_warmup"
        case restSeconds    = "rest_seconds"
        case exercises
    }
}

// MARK: - Workout
struct Workout: Identifiable, Codable {
    let id: UUID
    let routineId: UUID?
    let routineName: String
    let startedAt: Date
    let finishedAt: Date?
    let calories: Int?
    let avgHeartRate: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case routineId    = "routine_id"
        case routineName  = "routine_name"
        case startedAt    = "started_at"
        case finishedAt   = "finished_at"
        case calories
        case avgHeartRate = "avg_heart_rate"
    }

    var duration: String {
        let end = finishedAt ?? Date()
        let mins = Int(end.timeIntervalSince(startedAt) / 60)
        return mins < 60 ? "\(mins) min" : "\(mins / 60)h \(mins % 60)m"
    }

    var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(startedAt)     { return "Today" }
        if cal.isDateInYesterday(startedAt) { return "Yesterday" }
        return Self.dMMMFormatter.string(from: startedAt)
    }

    private static let dMMMFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()
}

// MARK: - WorkoutSet
struct WorkoutSet: Identifiable, Codable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let exerciseName: String
    let setNumber: Int
    let weightKg: Double
    let reps: Int
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId    = "workout_id"
        case exerciseId   = "exercise_id"
        case exerciseName = "exercise_name"
        case setNumber    = "set_number"
        case weightKg     = "weight_kg"
        case reps
        case loggedAt     = "logged_at"
    }
}

// MARK: - Insert payloads (no id — DB generates it)
struct WorkoutInsert: Encodable {
    var id: UUID?            // set when creating offline so flush uses same UUID
    let routineId: UUID?
    let routineName: String
    let startedAt: String    // ISO8601 string
    var finishedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case routineId   = "routine_id"
        case routineName = "routine_name"
        case startedAt   = "started_at"
        case finishedAt  = "finished_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let id { try c.encode(id, forKey: .id) }
        try c.encode(routineId, forKey: .routineId)
        try c.encode(routineName, forKey: .routineName)
        try c.encode(startedAt, forKey: .startedAt)
        if let finishedAt { try c.encode(finishedAt, forKey: .finishedAt) }
    }
}

struct WorkoutSetInsert: Codable {
    let workoutId: UUID
    let exerciseId: UUID
    let exerciseName: String
    let setNumber: Int
    let weightKg: Double
    let reps: Int
    let loggedAt: String

    enum CodingKeys: String, CodingKey {
        case workoutId    = "workout_id"
        case exerciseId   = "exercise_id"
        case exerciseName = "exercise_name"
        case setNumber    = "set_number"
        case weightKg     = "weight_kg"
        case reps
        case loggedAt     = "logged_at"
    }
}

// MARK: - Progression suggestion
struct ProgressionSuggestion: Identifiable {
    let id = UUID()
    let exerciseName: String
    let currentWeight: Double
    let repsHit: Int          // max reps achieved across all sets
    let targetRepsMax: Int
}

// MARK: - Overload suggestion (2+ consecutive sessions hitting target reps)
struct OverloadSuggestion: Identifiable {
    let id: String               // exerciseName + currentWeight — used for dismiss tracking
    let exerciseName: String
    let currentWeight: Double
    let suggestedWeight: Double
    let consecutiveSessions: Int
}

// MARK: - In-memory set state (not persisted until logged)
struct SetState: Identifiable {
    let id = UUID()
    var weight: Double
    var reps: Int
    var isDone: Bool  = false
    var isTarget: Bool = false   // true = progression engine raised weight or reps
    var isDropSet: Bool = false  // true = this set was added as a drop set
}

// MARK: - Cardio types
struct CardioType: Identifiable {
    let id = UUID()
    let name: String
    let icon: String                         // SF Symbol
    let hkActivityType: HKWorkoutActivityType
    let isIndoor: Bool
}

let cardioTypes: [CardioType] = [
    CardioType(name: "Indoor Cycling", icon: "figure.indoor.cycle", hkActivityType: .cycling,       isIndoor: true),
    CardioType(name: "Running",        icon: "figure.run",           hkActivityType: .running,      isIndoor: false),
    CardioType(name: "Treadmill",      icon: "figure.run",           hkActivityType: .running,      isIndoor: true),
    CardioType(name: "Step Climbing",  icon: "figure.stair.stepper", hkActivityType: .stairClimbing, isIndoor: true),
    CardioType(name: "Elliptical",     icon: "figure.elliptical",    hkActivityType: .elliptical,   isIndoor: true),
    CardioType(name: "Rowing",         icon: "oar.2.crossed",        hkActivityType: .rowing,       isIndoor: true),
    CardioType(name: "Walking",        icon: "figure.walk",          hkActivityType: .walking,      isIndoor: false),
]

// MARK: - Body Weight
struct BodyWeight: Identifiable, Codable {
    let id: UUID
    let loggedAt: Date
    let weightKg: Double

    enum CodingKeys: String, CodingKey {
        case id
        case loggedAt = "logged_at"
        case weightKg = "weight_kg"
    }

    var dayLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(loggedAt)     { return "Today" }
        if cal.isDateInYesterday(loggedAt) { return "Yesterday" }
        return Self.dMMMFormatter.string(from: loggedAt)
    }

    private static let dMMMFormatter: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM"; return f
    }()
}

struct BodyWeightInsert: Encodable {
    let loggedAt: String
    let weightKg: Double

    enum CodingKeys: String, CodingKey {
        case loggedAt = "logged_at"
        case weightKg = "weight_kg"
    }
}

// MARK: - Apple Health workout (not yet synced to Supabase)

struct HKWorkoutEntry: Identifiable {
    let id:           UUID    // HealthKit workout UUID → stored as healthkit_uuid in Supabase
    let activityName: String
    let startedAt:    Date
    let finishedAt:   Date
    let calories:     Int?
    let avgHeartRate: Int?

    var duration: String {
        let secs = Int(finishedAt.timeIntervalSince(startedAt))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m) min"
    }

    var emoji: String {
        let n = activityName.lowercased()
        if n.contains("walk")     { return "🚶" }
        if n.contains("run")      { return "🏃" }
        if n.contains("cycl")     { return "🚴" }
        if n.contains("swim")     { return "🏊" }
        if n.contains("hik")      { return "🥾" }
        if n.contains("strength") { return "💪" }
        if n.contains("hiit")     { return "⚡" }
        if n.contains("yoga")     { return "🧘" }
        if n.contains("row")      { return "🚣" }
        if n.contains("stair")    { return "🪜" }
        return "🏋️"
    }
}

// MARK: - Routine exercise insert (POST)
struct RoutineExerciseInsert: Encodable {
    let routineId: UUID
    let exerciseId: UUID
    let position: Int
    let targetSets: Int
    let targetRepsMin: Int?
    let targetRepsMax: Int?
    let restSeconds: Int?
    let supersetGroup: String?
    let isWarmup: Bool
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case routineId     = "routine_id"
        case exerciseId    = "exercise_id"
        case position
        case targetSets    = "target_sets"
        case targetRepsMin = "target_reps_min"
        case targetRepsMax = "target_reps_max"
        case restSeconds   = "rest_seconds"
        case supersetGroup = "superset_group"
        case isWarmup      = "is_warmup"
        case notes
    }
}

// MARK: - Routine exercise update (PATCH)
// Uses double-optional pattern: outer nil = skip field, inner nil = send JSON null
struct RoutineExerciseUpdate: Encodable {
    var targetSets: Int?
    var targetRepsMin: Int?
    var targetRepsMax: Int?
    var restSeconds: Int?
    var supersetGroup: String??   // nil = skip, .some(nil) = send null
    var isWarmup: Bool?
    var notes: String??           // nil = skip, .some(nil) = send null
    var position: Int?

    enum CodingKeys: String, CodingKey {
        case targetSets    = "target_sets"
        case targetRepsMin = "target_reps_min"
        case targetRepsMax = "target_reps_max"
        case restSeconds   = "rest_seconds"
        case supersetGroup = "superset_group"
        case isWarmup      = "is_warmup"
        case notes
        case position
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let v = targetSets    { try c.encode(v, forKey: .targetSets) }
        if let v = targetRepsMin { try c.encode(v, forKey: .targetRepsMin) }
        if let v = targetRepsMax { try c.encode(v, forKey: .targetRepsMax) }
        if let v = restSeconds   { try c.encode(v, forKey: .restSeconds) }
        if let v = isWarmup      { try c.encode(v, forKey: .isWarmup) }
        if let v = position      { try c.encode(v, forKey: .position) }
        // Double-optional: encode null when .some(nil), skip when nil
        if let outer = supersetGroup {
            try c.encode(outer, forKey: .supersetGroup)
        }
        if let outer = notes {
            try c.encode(outer, forKey: .notes)
        }
    }
}

// MARK: - Photo Entry
struct PhotoEntry: Codable, Identifiable {
    let id: UUID
    let date: String        // yyyy-MM-dd
    let pose: String        // "front", "side", "back"
    let imagePath: String   // relative path in Documents/ProgressPhotos/
    let weightKg: Double?
}

// MARK: - Schedule
#if SONYA
let defaultWeeklySchedule: [String: String] = [
    "Monday": "Monday", "Tuesday": "Tuesday", "Wednesday": "Wednesday",
    "Thursday": "Thursday", "Friday": "Friday", "Saturday": "Saturday", "Sunday": "Rest"
]
#else
let defaultWeeklySchedule: [String: String] = [
    "Monday": "Push (Mon)", "Tuesday": "Pull A", "Wednesday": "Legs A",
    "Thursday": "Push (Thu)", "Friday": "Pull B", "Saturday": "Legs B", "Sunday": "Rest"
]

// MARK: - Cardio phase (Hristo only)

enum CardioPhase {
    case miniCut, reverse12, reverse34, bulk

    var weeklyGoal: Int {
        switch self {
        case .miniCut:   return 7
        case .reverse12: return 5
        case .reverse34: return 4
        case .bulk:      return 3
        }
    }

    static func current(on date: Date = Date()) -> CardioPhase {
        let cal = Calendar.current
        let c = cal.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return .bulk }
        let v = y * 10000 + m * 100 + d
        if v <= 20260307 { return .miniCut }
        if v <= 20260321 { return .reverse12 }
        if v <= 20260404 { return .reverse34 }
        return .bulk
    }
}
#endif
