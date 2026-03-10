import Foundation
import Observation

/// Observable state for the Watch app — updated by WatchConnectivityManager
@Observable
@MainActor
final class WatchStore {
    static let shared = WatchStore()

    var isWorkoutActive    = false
    var routineName        = ""
    var exerciseName       = ""
    var nextExerciseName   = ""
    var setIndex           = 0          // 1-based
    var targetSets         = 0
    var weight: Double     = 0
    var reps               = 0
    var restSeconds        = 0          // countdown; 0 = not resting
    var totalRestSeconds   = 0          // full duration of current rest period
    var restEndTime: Double = 0         // Unix timestamp when rest ends
    var heartRate: Double  = 0
    var activeCalories: Double = 0
    var workoutStartTime: Date? = nil
    var elapsedDisplay     = "0:00"

    // Called by connectivity manager on message receipt
    func handleMessage(_ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }
        switch type {
        case "workout_started":
            isWorkoutActive    = true
            routineName        = msg["routineName"] as? String ?? ""
            workoutStartTime   = Date()
            exerciseName       = ""
            nextExerciseName   = ""
            restSeconds        = 0
        case "cardio_started":
            isWorkoutActive    = true
            routineName        = msg["routineName"] as? String ?? "Cardio"
            exerciseName       = msg["routineName"] as? String ?? "Cardio"
            workoutStartTime   = Date()
            nextExerciseName   = ""
            setIndex           = 0
            targetSets         = 0
            restSeconds        = 0
        case "exercise_update":
            exerciseName       = msg["exerciseName"]     as? String ?? exerciseName
            nextExerciseName   = msg["nextExerciseName"] as? String ?? ""
            setIndex           = msg["setIndex"]  as? Int    ?? setIndex
            targetSets         = msg["targetSets"] as? Int   ?? targetSets
            weight             = msg["weight"]    as? Double ?? weight
            reps               = msg["reps"]      as? Int    ?? reps
        case "rest_start":
            totalRestSeconds   = msg["seconds"] as? Int ?? 60
            restEndTime        = msg["endTime"] as? Double ?? (Date().timeIntervalSince1970 + Double(totalRestSeconds))
            restSeconds        = max(0, Int(restEndTime - Date().timeIntervalSince1970))
        case "rest_stop":
            restSeconds        = 0
            restEndTime        = 0
        case "workout_finished", "workout_discarded":
            isWorkoutActive    = false
            restSeconds        = 0
            restEndTime        = 0
            heartRate          = 0
            activeCalories     = 0
            workoutStartTime   = nil
        default:
            break
        }
    }
}
