import Foundation
import HealthKit
import os.log

// MARK: - HealthKit: Body Weight, Weight Sync, HK Workout Import

extension WorkoutStore {

    // MARK: - Load body weight + trigger sync & HK workout loading

    func loadBodyWeight() async {
        bodyWeightLog = await PhoneHealthKitManager.shared.fetchBodyWeight(days: 90)
        async let sync: () = syncWeightsToSupabase()
        async let hk: ()   = loadPendingHKWorkouts()
        _ = await (sync, hk)
    }

    // MARK: - Pending HK workouts

    func loadPendingHKWorkouts() async {
        let hkWorkouts = await PhoneHealthKitManager.shared.fetchWorkouts(days: 30)
        guard !hkWorkouts.isEmpty else { pendingHKWorkouts = []; return }

        struct HKUUIDRow: Decodable {
            let healthkitUuid: String
            enum CodingKeys: String, CodingKey { case healthkitUuid = "healthkit_uuid" }
        }

        let existing: [HKUUIDRow] = (try? await sb.get(
            "workouts?select=healthkit_uuid&healthkit_uuid=not.is.null"
        )) ?? []
        let existingUUIDs = Set(existing.map(\.healthkitUuid))

        let dismissed = dismissedUUIDs
        pendingHKWorkouts = hkWorkouts.filter {
            let uuid = $0.id.uuidString.lowercased()
            return !existingUUIDs.contains(uuid) && !dismissed.contains(uuid)
        }
    }

    // MARK: - Dismiss an HK workout

    func dismissWorkout(_ entry: HKWorkoutEntry) {
        dismissedUUIDs.insert(entry.id.uuidString.lowercased())
        pendingHKWorkouts.removeAll { $0.id == entry.id }
    }

    // MARK: - Import an HK workout into Supabase

    func importWorkout(_ entry: HKWorkoutEntry) async {
        importingWorkoutId = entry.id
        importError = nil

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var row: [String: Any] = [
            "id":             UUID().uuidString,
            "healthkit_uuid": entry.id.uuidString.lowercased(),
            "routine_name":   entry.activityName,
            "started_at":     iso.string(from: entry.startedAt),
            "finished_at":    iso.string(from: entry.finishedAt),
        ]
        if let cal = entry.calories     { row["calories"]       = cal }
        if let hr  = entry.avgHeartRate { row["avg_heart_rate"] = hr }

        do {
            try await sb.insertRaw("workouts", payload: [row])
            pendingHKWorkouts.removeAll { $0.id == entry.id }
            let updated: [Workout]? = try? await sb.get(
                "workouts?select=id,routine_id,routine_name,started_at,finished_at,calories,avg_heart_rate" +
                "&finished_at=not.is.null&order=started_at.desc&limit=60"
            )
            if let updated { history = updated }
        } catch {
            importError = error.localizedDescription
        }
        importingWorkoutId = nil
    }

    // MARK: - Sync body weights to Supabase

    func syncWeightsToSupabase() async {
        guard !bodyWeightLog.isEmpty else { return }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        let payload: [[String: Any]] = bodyWeightLog.map { w in
            [
                "logged_at": fmt.string(from: w.loggedAt),
                "weight_kg": round(w.weightKg * 100) / 100
            ]
        }
        try? await SupabaseClient.shared.upsertRaw(
            "body_weight?on_conflict=logged_at", payload: payload
        )
    }
}
