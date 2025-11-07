//
//  HealthDataFetcher+Process.swift
//

import Foundation

extension HealthDataFetcher {
    /// Fetches and processes health data for the last 14 days.
    func fetchAndProcessHealthData() async -> [HealthData] {
        let calendar = Calendar.current
        let today = Date()

        // Build 14 dates (oldest → newest)
        var days: [Date] = []
        for delta in stride(from: 14, through: 1, by: -1) {
            if let d = calendar.date(byAdding: .day, value: -delta, to: today) {
                days.append(d)
            }
        }

        var rows: [HealthData] = days.map {
            HealthData(date: DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .none))
        }

        // Fetch in parallel
        async let stepCounts    = fetchLastTwoWeeksStepCount()
        async let sleepHours    = fetchLastTwoWeeksSleep()
        async let calories      = fetchLastTwoWeeksActiveEnergy()
        async let exercise      = fetchLastTwoWeeksExerciseTime()
        async let bodyMass      = fetchLastTwoWeeksBodyWeight()
        async let heartRate     = fetchLastTwoWeeksHeartRate()

        let s  = try? await stepCounts
        let sl = try? await sleepHours
        let c  = try? await calories
        let ex = try? await exercise
        let bm = try? await bodyMass
        let hr = try? await heartRate

        // Safely assign if arrays are present and long enough
        for i in rows.indices {
            if let s,  i < s.count  { rows[i].steps          = s[i] }
            if let sl, i < sl.count { rows[i].sleepHours     = sl[i] }
            if let c,  i < c.count  { rows[i].activeEnergy   = c[i] }
            if let ex, i < ex.count { rows[i].exerciseMinutes = ex[i] }
            if let bm, i < bm.count { rows[i].bodyWeight     = bm[i] }
            if let hr, i < hr.count { rows[i].heartRate      = hr[i] }
        }

        return rows
    }
}

