import Foundation
import UIKit
import WatchConnectivity

/// Sends workout state updates from iPhone to Apple Watch.
final class PhoneConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityManager()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // Message types that must never be cancelled — they change workout state on the Watch
    private let criticalTypes: Set<String> = ["workout_started", "workout_finished", "workout_discarded", "cardio_started"]

    private func send(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else {
            print("WCSession not activated")
            notifyFailure()
            return
        }
        guard WCSession.default.isReachable else {
            // Watch app not in foreground — queue via transferUserInfo for background delivery
            // Cancel stale non-critical transfers to prevent unbounded queue growth
            for transfer in WCSession.default.outstandingUserInfoTransfers {
                let transferType = transfer.userInfo["type"] as? String ?? ""
                if !criticalTypes.contains(transferType) {
                    transfer.cancel()
                }
            }
            WCSession.default.transferUserInfo(message)
            return
        }
        WCSession.default.sendMessage(message, replyHandler: nil) { [weak self] error in
            print("WCSession sendMessage error: \(error)")
            self?.notifyFailure()
        }
    }

    private func notifyFailure() {
        DispatchQueue.main.async {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
    }

    // MARK: - Schedule & rest days sync (sent together — updateApplicationContext replaces entire context)
    func sendSchedule(_ schedule: [String: String]) {
        updateContext(schedule: schedule)
    }

    func sendRestDays(_ restDayStrings: [String]) {
        updateContext(restDays: restDayStrings)
    }

    private func updateContext(schedule: [String: String]? = nil, restDays: [String]? = nil) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
        // Merge with existing context so we don't overwrite the other key
        var ctx = WCSession.default.applicationContext
        if let schedule { ctx["schedule"] = schedule }
        if let restDays { ctx["restDays"] = restDays }
        do {
            try WCSession.default.updateApplicationContext(ctx)
        } catch {
            print("Failed to update application context: \(error)")
        }
    }

    // MARK: - Message senders
    func sendWorkoutStarted(routineName: String) {
        send(["type": "workout_started", "routineName": routineName])
    }

    func sendExerciseUpdate(
        exerciseName: String,
        nextExerciseName: String,
        setIndex: Int,
        targetSets: Int,
        weight: Double,
        reps: Int
    ) {
        send([
            "type":             "exercise_update",
            "exerciseName":     exerciseName,
            "nextExerciseName": nextExerciseName,
            "setIndex":         setIndex,
            "targetSets":       targetSets,
            "weight":           weight,
            "reps":             reps
        ])
    }

    func sendRestStart(seconds: Int, endTime: Double) {
        send(["type": "rest_start", "seconds": seconds, "endTime": endTime])
    }

    func sendRestStop() {
        send(["type": "rest_stop"])
    }

    func sendWorkoutFinished() {
        send(["type": "workout_finished"])
    }

    func sendWorkoutDiscarded() {
        send(["type": "workout_discarded"])
    }

    func sendCardioStarted(name: String, activityTypeRaw: UInt, isIndoor: Bool) {
        send([
            "type":            "cardio_started",
            "routineName":     name,
            "activityTypeRaw": Int(activityTypeRaw),
            "isIndoor":        isIndoor
        ])
    }

    // MARK: - Receive from Watch (live stats via sendMessage or transferUserInfo)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncoming(userInfo)
    }

    private func handleIncoming(_ msg: [String: Any]) {
        guard let type = msg["type"] as? String else { return }
        switch type {
        case "live_stats":
            let hr  = msg["heartRate"] as? Double ?? 0
            let cal = msg["calories"]  as? Double ?? 0
            Task { @MainActor [weak self] in
                guard let _ = self else { return }
                WorkoutStore.shared.liveHeartRate = hr
                WorkoutStore.shared.liveCalories  = cal
            }
        case "rest_skip":
            Task { @MainActor [weak self] in
                guard let _ = self else { return }
                WorkoutStore.shared.restSkippedFromWatch = true
            }
        default:
            break
        }
    }

    // MARK: - Required delegates
    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
