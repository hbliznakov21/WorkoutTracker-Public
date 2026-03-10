import SwiftUI
import HealthKit

class AppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in
            await HealthKitManager.shared.startWorkout(
                activityType: workoutConfiguration.activityType,
                isIndoor:     workoutConfiguration.locationType == .indoor
            )
        }
    }
}

@main
struct WorkoutTracker_Watch_App_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var watchStore = WatchStore.shared

    init() {
        WatchConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(watchStore)
                // Pre-authorize HealthKit so HKWorkoutSession starts instantly
                // when a workout begins, keeping the display active without delay.
                .task { await HealthKitManager.shared.requestAuthorization() }
        }
    }
}
