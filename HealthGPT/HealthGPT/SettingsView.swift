//
//  SettingsView.swift
//  HealthGPT
//

import OSLog
import SpeziChat
import SwiftUI

struct SettingsView: View {
    @State private var path = NavigationPath()
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthDataInterpreter.self) private var healthDataInterpreter

    @AppStorage(StorageKeys.llmSource)
    private var llmSourceRaw: String = StorageKeys.Defaults.llmSource

    private var llmSource: LLMSource {
        get { LLMSource(rawValue: llmSourceRaw) ?? .local }
        set { llmSourceRaw = newValue.rawValue }
    }

    private let logger = Logger(subsystem: "HealthGPT", category: "Settings")

    var body: some View {
        NavigationStack(path: $path) {
            List {
                chatSection
                connectionsSection
                disclaimerSection
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .accessibilityIdentifier("settingsList")
        }
    }

    // MARK: - Sections

    private var chatSection: some View {
        Section("Chat") {
            Button("Reset Conversation") {
                Task {
                    await healthDataInterpreter.resetChat()
                    dismiss()
                }
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityIdentifier("resetButton")
        }
    }

    private var connectionsSection: some View {
        Section("Connections") {
            Text("Medical Records are read from the Apple Health app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("To add providers (e.g., MyChart), open Health → Browse → Health Records → Add Account, then grant this app access.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var disclaimerSection: some View {
        Section("Disclaimer") {
            VStack(alignment: .leading, spacing: 8) {
                Text("HealthGPT is an educational companion and is not a substitute for professional medical advice, diagnosis, or treatment.")
                Text("Always seek the advice of a physician or other qualified health provider with any questions you may have regarding a medical condition.")
                Text("If you think you may have a medical emergency, call emergency services immediately.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .accessibilityIdentifier("disclaimerText")
        }
    }
}

