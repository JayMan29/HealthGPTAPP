//
// This source file is part of the Stanford HealthGPT project
// SPDX-FileCopyrightText: 2024 Stanford University & Project Contributors
// SPDX-License-Identifier: MIT
//

import SwiftUI
import SpeziOnboarding


struct LLMSourceSelection: View {
    @Environment(OnboardingNavigationPath.self) private var onboardingNavigationPath

    // Store the raw value persistently
    @AppStorage(StorageKeys.llmSource) private var llmSourceRaw: String = StorageKeys.Defaults.llmSource

    // Temporary local binding for UI (avoids computed setter issues)
    @State private var selectedLLMSource: LLMSource = .local

    var body: some View {
        OnboardingView(
            contentView: {
                VStack {
                    OnboardingTitleView(
                        title: "LLM_SOURCE_SELECTION_TITLE",
                        subtitle: "LLM_SOURCE_SELECTION_SUBTITLE"
                    )
                    Spacer()
                    sourceSelector
                    Spacer()
                }
            },
            actionView: {
                OnboardingActionsView("LLM_SOURCE_SELECTION_BUTTON") {
                    // Save to persistent storage
                    llmSourceRaw = selectedLLMSource.rawValue
                    onboardingNavigationPath.append(customView: LLMLocalDownload())
                }
            }
        )
        .onAppear {
            // Load the persisted value when the view appears
            selectedLLMSource = LLMSource(rawValue: llmSourceRaw) ?? .local
        }
    }

    private var sourceSelector: some View {
        Picker("LLM_SOURCE_PICKER_LABEL", selection: $selectedLLMSource) {
            ForEach(LLMSource.allCases) { source in
                Text(source.localizedDescription)
                    .tag(source)
            }
        }
        .pickerStyle(.inline)
        .accessibilityIdentifier("llmSourcePicker")
    }
}

#Preview {
    LLMSourceSelection()
}

