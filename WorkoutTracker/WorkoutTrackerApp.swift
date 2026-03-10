import SwiftUI
import UIKit
import WidgetKit

@main
struct WorkoutTrackerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var store = WorkoutStore.shared
    @State private var photoStore = PhotoStore.shared

    init() {
        Self.migrateScheduleToAppGroup()
        PhoneConnectivityManager.shared.activate()
        // Sync current schedule to watch on launch
        PhoneConnectivityManager.shared.sendSchedule(WorkoutStore.shared.schedule)
    }

    /// One-time migration: copy schedule from standard UserDefaults to App Group shared container
    private static func migrateScheduleToAppGroup() {
        let migrationKey = "didMigrateScheduleToAppGroup"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }
        if let data = UserDefaults.standard.data(forKey: "weeklySchedule"),
           let shared = UserDefaults(suiteName: WorkoutStore.appGroupID) {
            shared.set(data, forKey: "weeklySchedule")
            WidgetCenter.shared.reloadAllTimelines()
        }
        UserDefaults.standard.set(true, forKey: migrationKey)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(photoStore)
                .preferredColorScheme(.dark)
                .task {
                    await PhoneHealthKitManager.shared.requestAuthorization()
                    await WorkoutStore.shared.loadScheduleFromSupabase()
                    await WorkoutStore.shared.loadRoutines(force: true)
                }
                .onChange(of: store.activeWorkout != nil) { _, isActive in
                    UIApplication.shared.isIdleTimerDisabled = isActive
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                UIApplication.shared.isIdleTimerDisabled = WorkoutStore.shared.activeWorkout != nil
                Task {
                    await OfflineQueue.shared.flush()
                    await WorkoutStore.shared.loadScheduleFromSupabase()
                    await WorkoutStore.shared.loadRoutines(force: true)
                    // Ensure rest days are synced to Watch widget on every foreground
                    await WorkoutStore.shared.loadRestDays()
                }
            }
        }
    }
}
