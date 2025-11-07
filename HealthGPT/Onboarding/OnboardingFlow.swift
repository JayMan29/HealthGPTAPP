//
// This source file is part of the Stanford HealthGPT project
//
// SPDX-FileCopyrightText: 2023 Stanford University & Project Contributors
//
// SPDX-License-Identifier: MIT
//

import HealthKit
import SpeziOnboarding
import SwiftUI


/// Displays a multi-step onboarding flow for the HealthGPT Application.
struct OnboardingFlow: View {
    @AppStorage(StorageKeys.onboardingFlowComplete) private var completedOnboardingFlow = false
    @AppStorage(StorageKeys.llmSource) private var llmSourceRaw: String = StorageKeys.Defaults.llmSource

    private var llmSource: LLMSource {
        get { LLMSource(rawValue: llmSourceRaw) ?? .local }
        set { llmSourceRaw = newValue.rawValue }
    }

    var body: some View {
        OnboardingStack(onboardingFlowComplete: $completedOnboardingFlow) {
            Welcome()
            Disclaimer()
            
            if llmSource == .local {
                LLMLocalDownload()
            } else {
                LLMSourceSelection()
            }
            
            if HKHealthStore.isHealthDataAvailable() {
                HealthKitPermissions()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(!completedOnboardingFlow)
    }
}


#if DEBUG
struct OnboardingFlow_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlow()
    }
}
#endif

