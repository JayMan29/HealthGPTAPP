//
//  HealthKitPermissions.swift
//

import OSLog
import HealthKit
import SpeziOnboarding
import SwiftUI

struct HealthKitPermissions: View {
    @Environment(OnboardingNavigationPath.self) private var onboardingNavigationPath

    @State private var healthKitProcessing = false
    @State private var stepData: [StepEntry] = []

    private let logger = Logger(subsystem: "HealthGPT", category: "Onboarding")
    private let store = HKHealthStore()

    var body: some View {
        OnboardingView(
            contentView: {
                VStack {
                    OnboardingTitleView(
                        title: "HEALTHKIT_PERMISSIONS_TITLE".moduleLocalized,
                        subtitle: "HEALTHKIT_PERMISSIONS_SUBTITLE".moduleLocalized
                    )
                    Spacer()
                    Image(systemName: "heart.text.square.fill")
                        .accessibilityHidden(true)
                        .font(.system(size: 150))
                        .foregroundColor(.accentColor)

                    Text("HEALTHKIT_PERMISSIONS_DESCRIPTION")
                        .multilineTextAlignment(.center)
                        .padding(.vertical, 16)

                    Spacer()

                    if !stepData.isEmpty {
                        List(stepData) { entry in
                            HStack {
                                Text(entry.date, style: .date)
                                Spacer()
                                Text("\(entry.steps) steps")
                            }
                        }
                        .frame(height: 200)
                    }
                }
            },
            actionView: {
                OnboardingActionsView("HEALTHKIT_PERMISSIONS_BUTTON") {
                    await requestAllPermissionsOneSheet()
                }
                .disabled(healthKitProcessing)
            }
        )
        .navigationBarBackButtonHidden(healthKitProcessing)
        .overlay {
            if healthKitProcessing {
                ZStack {
                    Color.black.opacity(0.1).ignoresSafeArea()
                    ProgressView("Requesting Health permissions…")
                        .padding()
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .transition(.opacity)
            }
        }
    }

    // MARK: - Request permissions (Base types first; clinical optional)

    @MainActor
    private func requestAllPermissionsOneSheet() async {
        #if targetEnvironment(simulator)
        logger.error("HealthKit is limited in Simulator; run on a real device.")
        onboardingNavigationPath.nextStep()
        return
        #endif

        guard HKHealthStore.isHealthDataAvailable() else {
            logger.error("Health data not available on this device.")
            onboardingNavigationPath.nextStep()
            return
        }

        guard !healthKitProcessing else { return }
        healthKitProcessing = true
        defer { healthKitProcessing = false }

        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            onboardingNavigationPath.nextStep()
            return
        }

        // 1) Base HealthKit types
        logger.info("Requesting base HealthKit permissions …")
        do {
            try await requestAuthorizationAsync(toShare: [], read: baseReadTypes())
            logger.info("Base HealthKit authorization completed.")
        } catch {
            logger.error("Base authorization failed: \(error.localizedDescription)")
        }

        // 2) Clinical Health Records (optional)
        #if HAS_HEALTH_RECORDS
        let clinical = clinicalReadTypes()
        if !clinical.isEmpty {
            logger.info("Attempting to request clinical Health Records permissions …")
            do {
                try await requestAuthorizationAsync(toShare: [], read: clinical)
                logger.info("Clinical Health Records authorization completed.")
            } catch {
                logger.error("Clinical authorization failed: \(error.localizedDescription)")
            }
        } else {
            logger.warning("No clinical types available to request.")
        }
        #endif

        // 3) Quick sanity read (steps)
        await fetchStepData()
        onboardingNavigationPath.nextStep()
    }

    // MARK: - Async wrapper for HealthKit auth (safe, no double-resume)

    private func requestAuthorizationAsync(
        toShare share: Set<HKSampleType>,
        read types: Set<HKObjectType>
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: share, read: types) { ok, err in
                if let err { cont.resume(throwing: err); return }
                if ok { cont.resume(returning: ()); return }
                cont.resume(throwing: NSError(
                    domain: "HealthKit",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Authorization was not granted"]
                ))
            }
        }
    }

    // MARK: - Fetch Data

    @MainActor
    private func fetchStepData() async {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else { return }

        let status = store.authorizationStatus(for: stepType)
        guard status == .sharingAuthorized else {
            logger.info("Steps not authorized (status rawValue=\(status.rawValue)).")
            return
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        let endDate = Date()

        do {
            let entries = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[StepEntry], Error>) in
                let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
                let query = HKStatisticsCollectionQuery(
                    quantityType: stepType,
                    quantitySamplePredicate: predicate,
                    options: .cumulativeSum,
                    anchorDate: Calendar.current.startOfDay(for: endDate),
                    intervalComponents: DateComponents(day: 1)
                )
                query.initialResultsHandler = { _, results, error in
                    if let error { continuation.resume(throwing: error); return }
                    guard let results else { continuation.resume(returning: []); return }

                    var items: [StepEntry] = []
                    results.enumerateStatistics(from: startDate, to: endDate) { stat, _ in
                        if let sum = stat.sumQuantity() {
                            let steps = Int(sum.doubleValue(for: HKUnit.count()))
                            items.append(StepEntry(date: stat.startDate, steps: steps))
                        }
                    }
                    continuation.resume(returning: items)
                }
                store.execute(query)
            }

            self.stepData = entries
            logger.info("Fetched \(entries.count) day(s) of step data.")
        } catch {
            logger.error("Failed to fetch steps: \(error.localizedDescription)")
        }
    }

    // MARK: - Types to read

    private func baseReadTypes() -> Set<HKObjectType> {
        var set = Set<HKObjectType>()
        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .appleExerciseTime) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .heartRate) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .bodyMass) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .height) { set.insert(t) }
        if let t = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { set.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { set.insert(t) }
        return set
    }

    private func clinicalReadTypes() -> Set<HKObjectType> {
        var set = Set<HKObjectType>()
        #if HAS_HEALTH_RECORDS
        let ids: [HKClinicalTypeIdentifier] = [
            .allergyRecord,
            .conditionRecord,
            .immunizationRecord,
            .labResultRecord,
            .medicationRecord,
            .procedureRecord
        ]
        for id in ids {
            if let type = HKObjectType.clinicalType(forIdentifier: id) { set.insert(type) }
        }
        if #available(iOS 17.0, *) {
            if let t = HKObjectType.clinicalType(forIdentifier: .vitalSignRecord) { set.insert(t) }
        }
        #endif
        return set
    }
}

// MARK: - Model

struct StepEntry: Identifiable {
    let id = UUID()
    let date: Date
    let steps: Int
}

#if DEBUG
struct HealthKitPermissions_Previews: PreviewProvider {
    static var previews: some View {
        HealthKitPermissions()
    }
}
#endif

