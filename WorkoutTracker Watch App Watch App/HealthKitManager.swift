import Foundation
import HealthKit
import WatchKit

/// Manages HKWorkoutSession + live heart rate on Apple Watch.
/// Starts automatically when a workout begins (replaces GymStart Shortcut).
@MainActor
final class HealthKitManager: NSObject {
    static let shared = HealthKitManager()

    private let store           = HKHealthStore()
    private var session:        HKWorkoutSession?
    private var builder:        HKLiveWorkoutBuilder?
    private let watchStore      = WatchStore.shared
    private var statsTimer:     Timer?
    private let shareTypes: Set<HKSampleType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.activeEnergyBurned)
    ]
    private let readTypes: Set<HKObjectType> = [
        HKObjectType.workoutType(),
        HKQuantityType(.heartRate),
        HKQuantityType(.activeEnergyBurned)
    ]

    // MARK: - Authorise
    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: shareTypes, read: readTypes)
    }

    // MARK: - Start workout session
    func startWorkout(
        activityType: HKWorkoutActivityType = .traditionalStrengthTraining,
        isIndoor: Bool = true
    ) async {
        guard session == nil else { return }
        await requestAuthorization()
        let config = HKWorkoutConfiguration()
        config.activityType  = activityType
        config.locationType  = isIndoor ? .indoor : .outdoor
        do {
            let newSession = try HKWorkoutSession(healthStore: store, configuration: config)
            let newBuilder = newSession.associatedWorkoutBuilder()
            newBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: store, workoutConfiguration: config
            )
            newSession.delegate  = self
            newBuilder.delegate  = self
            self.session = newSession
            self.builder = newBuilder
            let startDate = Date()
            newSession.startActivity(with: startDate)
            try await newBuilder.beginCollection(at: startDate)

            // HKWorkoutSession already prevents app suspension — no extended session needed

            // Push live stats to phone every 10 seconds (battery-friendly)
            statsTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.pushStatsToPhone() }
            }
        } catch {
            print("HealthKit startWorkout error: \(error)")
        }
    }

    // MARK: - End workout session (saves to Apple Health)
    func endWorkout() async {
        statsTimer?.invalidate()
        statsTimer = nil
        guard let s = session, let b = builder else { return }
        self.session = nil
        self.builder = nil
        s.end()
        do {
            try await b.endCollection(at: Date())
            try await b.finishWorkout()
        } catch {
            print("HealthKit endWorkout error: \(error)")
        }
    }

    // MARK: - Discard workout session (does NOT save to Apple Health)
    func discardWorkout() async {
        statsTimer?.invalidate()
        statsTimer = nil
        guard let s = session, let b = builder else { return }
        self.session = nil
        self.builder = nil
        s.end()
        do {
            try await b.endCollection(at: Date())
            try await b.discardWorkout()
        } catch {
            print("HealthKit discardWorkout error: \(error)")
        }
    }

    // MARK: - Push current stats to phone
    private func pushStatsToPhone() {
        guard let builder else { return }
        let hr  = builder.statistics(for: HKQuantityType(.heartRate))?
                         .mostRecentQuantity()?.doubleValue(for: HKUnit(from: "count/min")) ?? 0
        let cal = builder.statistics(for: HKQuantityType(.activeEnergyBurned))?
                         .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0

        // Update local Watch display
        watchStore.heartRate      = hr
        watchStore.activeCalories = cal

        // Send to phone (drop silently if not reachable — timer will retry in 3s)
        WatchConnectivityManager.shared.sendLiveStats(heartRate: hr, calories: cal)
    }
}

// MARK: - HKWorkoutSessionDelegate
extension HealthKitManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ session: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) { }

    nonisolated func workoutSession(
        _ session: HKWorkoutSession,
        didFailWithError error: Error
    ) {
        print("WorkoutSession error: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
extension HealthKitManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) { }

    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) { }
}


