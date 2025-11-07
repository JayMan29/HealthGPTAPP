//
//  HealthDataInterpreter.swift
//

import Foundation
import Spezi
import SpeziChat
import SpeziLLM
import SpeziLLMLocal
import SpeziSpeechSynthesizer
import QuartzCore          // CACurrentMediaTime()
import UIKit               // memory warning & thermal integration

@Observable
class HealthDataInterpreter: DefaultInitializable, Module, EnvironmentAccessible {
    // DI
    @ObservationIgnored @Dependency(LLMRunner.self) private var llmRunner
    @ObservationIgnored @Dependency(HealthDataFetcher.self) private var healthDataFetcher

    // Active session
    var llm: (any LLMSession)?

    // System prompt cache
    @ObservationIgnored private var systemPrompt = ""

    // Run state
    @ObservationIgnored private var isGenerating = false
    @ObservationIgnored private var generationTask: Task<Void, Never>? = nil

    // UI streaming tunables
    @ObservationIgnored private let flushEverySeconds: CFTimeInterval = 0.05  // ~20fps batching
    @ObservationIgnored private let flushMinChars: Int = 64                   // batch tokens

    // Context / memory limits
    @ObservationIgnored private let maxAssistantChars: Int = 16_000           // cap assistant text in context
    @ObservationIgnored private let keepLastMessages: Int = 12                // keep last N turns

    // System pressure safeguards
    @ObservationIgnored private var memoryWarningObserver: NSObjectProtocol?
    @ObservationIgnored private var thermalTimer: Timer?

    // MARK: - Lifecycle

    required init() {
        // Cancel if iOS reports memory pressure
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            print("⚠️ Memory warning — canceling generation.")
            Task { @MainActor in self?.cancelGeneration() }
        }

        // Check thermal state periodically; cancel if too hot
        thermalTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                print("🔥 Thermal state \(state.rawValue) — canceling generation.")
                Task { @MainActor in self?.cancelGeneration() }
            }
        }
        if let thermalTimer { RunLoop.main.add(thermalTimer, forMode: .common) }
    }

    deinit {
        if let obs = memoryWarningObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        thermalTimer?.invalidate()
    }

    // MARK: - Setup

    /// Creates an `LLMSession`, injects prompt, and performs local setup.
    @MainActor
    func prepareLLM(with schema: any LLMSchema) async throws {
        let llm = llmRunner(with: schema)

        // Build & inject system prompt
        systemPrompt = await generateSystemPrompt()
        llm.context.reset()
        llm.context.append(systemMessage: systemPrompt)

        // Local model setup (downloads / warms up)
        if let local = llm as? LLMLocalSession {
            try await local.setup()
        }

        self.llm = llm
        debugLog("✅ LLM prepared; system prompt injected (\(systemPrompt.count) chars)")
    }

    // MARK: - Generation (throttled streaming + cancel)

    /// Starts a generation run with throttled UI appends. Safe to call repeatedly.
    @MainActor
    func queryLLM() async {
        guard let llm else {
            debugLog("⚠️ queryLLM called without an active session")
            return
        }
        guard llm.state != .generating, !isGenerating else {
            debugLog("⏳ Skipping query: already generating")
            return
        }

        trimChatIfNeeded()

        isGenerating = true
        debugLog("🚀 Starting generation")

        // Ensure previous task is canceled before starting a new one
        generationTask?.cancel()
        let currentLLM = llm

        generationTask = Task { [weak self] in
            do {
                try await self?.runThrottledStream(llm: currentLLM)
                await MainActor.run {
                    self?.debugLog("✅ Generation completed")
                    self?.isGenerating = false
                    self?.generationTask = nil
                }
            } catch is CancellationError {
                await MainActor.run {
                    self?.debugLog("🛑 Generation canceled")
                    self?.isGenerating = false
                    self?.generationTask = nil
                }
            } catch {
                await MainActor.run {
                    self?.debugLog("🔴 Generation error: \(error.localizedDescription)")
                    self?.isGenerating = false
                    self?.generationTask = nil
                }
            }
        }
    }

    /// Cancels the active generation (if any).
    @MainActor
    func cancelGeneration() {
        guard generationTask != nil else { return }
        generationTask?.cancel()
        generationTask = nil
    }

    /// Streaming loop with token batching to reduce SwiftUI re-render frequency.
    private func runThrottledStream(llm: any LLMSession) async throws {
        let stream = try await llm.generate()

        var buffer = ""
        var lastFlush = CACurrentMediaTime()

        for try await token in stream {
            // Cooperative cancel (memory/thermal/user)
            if Task.isCancelled { throw CancellationError() }

            buffer += token

            let now = CACurrentMediaTime()
            if buffer.count >= flushMinChars || (now - lastFlush) >= flushEverySeconds {
                let chunk = buffer
                buffer.removeAll(keepingCapacity: true)
                lastFlush = now

                await MainActor.run {
                    llm.context.append(assistantOutput: chunk)
                }
            }
        }

        // Flush remaining tail
        if !buffer.isEmpty {
            let tail = buffer
            await MainActor.run {
                llm.context.append(assistantOutput: tail)
            }
        }
    }

    // MARK: - Context Utilities

    /// Clears chat and re-injects the latest system prompt.
    @MainActor
    func resetChat() async {
        systemPrompt = await generateSystemPrompt()
        llm?.context.reset()
        llm?.context.append(systemMessage: systemPrompt)
        debugLog("🧹 Chat reset; system prompt re-injected")
    }

    /// Append a *system* note (e.g., “Uploaded file…”, extracted PDF text).
    @MainActor
    func appendSystemNote(_ text: String) {
        llm?.context.append(systemMessage: text)
        debugLog("📝 Appended system note (\(text.count) chars)")
    }

    /// Keep chat bounded so generations stay fast and memory-friendly.
    @MainActor
    private func trimChatIfNeeded() {
        guard let llm else { return }
        var chat = llm.context.chat

        // Keep only the most recent N messages
        if chat.count > keepLastMessages {
            chat.removeFirst(chat.count - keepLastMessages)
        }

        // Cap total assistant text length
        var totalAssistant = 0
        for i in chat.indices.reversed() where chat[i].role == .assistant {
            totalAssistant += chat[i].content.count
            if totalAssistant > maxAssistantChars {
                chat.removeFirst(i)
                break
            }
        }

        llm.context.chat = chat
    }

    // MARK: - Prompt (Apple Health + Clinical Records / MyChart)

    /// Builds the system prompt including metrics and (if available) Apple Health clinical records (MyChart).
    private func generateSystemPrompt() async -> String {
        // 1) Activity / metrics block
        let healthData = await healthDataFetcher.fetchAndProcessHealthData()
        var prompt = PromptGenerator(with: healthData).buildMainPrompt()

        // 2) Clinical records (quietly skipped if entitlement or data is unavailable)
        if let clinicalBlock = try? await healthDataFetcher.fetchClinicalRecordsPlainText(limitPerType: 20),
           !clinicalBlock.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += "\n\n" + clinicalBlock
        }

        return prompt
    }

    // MARK: - Logging

    private func debugLog(_ message: String) {
        #if DEBUG
        print("[HealthDataInterpreter] \(message)")
        #endif
    }
}

