//
//  HealthDataFetcher.swift
//

import HealthKit
import Spezi

@Observable
class HealthDataFetcher: DefaultInitializable, Module, EnvironmentAccessible {
    @ObservationIgnored private let healthStore = HKHealthStore()

    required init() { }

    // MARK: - Quantities (14-day daily series)

    func fetchLastTwoWeeksQuantityData(
        for identifier: HKQuantityTypeIdentifier,
        unit: HKUnit,
        options: HKStatisticsOptions
    ) async throws -> [Double] {
        guard let quantityType = HKObjectType.quantityType(forIdentifier: identifier) else {
            throw HealthDataFetcherError.invalidObjectType
        }

        let predicate = createLastTwoWeeksPredicate()

        let quantityLastTwoWeeks = HKSamplePredicate.quantitySample(
            type: quantityType,
            predicate: predicate
        )

        let query = HKStatisticsCollectionQueryDescriptor(
            predicate: quantityLastTwoWeeks,
            options: options,
            anchorDate: Date.startOfDay(),
            intervalComponents: DateComponents(day: 1)
        )

        let collection = try await query.result(for: healthStore)

        var daily: [Double] = []
        collection.enumerateStatistics(
            from: Date().twoWeeksAgoStartOfDay(),
            to: Date.startOfDay()
        ) { stats, _ in
            var value: Double = 0
            if options.contains(.discreteAverage), let q = stats.averageQuantity() {
                value = q.doubleValue(for: unit)
            } else if options.contains(.discreteMin), let q = stats.minimumQuantity() {
                value = q.doubleValue(for: unit)
            } else if options.contains(.discreteMax), let q = stats.maximumQuantity() {
                value = q.doubleValue(for: unit)
            } else if let q = stats.sumQuantity() { // .cumulativeSum
                value = q.doubleValue(for: unit)
            }
            daily.append(value)
        }

        return daily
    }

    func fetchLastTwoWeeksStepCount() async throws -> [Double] {
        try await fetchLastTwoWeeksQuantityData(
            for: .stepCount,
            unit: .count(),
            options: [.cumulativeSum]
        )
    }

    func fetchLastTwoWeeksActiveEnergy() async throws -> [Double] {
        try await fetchLastTwoWeeksQuantityData(
            for: .activeEnergyBurned,
            unit: .largeCalorie(),
            options: [.cumulativeSum]
        )
    }

    func fetchLastTwoWeeksExerciseTime() async throws -> [Double] {
        try await fetchLastTwoWeeksQuantityData(
            for: .appleExerciseTime,
            unit: .minute(),
            options: [.cumulativeSum]
        )
    }

    func fetchLastTwoWeeksBodyWeight() async throws -> [Double] {
        try await fetchLastTwoWeeksQuantityData(
            for: .bodyMass,
            unit: .pound(),
            options: [.discreteAverage]
        )
    }

    func fetchLastTwoWeeksHeartRate() async throws -> [Double] {
        try await fetchLastTwoWeeksQuantityData(
            for: .heartRate,
            unit: HKUnit.count().unitDivided(by: .minute()),
            options: [.discreteAverage]
        )
    }

    // MARK: - Sleep (3pm→3pm day)

    func fetchLastTwoWeeksSleep() async throws -> [Double] {
        var daily: [Double] = []

        for day in -14..<0 {
            guard
                let startOfSleepDay = Calendar.current.date(byAdding: .day, value: day - 1, to: Date.startOfDay()),
                let startOfSleep = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: startOfSleepDay),
                let endOfSleepDay = Calendar.current.date(byAdding: .day, value: day, to: Date.startOfDay()),
                let endOfSleep = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: endOfSleepDay),
                let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)
            else {
                daily.append(0)
                continue
            }

            let dateRange = HKQuery.predicateForSamples(withStart: startOfSleep, end: endOfSleep, options: .strictEndDate)
            let asleepOnly = HKCategoryValueSleepAnalysis.predicateForSamples(equalTo: HKCategoryValueSleepAnalysis.allAsleepValues)
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [dateRange, asleepOnly])

            let descriptor = HKSampleQueryDescriptor(
                predicates: [.categorySample(type: sleepType, predicate: predicate)],
                sortDescriptors: []
            )

            let samples: [HKCategorySample] = try await descriptor.result(for: healthStore)

            let seconds = samples.reduce(0.0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
            daily.append(seconds / 3600.0)
        }

        return daily
    }

    private func createLastTwoWeeksPredicate() -> NSPredicate {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -14, to: now) ?? now
        return HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)
    }
}

// MARK: - Clinical Records (Apple Health → Health Records / MyChart)

extension HealthDataFetcher {
    /// Clinical types we care about.
    private func clinicalTypes() -> [HKClinicalType] {
        var types: [HKClinicalType] = []
        if let t = HKObjectType.clinicalType(forIdentifier: .allergyRecord)      { types.append(t) }
        if let t = HKObjectType.clinicalType(forIdentifier: .conditionRecord)    { types.append(t) }
        if let t = HKObjectType.clinicalType(forIdentifier: .immunizationRecord) { types.append(t) }
        if let t = HKObjectType.clinicalType(forIdentifier: .labResultRecord)    { types.append(t) }
        if let t = HKObjectType.clinicalType(forIdentifier: .medicationRecord)   { types.append(t) }
        if let t = HKObjectType.clinicalType(forIdentifier: .procedureRecord)    { types.append(t) }
        if #available(iOS 17.0, *),
           let t = HKObjectType.clinicalType(forIdentifier: .vitalSignRecord)    { types.append(t) }
        return types
    }

    /// Ask for read access to clinical records. (Shows the Health permission sheet.)
    @discardableResult
    func requestClinicalAuthorization() async throws -> Bool {
        let readTypes = Set<HKObjectType>(clinicalTypes())
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Bool, Error>) in
            healthStore.requestAuthorization(toShare: nil, read: readTypes) { ok, err in
                if let err { cont.resume(throwing: err) } else { cont.resume(returning: ok) }
            }
        }
    }

    /// Fetch raw clinical records grouped by type.
    func fetchClinicalRecords() async throws -> [HKClinicalType: [HKClinicalRecord]] {
        _ = try await requestClinicalAuthorization()
        var result: [HKClinicalType: [HKClinicalRecord]] = [:]
        for type in clinicalTypes() {
            let records = try await fetchRecords(for: type)
            if !records.isEmpty { result[type] = records }
        }
        return result
    }

    /// Plain-text block suitable for LLM context.
    func fetchClinicalRecordsPlainText(limitPerType: Int = 20) async throws -> String {
        let grouped = try await fetchClinicalRecords()
        guard !grouped.isEmpty else { return "No clinical records were found in Apple Health." }

        var lines: [String] = []
        for (type, records) in grouped {
            lines.append("• \(friendlyName(for: type))")
            for r in records.prefix(limitPerType) {
                let title = r.displayName
                let date  = DateFormatter.localizedString(from: r.endDate, dateStyle: .medium, timeStyle: .none)
                var snippet = ""
                if let data = r.fhirResource?.data,
                   let json = String(data: data, encoding: .utf8) {
                    let oneLine = json.replacingOccurrences(of: "\n", with: " ")
                    snippet = String(oneLine.prefix(180))
                }
                lines.append(snippet.isEmpty ? "   - \(title) (\(date))"
                                             : "   - \(title) (\(date)) – \(snippet)…")
            }
        }

        return """
        [Apple Health — Clinical Records]
        \(lines.joined(separator: "\n"))
        [/Apple Health — Clinical Records]
        """
    }

    // MARK: - Helpers

    private func fetchRecords(for type: HKClinicalType) async throws -> [HKClinicalRecord] {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[HKClinicalRecord], Error>) in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: HKObjectQueryNoLimit, sortDescriptors: sort) {
                _, samples, error in
                if let error { cont.resume(throwing: error); return }
                cont.resume(returning: samples as? [HKClinicalRecord] ?? [])
            }
            self.healthStore.execute(query)
        }
    }

    private func friendlyName(for type: HKClinicalType) -> String {
        let raw = type.identifier
        if let r = raw.split(separator: ".").last {
            return r.replacingOccurrences(of: "HKClinicalTypeIdentifier", with: "")
        }
        return raw
    }
}

