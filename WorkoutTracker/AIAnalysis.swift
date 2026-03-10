import Foundation

// MARK: - Claude API response models

struct AIAnalysisResult: Codable {
    let summary: String
    let overallRating: String       // "excellent", "good", "average", "needs_improvement"
    let suggestions: [AISuggestion]
    let strengths: [String]
    let weaknesses: [String]

    // New fields — optional for backward compat with cached analyses
    let volumeAnalysis: VolumeAnalysis?
    let nextSessionTargets: [NextSessionTarget]?
    let plateauAlerts: [PlateauAlert]?

    enum CodingKeys: String, CodingKey {
        case summary
        case overallRating = "overall_rating"
        case suggestions, strengths, weaknesses
        case volumeAnalysis = "volume_analysis"
        case nextSessionTargets = "next_session_targets"
        case plateauAlerts = "plateau_alerts"
    }
}

struct VolumeAnalysis: Codable {
    let todayVolume: Double         // kg
    let previousVolume: Double?     // kg (nil if no prev data)
    let changePct: Double?          // e.g. +5.2 or -3.1
    let assessment: String          // 1 sentence

    enum CodingKeys: String, CodingKey {
        case todayVolume = "today_volume"
        case previousVolume = "previous_volume"
        case changePct = "change_pct"
        case assessment
    }
}

struct NextSessionTarget: Codable, Identifiable {
    var id: String { exerciseName }
    let exerciseName: String
    let targetWeight: Double
    let targetReps: Int
    let dropSetWeight: Double?
    let dropSetReps: Int?
    let note: String                // e.g. "Push for 12 reps before bumping weight"

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case targetWeight = "target_weight"
        case targetReps = "target_reps"
        case dropSetWeight = "drop_set_weight"
        case dropSetReps = "drop_set_reps"
        case note
    }
}

struct PlateauAlert: Codable, Identifiable {
    var id: String { exerciseName }
    let exerciseName: String
    let sessionsStalled: Int        // how many sessions at same weight/reps
    let suggestion: String          // what to try

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case sessionsStalled = "sessions_stalled"
        case suggestion
    }
}

struct AISuggestion: Codable, Identifiable {
    var id: UUID { UUID(uuidString: idStr ?? "") ?? UUID() }
    let idStr: String?
    let exerciseName: String
    let action: String              // "increase_weight", "increase_reps", "maintain", "decrease_weight", "add_drop_set"
    let currentWeight: Double
    let currentReps: Int
    let suggestedWeight: Double
    let suggestedReps: Int
    let dropSetWeight: Double?
    let dropSetReps: Int?
    let reason: String

    enum CodingKeys: String, CodingKey {
        case idStr = "id"
        case exerciseName = "exercise_name"
        case action
        case currentWeight = "current_weight"
        case currentReps = "current_reps"
        case suggestedWeight = "suggested_weight"
        case suggestedReps = "suggested_reps"
        case dropSetWeight = "drop_set_weight"
        case dropSetReps = "drop_set_reps"
        case reason
    }

    var actionLabel: String {
        switch action {
        case "increase_weight": return "Increase Weight"
        case "increase_reps":   return "Increase Reps"
        case "decrease_weight": return "Decrease Weight"
        case "maintain":        return "Maintain"
        case "add_drop_set":    return "Add Drop Set"
        default:                return action.capitalized
        }
    }

    var actionColor: String {
        switch action {
        case "increase_weight": return "22c55e"
        case "increase_reps":   return "3b82f6"
        case "decrease_weight": return "ef4444"
        case "maintain":        return "f59e0b"
        case "add_drop_set":    return "a855f7"
        default:                return "94a3b8"
        }
    }
}

// MARK: - Supabase row models

struct WorkoutAnalysisRow: Codable {
    let id: UUID
    let workoutId: UUID
    let routineName: String
    let analysisJson: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId   = "workout_id"
        case routineName = "routine_name"
        case analysisJson = "analysis_json"
        case createdAt   = "created_at"
    }
}

struct WorkoutAnalysisInsert: Encodable {
    let workoutId: UUID
    let routineName: String
    let analysisJson: String

    enum CodingKeys: String, CodingKey {
        case workoutId   = "workout_id"
        case routineName = "routine_name"
        case analysisJson = "analysis_json"
    }
}

struct AISuggestionRow: Codable, Identifiable {
    let id: UUID
    let workoutId: UUID
    let exerciseId: UUID
    let exerciseName: String
    let suggestedWeight: Double
    let suggestedReps: Int
    let reason: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case id
        case workoutId     = "workout_id"
        case exerciseId    = "exercise_id"
        case exerciseName  = "exercise_name"
        case suggestedWeight = "suggested_weight"
        case suggestedReps = "suggested_reps"
        case reason, status
    }
}

// MARK: - Session goals (pre-workout AI analysis)

struct SessionGoal: Codable, Identifiable {
    var id: String { exerciseName }
    let exerciseName: String
    let action: String              // "increase_weight", "increase_reps", "maintain", "deload", "add_drop_set"
    let suggestedWeight: Double
    let suggestedReps: Int
    let dropSetWeight: Double?
    let dropSetReps: Int?
    let reasoning: String

    enum CodingKeys: String, CodingKey {
        case exerciseName  = "exercise_name"
        case action
        case suggestedWeight = "suggested_weight"
        case suggestedReps   = "suggested_reps"
        case dropSetWeight   = "drop_set_weight"
        case dropSetReps     = "drop_set_reps"
        case reasoning
    }

    var actionLabel: String {
        switch action {
        case "increase_weight": return "↑ Weight"
        case "increase_reps":   return "↑ Reps"
        case "decrease_weight": return "↓ Weight"
        case "maintain":        return "Maintain"
        case "deload":          return "Deload"
        case "add_drop_set":    return "Drop Set"
        default:                return action.capitalized
        }
    }

    var actionColor: String {
        switch action {
        case "increase_weight": return "22c55e"
        case "increase_reps":   return "3b82f6"
        case "decrease_weight": return "ef4444"
        case "maintain":        return "f59e0b"
        case "deload":          return "38bdf8"
        case "add_drop_set":    return "a855f7"
        default:                return "94a3b8"
        }
    }
}

struct SessionGoalsResult: Codable {
    let summary: String
    let goals: [SessionGoal]
}

struct SessionGoalRow: Codable {
    let id: UUID
    let routineName: String
    let goalDate: String
    let goalsJson: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case routineName = "routine_name"
        case goalDate    = "goal_date"
        case goalsJson   = "goals_json"
        case createdAt   = "created_at"
    }
}

struct SessionGoalInsert: Encodable {
    let routineName: String
    let goalDate: String
    let goalsJson: String

    enum CodingKeys: String, CodingKey {
        case routineName = "routine_name"
        case goalDate    = "goal_date"
        case goalsJson   = "goals_json"
    }
}

// MARK: - Weight AI insight

struct WeightInsight: Codable {
    let trend: String               // "losing", "gaining", "stable", "fluctuating"
    let weeklyRate: Double           // kg/week
    let suggestion: String           // 1-2 sentence recommendation
    let calorieAction: String        // "increase", "maintain", "decrease", "hold"
    let confidence: String           // "high", "medium", "low"

    enum CodingKeys: String, CodingKey {
        case trend
        case weeklyRate = "weekly_rate"
        case suggestion
        case calorieAction = "calorie_action"
        case confidence
    }

    var actionLabel: String {
        switch calorieAction {
        case "increase": return "Increase Cals"
        case "decrease": return "Decrease Cals"
        case "maintain":  return "Maintain Cals"
        case "hold":      return "Hold Steady"
        default:          return calorieAction.capitalized
        }
    }

    var actionColor: String {
        switch calorieAction {
        case "increase": return "22c55e"
        case "decrease": return "ef4444"
        case "maintain":  return "3b82f6"
        case "hold":      return "f59e0b"
        default:          return "94a3b8"
        }
    }
}

// MARK: - Photo comparison AI insight

struct PhotoInsight: Codable {
    let summary: String               // 2-3 sentence overall comparison
    let changes: [PhotoChange]        // per-body-area observations
    let overallProgress: String       // "significant", "moderate", "minimal", "no_change"
    let encouragement: String         // motivational closing sentence

    enum CodingKeys: String, CodingKey {
        case summary, changes
        case overallProgress = "overall_progress"
        case encouragement
    }

    var progressLabel: String {
        switch overallProgress {
        case "significant": return "Great Progress"
        case "moderate":    return "Good Progress"
        case "minimal":     return "Early Signs"
        case "no_change":   return "Stay Consistent"
        default:            return overallProgress.capitalized
        }
    }

    var progressColor: String {
        switch overallProgress {
        case "significant": return "22c55e"
        case "moderate":    return "3b82f6"
        case "minimal":     return "f59e0b"
        case "no_change":   return "94a3b8"
        default:            return "94a3b8"
        }
    }
}

struct PhotoChange: Codable, Identifiable {
    var id: String { area }
    let area: String                  // "shoulders", "chest", "abs", "arms", "legs", etc.
    let observation: String           // what changed
    let direction: String             // "improved", "maintained", "declined"
}

struct AISuggestionInsert: Encodable {
    let workoutId: UUID
    let exerciseId: UUID
    let exerciseName: String
    let suggestedWeight: Double
    let suggestedReps: Int
    let reason: String?
    let status: String

    enum CodingKeys: String, CodingKey {
        case workoutId     = "workout_id"
        case exerciseId    = "exercise_id"
        case exerciseName  = "exercise_name"
        case suggestedWeight = "suggested_weight"
        case suggestedReps = "suggested_reps"
        case reason, status
    }
}

// MARK: - User Phase Goals (Sonya build)

struct UserPhaseGoals: Codable {
    let phase: String           // "cut", "post_cut", "bulk"
    let targetCalories: Int
    let targetProtein: Int
    let targetCarbs: Int
    let targetFat: Int
    let endDate: String         // yyyy-MM-dd

    enum CodingKeys: String, CodingKey {
        case phase
        case targetCalories = "target_calories"
        case targetProtein = "target_protein"
        case targetCarbs = "target_carbs"
        case targetFat = "target_fat"
        case endDate = "end_date"
    }

    var phaseLabel: String {
        switch phase {
        case "cut":      return "Cutting"
        case "post_cut": return "Post-Cut"
        case "bulk":     return "Bulking"
        default:         return phase.capitalized
        }
    }

    var phaseColor: String {
        switch phase {
        case "cut":      return "ef4444"
        case "post_cut": return "f59e0b"
        case "bulk":     return "22c55e"
        default:         return "94a3b8"
        }
    }
}
