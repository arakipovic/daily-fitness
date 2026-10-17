import Foundation
import HealthKit

@Observable
@MainActor
final class HealthKitManager {
    static let shared = HealthKitManager()

    private let store = HKHealthStore()

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }
    var authorizationStatus: AuthStatus = .notDetermined

    // Steps
    var todaySteps: Double = 0
    var weeklySteps: [DaySteps] = []

    // Sleep
    var lastNightSleep: SleepSummary? = nil
    var weeklySleep: [SleepSummary] = []

    // Weight & body composition
    var recentWeightKg: Double? = nil
    var weeklyWeightKg: [DayWeight] = []
    var bodyFatPercentage: Double? = nil
    var weeklyBodyFat: [DayMeasurement] = []
    var waistCircumferenceCm: Double? = nil
    var weeklyWaistCm: [DayMeasurement] = []

    // Heart
    var restingHeartRateBPM: Double? = nil
    var heartRateVariabilityMs: Double? = nil

    // Energy
    var activeEnergyToday: Double = 0
    var avgRestingEnergyKcal: Double? = nil

    // Recent workouts
    var recentActivities: [ActivitySummary] = []

    var sevenDayAverageKg: Double? {
        guard !weeklyWeightKg.isEmpty else { return nil }
        return weeklyWeightKg.map(\.weightKg).reduce(0, +) / Double(weeklyWeightKg.count)
    }

    /// Activity level inferred from 7-day average step count (NEAT proxy, excluding workout calories).
    /// < 5,000 steps → Sedentary · 5,000–7,999 → Lightly Active · ≥ 8,000 → Moderately Active
    var suggestedLifestyle: LifestyleActivity? {
        guard !weeklySteps.isEmpty else { return nil }
        let avg = weeklySteps.map(\.steps).reduce(0, +) / Double(weeklySteps.count)
        if avg < 5_000 { return .sedentary }
        if avg < 8_000 { return .light }
        return .moderate
    }

    enum AuthStatus { case notDetermined, authorized, denied }

    struct DaySteps: Identifiable {
        let id = UUID()
        let date: Date
        let steps: Double
    }

    struct DayWeight: Identifiable {
        let id = UUID()
        let date: Date
        let weightKg: Double
    }

    struct DayMeasurement: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    struct ActivitySummary: Identifiable {
        let id: UUID
        let activityType: HKWorkoutActivityType
        let startDate: Date
        let duration: TimeInterval
        let activeCalories: Double

        var displayName: String {
            switch activityType {
            case .running:                      return "Run"
            case .tennis:                       return "Tennis"
            case .tableTennis:                  return "Table Tennis"
            case .traditionalStrengthTraining:  return "Strength"
            case .cycling:                      return "Cycling"
            case .walking:                      return "Walk"
            case .swimming:                     return "Swimming"
            case .yoga:                         return "Yoga"
            case .highIntensityIntervalTraining: return "HIIT"
            case .basketball:                   return "Basketball"
            case .soccer:                       return "Soccer"
            case .hiking:                       return "Hiking"
            case .elliptical:                   return "Elliptical"
            case .rowing:                       return "Rowing"
            case .badminton:                    return "Badminton"
            case .squash:                       return "Squash"
            default:                            return "Workout"
            }
        }

        var systemImage: String {
            switch activityType {
            case .running:                      return "figure.run"
            case .tennis, .tableTennis, .squash, .badminton: return "figure.tennis"
            case .traditionalStrengthTraining:  return "dumbbell"
            case .cycling:                      return "figure.outdoor.cycle"
            case .walking:                      return "figure.walk"
            case .swimming:                     return "figure.pool.swim"
            case .yoga:                         return "figure.yoga"
            case .highIntensityIntervalTraining: return "bolt.heart"
            case .hiking:                       return "figure.hiking"
            case .basketball:                   return "figure.basketball"
            case .soccer:                       return "figure.soccer"
            case .elliptical:                   return "figure.elliptical"
            case .rowing:                       return "figure.rower"
            default:                            return "figure.mixed.cardio"
            }
        }

        var durationString: String {
            let mins = Int(duration / 60)
            return mins >= 60 ? "\(mins / 60)h \(mins % 60)m" : "\(mins)m"
        }
    }

    struct SleepSummary: Identifiable {
        var id: Date { date }
        let date: Date          // earliest sleep-sample start (bedtime proxy)
        let wakeTime: Date?     // latest sleep-sample end (wake time proxy)
        let inBedDuration: TimeInterval
        let asleepDuration: TimeInterval
        let coreDuration: TimeInterval
        let deepDuration: TimeInterval
        let remDuration: TimeInterval

        var asleepHours: Double { asleepDuration / 3600 }
        var inBedHours: Double { inBedDuration / 3600 }
        var coreHours: Double { coreDuration / 3600 }
        var deepHours: Double { deepDuration / 3600 }
        var remHours: Double { remDuration / 3600 }
        var hasStages: Bool { coreDuration + deepDuration + remDuration > 0 }

        var quality: String {
            switch asleepHours {
            case ..<5:   return "Poor"
            case 5..<6:  return "Fair"
            case 6..<7:  return "OK"
            case 7..<9:  return "Good"
            default:     return "Long"
            }
        }
    }

    private init() {}

    func requestAuthorization() async {
        guard isAvailable else { return }

        let shareTypes: Set<HKSampleType> = [
            HKWorkoutType.workoutType()
        ]

        let readTypes: Set<HKObjectType> = [
            HKQuantityType(.stepCount),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.basalEnergyBurned),
            HKQuantityType(.bodyMass),
            HKQuantityType(.bodyFatPercentage),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKCategoryType(.sleepAnalysis),
            HKWorkoutType.workoutType(),
            HKQuantityType(.waistCircumference)
        ]

        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            authorizationStatus = .authorized
            await fetchAll()
        } catch {
            authorizationStatus = .denied
        }
    }

    // MARK: - Write workout

    func writeWorkout(session: SessionLog) async {
        guard isAvailable,
              let start = session.started,
              let end = session.completed,
              end > start else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
            recentActivities = await fetchRecentActivities()
        } catch {
            // Workout still saved in app — HealthKit write failure is non-fatal
        }
    }

    func fetchAll() async {
        guard !Task.isCancelled else { return }
        async let steps      = fetchTodaySteps()
        async let weekly     = fetchWeeklySteps()
        async let sleep      = fetchLastNightSleep()
        async let weeklySl   = fetchWeeklySleep()
        async let weight     = fetchRecentWeight()
        async let weeklyW    = fetchWeeklyWeight()
        async let energy     = fetchTodayActiveEnergy()
        async let resting    = fetchAvgRestingEnergy()
        async let fat        = fetchBodyFat()
        async let weeklyBF   = fetchWeeklyBodyFat()
        async let waist      = fetchRecentWaist()
        async let weeklyWa   = fetchWeeklyWaistCm()
        async let rhr        = fetchRestingHeartRate()
        async let hrv        = fetchHRV()
        async let activities = fetchRecentActivities()

        todaySteps             = await steps
        weeklySteps            = await weekly
        lastNightSleep         = await sleep
        weeklySleep            = await weeklySl
        recentWeightKg         = await weight
        weeklyWeightKg         = await weeklyW
        activeEnergyToday      = await energy
        avgRestingEnergyKcal   = await resting
        bodyFatPercentage      = await fat
        weeklyBodyFat          = await weeklyBF
        waistCircumferenceCm   = await waist
        weeklyWaistCm          = await weeklyWa
        restingHeartRateBPM    = await rhr
        heartRateVariabilityMs = await hrv
        recentActivities       = await activities
    }

    // MARK: - Steps

    private func fetchTodaySteps() async -> Double {
        guard !Task.isCancelled else { return 0 }
        return await fetchSteps(for: Calendar.current.startOfDay(for: Date()), to: Date())
    }

    private func fetchWeeklySteps() async -> [DaySteps] {
        guard !Task.isCancelled else { return [] }
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var result: [DaySteps] = []
        for i in (0..<7).reversed() {
            guard let dayStart = calendar.date(byAdding: .day, value: -i, to: today),
                  let dayEnd   = calendar.date(byAdding: .day, value:  1, to: dayStart) else { continue }
            let s = await fetchSteps(for: dayStart, to: dayEnd)
            result.append(DaySteps(date: dayStart, steps: s))
        }
        return result
    }

    private func fetchSteps(for start: Date, to end: Date) async -> Double {
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
            store.execute(query)
        }
    }

    // MARK: - Sleep

    private func fetchLastNightSleep() async -> SleepSummary? {
        guard !Task.isCancelled else { return nil }
        let now = Date()
        let calendar = Calendar.current
        // Use a noon-to-noon window (same as weeklySleep) so early bedtimes
        // (e.g. 10 PM) aren't cut off by a fixed lookback window.
        guard
            let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now),
            let yesterdayNoon = calendar.date(byAdding: .day, value: -1, to: todayNoon)
        else { return nil }
        let windowEnd = min(todayNoon, now)
        return await fetchSleepSummary(from: yesterdayNoon, to: windowEnd)
    }

    private func fetchWeeklySleep() async -> [SleepSummary] {
        guard !Task.isCancelled else { return [] }
        let calendar = Calendar.current
        var result: [SleepSummary] = []
        for i in 0..<7 {
            guard
                let refDate = calendar.date(byAdding: .day, value: -i, to: Date()),
                let noonCurr = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: refDate),
                let noonPrev = calendar.date(byAdding: .day, value: -1, to: noonCurr)
            else { continue }
            let windowEnd = min(noonCurr, Date())
            if let summary = await fetchSleepSummary(from: noonPrev, to: windowEnd) {
                result.append(summary)
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    private func fetchSleepSummary(from windowStart: Date, to windowEnd: Date) async -> SleepSummary? {
        let type = HKCategoryType(.sleepAnalysis)
        let predicate = HKQuery.predicateForSamples(withStart: windowStart, end: windowEnd)
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                guard let samples = samples as? [HKCategorySample], !samples.isEmpty else {
                    cont.resume(returning: nil); return
                }

                // Collect intervals per category. Multiple sources (Apple Watch, Sleep Cycle,
                // Garmin, etc.) can write overlapping samples for the same night, so we merge
                // overlapping intervals before summing to avoid double-counting (e.g. 16 h).
                var inBedIntervals: [(Date, Date)] = []
                var asleepIntervals: [(Date, Date)] = []
                var core: TimeInterval = 0
                var deep: TimeInterval = 0
                var rem: TimeInterval = 0

                for s in samples {
                    guard s.endDate > s.startDate else { continue }
                    if s.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                        inBedIntervals.append((s.startDate, s.endDate))
                    }
                    if let v = HKCategoryValueSleepAnalysis(rawValue: s.value) {
                        switch v {
                        case .asleepCore:
                            core += s.endDate.timeIntervalSince(s.startDate)
                            asleepIntervals.append((s.startDate, s.endDate))
                        case .asleepDeep:
                            deep += s.endDate.timeIntervalSince(s.startDate)
                            asleepIntervals.append((s.startDate, s.endDate))
                        case .asleepREM:
                            rem += s.endDate.timeIntervalSince(s.startDate)
                            asleepIntervals.append((s.startDate, s.endDate))
                        case .asleepUnspecified:
                            asleepIntervals.append((s.startDate, s.endDate))
                        default: break
                        }
                    }
                }

                let asleep = Self.mergedDuration(asleepIntervals)
                var inBed = Self.mergedDuration(inBedIntervals)
                if inBed == 0 { inBed = asleep }
                let finalAsleep = asleep > 0 ? asleep : inBed

                let wakeTime = asleepIntervals.map(\.1).max()
                    ?? inBedIntervals.map(\.1).max()

                guard finalAsleep > 0 || inBed > 0 else { cont.resume(returning: nil); return }
                cont.resume(returning: SleepSummary(
                    date: samples.first?.startDate ?? windowStart,
                    wakeTime: wakeTime,
                    inBedDuration: inBed,
                    asleepDuration: finalAsleep,
                    coreDuration: core,
                    deepDuration: deep,
                    remDuration: rem
                ))
            }
            self.store.execute(query)
        }
    }

    /// Merges overlapping/adjacent intervals and returns their total non-overlapping duration.
    private nonisolated static func mergedDuration(_ intervals: [(Date, Date)]) -> TimeInterval {
        let sorted = intervals.sorted { $0.0 < $1.0 }
        var total: TimeInterval = 0
        var current: (Date, Date)? = nil
        for interval in sorted {
            if let c = current {
                if interval.0 < c.1 {
                    current = (c.0, max(c.1, interval.1))
                } else {
                    total += c.1.timeIntervalSince(c.0)
                    current = interval
                }
            } else {
                current = interval
            }
        }
        if let c = current { total += c.1.timeIntervalSince(c.0) }
        return total
    }

    // MARK: - Weight

    private func fetchWeeklyWeight() async -> [DayWeight] {
        guard !Task.isCancelled else { return [] }
        let type = HKQuantityType(.bodyMass)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekAgo = calendar.date(byAdding: .day, value: -7, to: today) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: weekAgo, end: Date())

        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else { cont.resume(returning: []); return }
                var byDay: [Date: Double] = [:]
                for s in samples {
                    let day = calendar.startOfDay(for: s.startDate)
                    let kg = s.quantity.doubleValue(for: .gramUnit(with: .kilo))
                    byDay[day] = byDay[day].map { min($0, kg) } ?? kg
                }
                cont.resume(returning: byDay.map { DayWeight(date: $0.key, weightKg: $0.value) }.sorted { $0.date < $1.date })
            }
            self.store.execute(query)
        }
    }

    private func fetchRecentWeight() async -> Double? {
        await fetchMostRecentQuantity(.bodyMass, unit: .gramUnit(with: .kilo), days: 30)
    }

    // MARK: - Body Composition

    private func fetchBodyFat() async -> Double? {
        // HealthKit returns body fat as a fraction (0.20 = 20%)
        guard let value = await fetchMostRecentQuantity(.bodyFatPercentage, unit: .percent(), days: 60) else { return nil }
        return value * 100
    }

    private func fetchWeeklyBodyFat() async -> [DayMeasurement] {
        await fetchWeeklyMeasurements(.bodyFatPercentage, unit: .percent(), days: 14) { $0 * 100 }
    }

    private func fetchRecentWaist() async -> Double? {
        // HealthKit stores waist in meters; convert to cm
        guard let m = await fetchMostRecentQuantity(.waistCircumference, unit: .meter(), days: 90) else { return nil }
        return m * 100
    }

    private func fetchWeeklyWaistCm() async -> [DayMeasurement] {
        await fetchWeeklyMeasurements(.waistCircumference, unit: .meter(), days: 90) { $0 * 100 }
    }

    private func fetchWeeklyMeasurements(
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        days: Int,
        transform: @escaping (Double) -> Double = { $0 }
    ) async -> [DayMeasurement] {
        let type = HKQuantityType(identifier)
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let calendar = Calendar.current
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                guard let samples = samples as? [HKQuantitySample] else { cont.resume(returning: []); return }
                var byDay: [Date: Double] = [:]
                for s in samples {
                    byDay[calendar.startOfDay(for: s.startDate)] = transform(s.quantity.doubleValue(for: unit))
                }
                let sorted = byDay.map { DayMeasurement(date: $0.key, value: $0.value) }.sorted { $0.date < $1.date }
                cont.resume(returning: sorted)
            }
            self.store.execute(query)
        }
    }

    // MARK: - Heart

    private func fetchRestingHeartRate() async -> Double? {
        await fetchMostRecentQuantity(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), days: 7)
    }

    private func fetchHRV() async -> Double? {
        await fetchMostRecentQuantity(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), days: 7)
    }

    // MARK: - Active Energy

    /// Fetches total active energy burned on `date`. For today, callers should use
    /// `activeEnergyToday` directly (it's kept live). This method is for past dates.
    func activeEnergy(on date: Date) async -> Double {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.isDateInToday(date)
            ? Date()
            : (calendar.date(byAdding: .day, value: 1, to: start) ?? start)
        return await fetchActiveEnergy(from: start, to: end)
    }

    private func fetchTodayActiveEnergy() async -> Double {
        let start = Calendar.current.startOfDay(for: Date())
        return await fetchActiveEnergy(from: start, to: Date())
    }

    /// 7-day average basal (resting) energy from Apple Watch. Nil if Watch data is unavailable.
    private func fetchAvgRestingEnergy() async -> Double? {
        let type = HKQuantityType(.basalEnergyBurned)
        guard let start = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                guard let sum = stats?.sumQuantity()?.doubleValue(for: .kilocalorie()), sum > 500 else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: sum / 7.0)
            }
            self.store.execute(query)
        }
    }

    private func fetchActiveEnergy(from start: Date, to end: Date) async -> Double {
        let type = HKQuantityType(.activeEnergyBurned)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, _ in
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0)
            }
            self.store.execute(query)
        }
    }

    // MARK: - Recent Workouts

    private func fetchRecentActivities() async -> [ActivitySummary] {
        guard !Task.isCancelled else { return [] }
        guard let twoWeeksAgo = Calendar.current.date(byAdding: .day, value: -14, to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: twoWeeksAgo, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: HKWorkoutType.workoutType(),
                predicate: predicate,
                limit: 15,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                guard let workouts = samples as? [HKWorkout] else { cont.resume(returning: []); return }
                let appBundleID = Bundle.main.bundleIdentifier ?? ""
                let summaries = workouts
                    .filter { $0.sourceRevision.source.bundleIdentifier != appBundleID }
                    .map { w in
                        ActivitySummary(
                            id: w.uuid,
                            activityType: w.workoutActivityType,
                            startDate: w.startDate,
                            duration: w.duration,
                            activeCalories: w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                                .sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                        )
                    }
                cont.resume(returning: summaries)
            }
            self.store.execute(query)
        }
    }

    // MARK: - Shared helper

    private func fetchMostRecentQuantity(_ identifier: HKQuantityTypeIdentifier, unit: HKUnit, days: Int) async -> Double? {
        let type = HKQuantityType(identifier)
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        return await withCheckedContinuation { cont in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
            ) { _, samples, _ in
                cont.resume(returning: (samples?.first as? HKQuantitySample)?.quantity.doubleValue(for: unit))
            }
            store.execute(query)
        }
    }
}
