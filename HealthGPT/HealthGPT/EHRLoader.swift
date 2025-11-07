// EHRFromHealthLoader.swift
// HealthGPT

import Foundation
import SpeziChat

@MainActor
final class EHRFromHealthLoader: ObservableObject {
    @Published var isLoading = false
    @Published var lastError: String?

    func loadFromHealthAppAndInject(healthDataInterpreter: HealthDataInterpreter) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        // Use your existing HealthDataFetcher’s clinical APIs
        let fetcher = HealthDataFetcher()

        do {
            let text = try await fetcher.fetchClinicalRecordsPlainText(limitPerType: 20)
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                lastError = "No clinical records were found in Apple Health."
                return
            }

            guard let llm = healthDataInterpreter.llm else {
                lastError = "LLM is not initialized."
                return
            }

            // Inject as assistant/system-style context (not a user message)
            llm.context.chat.append(
                ChatEntity(
                    role: .assistant,
                    content:
"""
[EHR Context – from Apple Health (Clinical Records)]
\(trimmed)
[/EHR Context]
"""
                )
            )
        } catch {
            lastError = "Failed to read clinical records: \(error.localizedDescription)"
        }
    }
}

