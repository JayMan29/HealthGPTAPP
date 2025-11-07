//
// This source file is part of the Stanford HealthGPT project
//
// SPDX-FileCopyrightText: 2024 Stanford University & Project Contributors
// SPDX-License-Identifier: MIT
//

import Foundation

/// Keys and default values used for persistent app storage (via `@AppStorage` or `UserDefaults`)
enum StorageKeys {
    
    // MARK: - Defaults
    
    /// Default values used when initializing `@AppStorage`
    enum Defaults {
        /// Default LLM source (as raw string, since enum values can’t be stored directly)
        static let llmSource = "local"
        
        /// Whether text-to-speech is enabled by default
        static let enableTextToSpeech = false
    }
    
    // MARK: - AppStorage keys
    
    /// Has the onboarding flow been completed?
    static let onboardingFlowComplete = "onboardingFlow.complete"
    
    /// What step of onboarding is currently active?
    static let onboardingFlowStep = "onboardingFlow.step"
    
    /// The source of the LLM (stored as string: "local")
    static let llmSource = "llmsource"
    
    /// Whether speech synthesis is enabled
    static let enableTextToSpeech = "settings.enableTextToSpeech"
}

