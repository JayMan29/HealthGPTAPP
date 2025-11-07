//
//  HealthGPTApplication.swift
//

import Spezi
import SwiftUI

@main
struct HealthGPTApplication: App {
    @UIApplicationDelegateAdaptor(HealthGPTAppDelegate.self) var appDelegate
    @AppStorage(StorageKeys.onboardingFlowComplete) private var completedOnboardingFlow = false

    var body: some Scene {
        WindowGroup {
            Group {
                if completedOnboardingFlow {
                    HealthGPTView()
                } else {
                    EmptyView()
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { !completedOnboardingFlow },
                    set: { presented in completedOnboardingFlow = !presented }
                )
            ) {
                OnboardingFlow()
            }
            // Removed: OAuth/MyChart deep-link handler
            // Removed: URL scheme debug printing (no longer needed)
            .testingSetup()
            .spezi(appDelegate)
        }
    }
}

