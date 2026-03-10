import Foundation

/// Centralized UserDefaults key management.
/// Prevents typo bugs from scattered string literals.
enum UDKey {
    // MARK: - HealthKit import
    static let dismissedHKUUIDs = "dismissed_hk_uuids"

    // MARK: - Deload tracking
    static let deloadWeeks = "deload_weeksWithoutDeload"
    static let deloadActive = "deload_isDeloadWeek"
    static let deloadDismissed = "deload_suggestionDismissed"
    static let deloadLastCheckedWeek = "deload_lastCheckedWeek"

    // MARK: - Schedule
    static let weeklySchedule = "weeklySchedule"

    // MARK: - Overload
    static let dismissedOverloadIDs = "dismissed_overload_ids"

    // MARK: - Offline queue
    static let offlinePendingSets = "offline_pending_sets"
    static let offlinePendingFinishes = "offline_pending_finishes"
    static let offlinePendingWorkouts = "offline_pending_workouts"

    // MARK: - Photos
    static let photoEntries = "photo_entries"
}
