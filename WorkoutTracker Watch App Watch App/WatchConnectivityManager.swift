import Foundation
import HealthKit
import WatchConnectivity
import WidgetKit

/// Receives messages from the iPhone app and updates WatchStore.
/// Also triggers HealthKit workout session start/stop.
final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()

    #if SONYA
    static let appGroupID = "group.com.hbliznakov.WorkoutTrackerSonya"
    #else
    static let appGroupID = "group.com.hbliznakov.WorkoutTracker"
    #endif
    static let scheduleKey = "weeklySchedule"

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // Load schedule + rest days from application context on launch
        loadFromContext()
    }

    private func loadFromContext() {
        let ctx = WCSession.default.receivedApplicationContext
        if let schedule = ctx["schedule"] as? [String: String] {
            saveScheduleToSharedDefaults(schedule)
        }
        if let restDays = ctx["restDays"] as? [String] {
            saveRestDaysToSharedDefaults(restDays)
        }
    }

    private func saveScheduleToSharedDefaults(_ schedule: [String: String]) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        if let data = try? JSONEncoder().encode(schedule) {
            defaults.set(data, forKey: Self.scheduleKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func saveRestDaysToSharedDefaults(_ restDays: [String]) {
        guard let defaults = UserDefaults(suiteName: Self.appGroupID) else { return }
        defaults.set(restDays, forKey: "widgetRestDays")
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Receive message from iPhone
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        Task { @MainActor in
            WatchStore.shared.handleMessage(message)
            let type = message["type"] as? String
            if type == "workout_started" {
                await HealthKitManager.shared.startWorkout()
            } else if type == "cardio_started" {
                let raw         = UInt(message["activityTypeRaw"] as? Int ?? 0)
                let activityType = HKWorkoutActivityType(rawValue: raw) ?? .cycling
                let isIndoor    = message["isIndoor"] as? Bool ?? true
                await HealthKitManager.shared.startWorkout(activityType: activityType, isIndoor: isIndoor)
            } else if type == "workout_finished" {
                await HealthKitManager.shared.endWorkout()
            } else if type == "workout_discarded" {
                await HealthKitManager.shared.discardWorkout()
            }
        }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        self.session(session, didReceiveMessage: message)
        replyHandler(["status": "ok"])
    }

    // MARK: - Background delivery via transferUserInfo
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            WatchStore.shared.handleMessage(userInfo)
            let type = userInfo["type"] as? String
            if type == "workout_started" {
                await HealthKitManager.shared.startWorkout()
            } else if type == "cardio_started" {
                let raw          = UInt(userInfo["activityTypeRaw"] as? Int ?? 0)
                let activityType = HKWorkoutActivityType(rawValue: raw) ?? .cycling
                let isIndoor     = userInfo["isIndoor"] as? Bool ?? true
                await HealthKitManager.shared.startWorkout(activityType: activityType, isIndoor: isIndoor)
            } else if type == "workout_finished" {
                await HealthKitManager.shared.endWorkout()
            } else if type == "workout_discarded" {
                await HealthKitManager.shared.discardWorkout()
            }
        }
    }

    // MARK: - Send to phone (with transferUserInfo fallback)
    private func sendToPhone(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isReachable else {
            // Phone not immediately reachable — queue for background delivery
            WCSession.default.transferUserInfo(message)
            return
        }
        WCSession.default.sendMessage(message, replyHandler: nil) { error in
            print("WCSession Watch→Phone sendMessage error: \(error)")
            // Fallback to transferUserInfo on send failure
            WCSession.default.transferUserInfo(message)
        }
    }

    func sendRestSkip() {
        sendToPhone(["type": "rest_skip"])
    }

    // MARK: - Send live stats to phone
    func sendLiveStats(heartRate: Double, calories: Double) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["type": "live_stats", "heartRate": heartRate, "calories": calories],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    // MARK: - Application context (schedule + rest days sync)
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if let schedule = applicationContext["schedule"] as? [String: String] {
            saveScheduleToSharedDefaults(schedule)
        }
        if let restDays = applicationContext["restDays"] as? [String] {
            saveRestDaysToSharedDefaults(restDays)
        }
    }

    // MARK: - Required delegates
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        print("WCSession Watch activated: \(activationState.rawValue), error: \(String(describing: error))")
    }
}
