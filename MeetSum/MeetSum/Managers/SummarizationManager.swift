//
//  SummarizationManager.swift
//  MeetSum
//
//  Manages MLX-based and Apple Intelligence summarization
//

import Foundation
import Combine
import MLXLLM
import MLXLMCommon
import FoundationModels

/// Manages summarization using MLX Swift or Apple Intelligence
@MainActor
class SummarizationManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isSummarizing = false
    @Published var progress: String = ""
    @Published var error: Error?
    @Published var isModelLoaded = false
    @Published var modelLoadProgress: String = ""

    // MARK: - Private Properties

    private var modelContainer: ModelContainer?
    private let modelManager: ModelManager

    // MARK: - Initialization

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - Public Methods

    /// Pre-load the MLX model
    func loadModel() async {
        guard modelContainer == nil else {
            isModelLoaded = true
            return
        }

        modelLoadProgress = "Downloading model (this may take a while on first run)..."

        do {
            let modelId = ModelSettings.selectedMLXModel
            let config = ModelConfiguration(id: modelId)
            let container = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                Task { @MainActor in
                    self.modelLoadProgress = "Loading model: \(Int(progress.fractionCompleted * 100))%"
                }
            }

            modelContainer = container
            isModelLoaded = true
            modelLoadProgress = "Model loaded"
            Logger.info("MLX model loaded successfully: \(modelId)", category: Logger.processing)

        } catch {
            Logger.error("Failed to load MLX model", error: error, category: Logger.processing)
            self.error = error
            modelLoadProgress = "Failed to load model"
        }
    }

    /// Unload the current model (for switching models)
    func unloadModel() {
        modelContainer = nil
        isModelLoaded = false
        modelLoadProgress = ""
    }

    /// Generate a summary from transcription text using the selected engine
    func summarize(transcription: String, notes: String = "") async -> String? {
        guard !transcription.isEmpty else {
            Logger.warning("Cannot summarize empty transcription", category: Logger.processing)
            return nil
        }

        let engine = ModelSettings.summarizationEngine

        Logger.info("Starting summarization with \(engine.displayName). Transcription length: \(transcription.count) characters", category: Logger.processing)

        isSummarizing = true
        error = nil

        let result: String?
        switch engine {
        case .mlx:
            result = await summarizeWithMLX(transcription: transcription, notes: notes)
        case .appleIntelligence:
            result = await summarizeWithAppleIntelligence(transcription: transcription, notes: notes)
        }

        isSummarizing = false
        return result
    }

    // MARK: - Prompt Building

    private static func buildUserPrompt(transcription: String, notes: String) -> String {
        if notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Please provide a concise summary of the following meeting transcription:\n\n\(transcription)"
        } else {
            return """
            Please provide a concise summary of the following meeting transcription and user notes:

            Transcript:
            \(transcription)

            User Notes (timestamps correlate with transcript timestamps):
            \(notes)
            """
        }
    }

    // MARK: - MLX Summarization

    private func summarizeWithMLX(transcription: String, notes: String = "") async -> String? {
        progress = "Loading model..."

        // Ensure model is loaded
        if modelContainer == nil {
            await loadModel()
        }

        guard let container = modelContainer else {
            Logger.error("Model failed to load", category: Logger.processing)
            error = NSError(domain: "SummarizationManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load MLX model. Please select and download a model in Settings."])
            return nil
        }

        progress = "Generating summary..."

        var systemPrompt = ModelSettings.summarizationSystemPrompt
        if ModelSettings.disableModelThinking {
            systemPrompt += " /no_think"
        }
        let userContent = Self.buildUserPrompt(transcription: transcription, notes: notes)
        let userInput = UserInput(
            messages: [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userContent]
            ]
        )

        let maxTokens = 2000

        do {
            let result = try await container.perform { context in
                let input = try await context.processor.prepare(input: userInput)

                return try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(temperature: 0.7),
                    context: context
                ) { tokens in
                    if tokens.count >= maxTokens {
                        return .stop
                    }

                    if tokens.count % 20 == 0 {
                        let count = tokens.count
                        Task { @MainActor in
                            self.progress = "Generating summary (\(count) tokens)..."
                        }
                    }

                    return .more
                }
            }

            let summary = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.info("MLX summarization completed. Summary length: \(summary.count) characters", category: Logger.processing)
            progress = "Summary complete"
            return summary

        } catch {
            Logger.error("MLX summarization failed", error: error, category: Logger.processing)
            self.error = error
            progress = ""
            return nil
        }
    }

    // MARK: - Apple Intelligence Summarization

    private func summarizeWithAppleIntelligence(transcription: String, notes: String = "") async -> String? {
        progress = "Summarizing with Apple Intelligence..."

        let systemPrompt = ModelSettings.summarizationSystemPrompt
        let userContent = Self.buildUserPrompt(transcription: transcription, notes: notes)
        let prompt = """
        \(systemPrompt)

        \(userContent)
        """

        do {
            let session = LanguageModelSession()
            let response = try await session.respond(to: prompt)

            let summary = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            Logger.info("Apple Intelligence summarization completed. Summary length: \(summary.count) characters", category: Logger.processing)
            progress = "Summary complete"
            return summary

        } catch {
            Logger.error("Apple Intelligence summarization failed", error: error, category: Logger.processing)
            self.error = error
            progress = ""
            return nil
        }
    }
}
