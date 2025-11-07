//
//  HealthGPTView.swift
//  HealthGPT
//

import SpeziChat
import SpeziLLM
import SpeziLLMLocal
import SwiftUI
import UniformTypeIdentifiers
import PDFKit

struct HealthGPTView: View {
    @AppStorage(StorageKeys.onboardingFlowComplete) private var completedOnboardingFlow = false
    @AppStorage(StorageKeys.llmSource) private var llmSourceRaw: String = StorageKeys.Defaults.llmSource

    private var llmSource: LLMSource {
        get { LLMSource(rawValue: llmSourceRaw) ?? .local }
        set { llmSourceRaw = newValue.rawValue }
    }

    @Environment(HealthDataInterpreter.self) private var healthDataInterpreter

    // Health Records (from Apple Health)
    @StateObject private var healthEHRLoader = EHRFromHealthLoader()
    @State private var showEHRError = false

    // UI state
    @State private var showSettings = false
    @State private var showErrorAlert = false
    @State private var errorMessage = ""
    @State private var showingFileImporter = false
    @State private var selectedPDF: URL? = nil
    @State private var isExtracting = false

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("WELCOME_TITLE")
                .toolbar {
                    // Settings
                    ToolbarItem(placement: .primaryAction) { settingsButton }

                    // Reset chat
                    ToolbarItem(placement: .primaryAction) { resetChatButton }

                    // Upload PDF
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button {
                            showingFileImporter = true
                        } label: {
                            Image(systemName: "doc.fill.badge.plus")
                        }
                        .accessibilityIdentifier("uploadPDFButton")
                        .help("Upload and analyze a PDF file")
                    }

                    // Import Health Records from Apple Health
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task {
                                await healthEHRLoader.loadFromHealthAppAndInject(healthDataInterpreter: healthDataInterpreter)
                                if let err = healthEHRLoader.lastError {
                                    errorMessage = err
                                    showEHRError = true
                                } else {
                                    await healthDataInterpreter.queryLLM() // async call; keep await
                                }
                            }
                        } label: {
                            if healthEHRLoader.isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "heart.text.square")
                            }
                        }
                        .accessibilityIdentifier("importHealthRecordsButton")
                        .help("Import clinical records from the Apple Health app into the chat")
                    }

                    // Stop generation (cancel) — not async, so no await
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { @MainActor in
                                healthDataInterpreter.cancelGeneration()
                            }
                        } label: {
                            Image(systemName: healthDataInterpreter.llm?.state == .generating
                                  ? "xmark.circle.fill"
                                  : "xmark.circle")
                                .foregroundStyle(healthDataInterpreter.llm?.state == .generating ? .primary : .secondary)
                        }
                        .disabled(healthDataInterpreter.llm?.state != .generating)
                        .accessibilityIdentifier("stopButton")
                        .help("Stop the current AI response")
                    }
                }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack { SettingsView() }
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .alert("Health Records Error", isPresented: $showEHRError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleFileImportResult(result)
        }
        .task {
            await prepareLLMIfNeeded()
        }
    }

    // MARK: - Main Content
    @ViewBuilder
    private var content: some View {
        if let llm = healthDataInterpreter.llm {
            chatArea(llm: llm)
        } else {
            loadingChatView
        }
    }

    // MARK: - Chat Area
    @ViewBuilder
    private func chatArea(llm: any LLMSession) -> some View {
        let chatBinding = makeChatBinding(for: llm)
        VStack(spacing: 8) {
            ChatView(chatBinding, exportFormat: .text)
                .textSelection(.disabled)

            if isExtracting {
                ProgressView("Extracting text from PDF…")
                    .padding(.bottom)
            }
        }
    }

    // MARK: - Chat Binding
    private func makeChatBinding(for llm: any LLMSession) -> Binding<Chat> {
        Binding<Chat>(
            get: { llm.context.chat },
            set: { newValue in
                llm.context.chat = newValue
                if let last = newValue.last,
                   last.role == .user,
                   !isExtracting,
                   healthDataInterpreter.llm?.state != .generating {
                    Task { await healthDataInterpreter.queryLLM() } // async; keep await
                }
            }
        )
    }

    // MARK: - Toolbar Buttons
    private var settingsButton: some View {
        Button {
            Task { @MainActor in showSettings = true }
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityIdentifier("settingsButton")
    }

    private var resetChatButton: some View {
        Button {
            Task { await healthDataInterpreter.resetChat() } // async; keep await
            selectedPDF = nil
        } label: {
            Image(systemName: "arrow.counterclockwise")
        }
        .accessibilityIdentifier("resetChatButton")
    }

    // MARK: - Loading View
    private var loadingChatView: some View {
        VStack {
            Text("Initializing Chat…")
            ProgressView()
        }
    }

    // MARK: - PDF Handling
    private func handleFileImportResult(_ result: Result<[URL], Error>) {
        do {
            guard let file = try result.get().first else { return }
            selectedPDF = file

            let name = file.lastPathComponent
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let sizeString = ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)

            if let llm = healthDataInterpreter.llm {
                Task { @MainActor in
                    llm.context.chat.append(ChatEntity(role: .user, content: "📄 Uploaded: \(name) (\(sizeString))"))
                }
            }

            isExtracting = true
            Task.detached(priority: .userInitiated) {
                guard file.startAccessingSecurityScopedResource() else {
                    await MainActor.run { showError("Failed to access selected file.") }
                    return
                }
                defer { file.stopAccessingSecurityScopedResource() }

                let extracted = await PDFTextExtractor.extractText(from: file)
                await MainActor.run { isExtracting = false }

                guard let text = extracted, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    await MainActor.run { showError("No readable text found in PDF.") }
                    return
                }

                await MainActor.run {
                    healthDataInterpreter.llm?.context.chat.append(
                        ChatEntity(role: .user, content: "📄 Extracted PDF text:\n\n\(text)")
                    )
                }

                await healthDataInterpreter.queryLLM() // async; keep await
            }
        } catch {
            showError("PDF import failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Error Handling
    private func showError(_ message: String) {
        errorMessage = message
        showErrorAlert = true
    }

    // MARK: - LLM Initialization
    private func prepareLLMIfNeeded() async {
        do {
            if FeatureFlags.mockMode {
                try await healthDataInterpreter.prepareLLM(with: LLMMockSchema())
            } else if FeatureFlags.localLLM || llmSource == .local {
                // SpeziLLMLocal schema supports only `model:` in this initializer
                try await healthDataInterpreter.prepareLLM(
                    with: LLMLocalSchema(model: .llama3_8B_4bit)
                )
            }
        } catch {
            showErrorAlert = true
            errorMessage = "Error preparing LLM: \(error.localizedDescription)"
        }
    }
}

