//
// This source file is part of the Stanford HealthGPT project
//
// SPDX-FileCopyrightText: 2023 Stanford University & Project Contributors
//
// SPDX-License-Identifier: MIT
//

import SpeziOnboarding
import SwiftUI

struct Disclaimer: View {
    @Environment(OnboardingNavigationPath.self) private var onboardingNavigationPath

    var body: some View {
        SequentialOnboardingView(
            title: "Disclaimer",
            subtitle: "Please read this important information before continuing.",
            content: [
                .init(
                    title: "Educational Purposes Only",
                    description: "This app is intended solely for educational use and does not provide medical advice, diagnosis, or treatment."
                ),
                .init(
                    title: "Consult Healthcare Providers",
                    description: "Always consult a qualified healthcare provider for medical concerns. Never delay seeking care because of this app."
                ),
                .init(
                    title: "Data Privacy",
                    description: "All health data processed by this app stays on your device unless explicitly shared by you."
                ),
                .init(
                    title: "Use at Your Own Risk",
                    description: "By continuing, you acknowledge that the app developers are not liable for medical outcomes based on information shown."
                )
            ],
            actionText: "I Understand",
            action: {
                onboardingNavigationPath.nextStep()
            }
        )
    }
}

#if DEBUG
struct Disclaimer_Previews: PreviewProvider {
    static var previews: some View {
        Disclaimer()
    }
}
#endif

