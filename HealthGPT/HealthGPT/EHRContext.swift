//
//  EHRContext.swift
//  HealthGPT
//

import Foundation

/// Minimal context built from MyChart/Epic FHIR data and passed into the system prompt.
struct EHRContext {
    var patientName: String? = nil
    var ageYears: Int? = nil
    var sex: String? = nil
    var lastUpdated: Date? = nil

    var problems: [String] = []
    var medications: [String] = []
    var allergies: [String] = []
    var vitals: [String] = []      // e.g., "Blood Pressure 120/80 mmHg 2025-08-10"
    var labs: [String] = []        // e.g., "A1C 6.2 % 2025-08-01"
    var recentNotes: [String] = [] // e.g., "Discharge Summary – 2025-07-28"
}

extension EHRContext {
    /// Formats the EHR context as a block you can append to the system prompt.
    func asPromptBlock() -> String {
        var out = [String]()
        if let n = patientName { out.append("Patient: \(n)") }
        if let a = ageYears { out.append("Age: \(a)") }
        if let s = sex { out.append("Sex: \(s)") }
        if let t = lastUpdated {
            let df = ISO8601DateFormatter()
            out.append("EHR Last Updated: \(df.string(from: t))")
        }
        if !problems.isEmpty { out.append("Problems: " + problems.joined(separator: "; ")) }
        if !medications.isEmpty { out.append("Medications: " + medications.joined(separator: "; ")) }
        if !allergies.isEmpty { out.append("Allergies: " + allergies.joined(separator: "; ")) }
        if !vitals.isEmpty { out.append("Recent Vitals: " + vitals.joined(separator: " | ")) }
        if !labs.isEmpty { out.append("Recent Labs: " + labs.joined(separator: " | ")) }
        if !recentNotes.isEmpty { out.append("Recent Notes: " + recentNotes.prefix(5).joined(separator: " | ")) }
        return out.joined(separator: "\n")
    }
}

