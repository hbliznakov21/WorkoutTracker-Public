import Foundation
import HealthKit

/// Reads active energy burned + heart rate from HealthKit on iPhone.
final class PhoneHealthKitManager {
    static let shared = PhoneHealthKitManager()
    private let store = HKHealthStore()
    private var liveTimer: Timer?
    private var liveStartDate: Date?

    private let readTypes: Set<HKObjectType> = [
        HKQuantityType(.activeEnergyBurned),
        HKQuantityType(.heartRate),
        HKQuantityType(.bodyMass),
        HKWorkoutType.workoutType()
    ]

    func requestAuthorization() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    // MARK: - Launch Watch app with workout configuration
    func startWatchApp(activityType: HKWorkoutActivityType, isIndoor: Bool) async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let config = HKWorkoutConfiguration()
        config.activityType = activityType
        config.locationType = isIndoor ? .indoor : .outdoor
        try? await store.startWatchApp(toHandle: config)
    }

    // MARK: - Live monitoring (HealthKit fallback, polls every 10s)

    func startLiveMonitoring(from startDate: Date) {
        stopLiveMonitoring()
        liveStartDate = startDate
        DispatchQueue.main.async { [weak self] in
            self?.liveTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
                self?.pollLiveStats()
            }
        }
    }

    func stopLiveMonitoring() {
        liveTimer?.invalidate()
        liveTimer = nil
        liveStartDate = nil
    }

    private func pollLiveStats() {
        guard let start = liveStartDate else { return }
        let end = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        // Latest heart rate sample
        let hrType = HKQuantityType(.heartRate)
        let hrUnit = HKUnit(from: "count/min")
        let hrSort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let hrQuery = HKSampleQuery(
            sampleType: hrType, predicate: predicate, limit: 1, sortDescriptors: [hrSort]
        ) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }
            let hr = sample.quantity.doubleValue(for: hrUnit)
            Task { @MainActor in
                if hr > WorkoutStore.shared.liveHeartRate {
                    WorkoutStore.shared.liveHeartRate = hr
                }
            }
        }
        store.execute(hrQuery)

        // Cumulative active calories
        let calType = HKQuantityType(.activeEnergyBurned)
        let calQuery = HKStatisticsQuery(
            quantityType: calType, quantitySamplePredicate: predicate, options: .cumulativeSum
        ) { _, stats, _ in
            guard let cal = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) else { return }
            Task { @MainActor in
                WorkoutStore.shared.liveCalories = cal
            }
        }
        store.execute(calQuery)
    }

    // MARK: - Workouts from HealthKit (Apple Fitness app recordings)

    func fetchWorkouts(days: Int) async -> [HKWorkoutEntry] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        let workouts: [HKWorkout] = await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sort]
            ) { _, samples, _ in
                cont.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(query)
        }

        var entries: [HKWorkoutEntry] = []
        for workout in workouts {
            let wPredicate = HKQuery.predicateForSamples(
                withStart: workout.startDate, end: workout.endDate,
                options: [.strictStartDate, .strictEndDate]
            )
            let avgHR    = await fetchAvgHeartRate(predicate: wPredicate)
            let calories: Int? = {
                if let q = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity() {
                    return Int(q.doubleValue(for: .kilocalorie()))
                }
                return workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()
                    .map { Int($0.doubleValue(for: .kilocalorie())) }
            }()
            let isIndoor = workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool ?? false
            entries.append(HKWorkoutEntry(
                id:           workout.uuid,
                activityName: activityName(workout.workoutActivityType, indoor: isIndoor),
                startedAt:    workout.startDate,
                finishedAt:   workout.endDate,
                calories:     calories,
                avgHeartRate: avgHR
            ))
        }
        return entries
    }

    private func activityName(_ type: HKWorkoutActivityType, indoor: Bool) -> String {
        switch type {
        case .walking:                          return indoor ? "Indoor Walk"    : "Outdoor Walk"
        case .running:                          return indoor ? "Indoor Run"     : "Outdoor Run"
        case .cycling:                          return indoor ? "Indoor Cycling" : "Cycling"
        case .swimming:                         return "Swimming"
        case .hiking:                           return "Hiking"
        case .traditionalStrengthTraining:      return "Strength Training"
        case .functionalStrengthTraining:       return "Functional Training"
        case .highIntensityIntervalTraining:    return "HIIT"
        case .elliptical:                       return "Elliptical"
        case .stairClimbing:                    return "Stair Climbing"
        case .rowing:                           return "Rowing"
        case .yoga:                             return "Yoga"
        case .pilates:                          return "Pilates"
        case .dance:                            return "Dance"
        case .crossTraining:                    return "Cross Training"
        case .mindAndBody:                      return "Mind & Body"
        case .jumpRope:                         return "Jump Rope"
        default:                                return "Workout"
        }
    }

    // MARK: - Body weight from HealthKit (Withings syncs here automatically)

    func fetchBodyWeight(days: Int) async -> [BodyWeight] {
        guard HKHealthStore.isHealthDataAvailable() else { return [] }
        let type      = HKQuantityType(.bodyMass)
        let start     = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sort      = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: [sort]
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else {
                    cont.resume(returning: [])
                    return
                }
                // One entry per calendar day — ascending sort means last overwrites = most recent reading
                let cal = Calendar.current
                var byDay: [DateComponents: HKQuantitySample] = [:]
                for s in samples {
                    byDay[cal.dateComponents([.year, .month, .day], from: s.startDate)] = s
                }
                let entries = byDay.values
                    .sorted { $0.startDate < $1.startDate }
                    .map { s in
                        BodyWeight(
                            id:        s.uuid,
                            loggedAt:  s.startDate,
                            weightKg:  s.quantity.doubleValue(for: .gramUnit(with: .kilo))
                        )
                    }
                cont.resume(returning: entries)
            }
            store.execute(query)
        }
    }

    // MARK: - Post-workout stats

    func fetchStats(from start: Date, to end: Date) async -> (calories: Int?, avgHeartRate: Int?) {
        let predicate = HKQuery.predicateForSamples(
            withStart: start, end: end, options: .strictStartDate
        )
        async let cal = fetchCalories(predicate: predicate)
        async let hr  = fetchAvgHeartRate(predicate: predicate)
        return await (cal, hr)
    }

    private func fetchCalories(predicate: NSPredicate) async -> Int? {
        let type = HKQuantityType(.activeEnergyBurned)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum
            ) { _, stats, _ in
                let val = stats?.sumQuantity()?.doubleValue(for: .kilocalorie())
                cont.resume(returning: val.map { Int($0.rounded()) })
            }
            store.execute(q)
        }
    }

    private func fetchAvgHeartRate(predicate: NSPredicate) async -> Int? {
        let type = HKQuantityType(.heartRate)
        let unit = HKUnit(from: "count/min")
        return await withCheckedContinuation { cont in
            let q = HKStatisticsQuery(
                quantityType: type, quantitySamplePredicate: predicate, options: .discreteAverage
            ) { _, stats, _ in
                let val = stats?.averageQuantity()?.doubleValue(for: unit)
                cont.resume(returning: val.map { Int($0.rounded()) })
            }
            store.execute(q)
        }
    }
}
