//
// This source file is part of the Stanford HealthGPT project
//
// SPDX-FileCopyrightText: 2023 Stanford University & Project Contributors
//
// SPDX-License-Identifier: MIT
//

import Foundation

/// Optional container you can populate from MyChart/Epic (put this in its own file if you prefer).

/// Builds the system prompt for HealthGPT from HealthKit data and (optionally) EHR context.
class PromptGenerator {
    private let healthData: [HealthData]
    private let ehrContext: EHRContext?

    /// Pass EHR context when you have it (from MyChart). It’s optional.
    init(with healthData: [HealthData], ehrContext: EHRContext? = nil) {
        self.healthData = healthData
        self.ehrContext = ehrContext
    }

    func buildMainPrompt() -> String {
        let today = DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .none)

        var prompt = """
        You are HealthGPT, a knowledgeable and compassionate health assistant. You can:
        • Answer general health questions in simple, supportive language.
        • Translate complex medical terms, diagnoses, and test results into plain English.
        • Provide context and possible next steps for lab values and medical instructions.
        • Offer insight based on the user’s recent health data.

        Safety & tone:
        • Do not diagnose or prescribe. Avoid definitive medical advice.
        • Avoid exact statistics unless absolutely necessary.
        • If unsure or if symptoms are serious, suggest contacting a clinician.
        • Be concise, clear, supportive, and non-judgmental.

        Today is \(today). You do not have access to today’s data.
        """

        // Append EHR context if available
        if let ehr = ehrContext {
            prompt += "\n\nInformation from the patient’s electronic health record (EHR):\n"
            if let name = ehr.patientName, !name.isEmpty {
                prompt += "• Name: \(name)\n"
            }
            if let age = ehr.ageYears {
                prompt += "• Age: \(age) years\n"
            }
            if let sex = ehr.sex, !sex.isEmpty {
                prompt += "• Sex: \(sex)\n"
            }
            if !ehr.problems.isEmpty {
                prompt += "• Problems: \(joinList(ehr.problems))\n"
            }
            if !ehr.medications.isEmpty {
                prompt += "• Medications: \(joinList(ehr.medications))\n"
            }
            if !ehr.allergies.isEmpty {
                prompt += "• Allergies: \(joinList(ehr.allergies))\n"
            }
            if !ehr.vitals.isEmpty {
                prompt += "• Vitals: \(joinList(ehr.vitals))\n"
            }
            if !ehr.labs.isEmpty {
                prompt += "• Labs: \(joinList(ehr.labs))\n"
            }
            if !ehr.recentNotes.isEmpty {
                prompt += "• Recent Notes: \(ehr.recentNotes.joined(separator: " | "))\n"
            }
        }

        // Append 14-day HealthKit summary (safe if fewer than 14 items)
        prompt += "\n\nSummary of health metrics from the past 14 days (0 = no entry that day):\n"
        prompt += buildFourteenDaysHealthDataPrompt()

        return prompt
    }

    // MARK: - Health data formatting

    private func buildFourteenDaysHealthDataPrompt() -> String {
        guard !healthData.isEmpty else { return "No recent health data available.\n" }

        // Use the most recent up to 14 items (assumes array is already most-recent-first or in the order you want)
        let slice = Array(healthData.suffix(14))
        var lines: [String] = []
        for dayData in slice {
            lines.append("\(dayData.date): \(buildOneDayHealthDataPrompt(with: dayData))")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func buildOneDayHealthDataPrompt(with dayData: HealthData) -> String {
        var parts: [String] = []
        if let steps = dayData.steps { parts.append("\(Int(steps)) steps") }
        if let sleepHours = dayData.sleepHours { parts.append("\(Int(sleepHours)) hours of sleep") }
        if let activeEnergy = dayData.activeEnergy { parts.append("\(Int(activeEnergy)) calories burned") }
        if let exerciseMinutes = dayData.exerciseMinutes { parts.append("\(Int(exerciseMinutes)) minutes of exercise") }
        if let bodyWeight = dayData.bodyWeight { parts.append("\(bodyWeight) lbs body weight") }
        return parts.isEmpty ? "No entries" : parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    /// Nicely joins an array for one line in the prompt.
    private func joinList(_ items: [String], maxItems: Int = 12) -> String {
        if items.count <= maxItems { return items.joined(separator: ", ") }
        let head = items.prefix(maxItems).joined(separator: ", ")
        return "\(head), … (+\(items.count - maxItems) more)"
    }
}

