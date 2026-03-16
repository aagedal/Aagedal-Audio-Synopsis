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
    @Published var modelLoadFraction: Double = 0

    // MARK: - Private Properties

    private var modelContainer: ModelContainer?
    private let modelManager: ModelManager
    private var loadedModelId: String?

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
                    self.modelLoadFraction = progress.fractionCompleted
                    self.modelLoadProgress = "Loading model: \(Int(progress.fractionCompleted * 100))%"
                }
            }

            modelContainer = container
            loadedModelId = modelId
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
        loadedModelId = nil
        isModelLoaded = false
        modelLoadProgress = ""
        modelLoadFraction = 0
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
            // Check if chunked summarization is needed
            let contextWindow = ModelMetadata.contextWindowForCurrentModel()
            let maxOutputTokens = ModelSettings.maxOutputTokens
            let inputBudget = Int(Double(contextWindow) * 0.8) - maxOutputTokens
            let estimatedInputTokens = transcription.count / 4

            if estimatedInputTokens > inputBudget {
                Logger.info("Transcript exceeds context budget (\(estimatedInputTokens) est. tokens vs \(inputBudget) budget), using chunked summarization", category: Logger.processing)
                result = await summarizeChunked(transcription: transcription, notes: notes, charBudget: inputBudget * 4)
            } else {
                result = await summarizeWithMLX(transcription: transcription, notes: notes)
            }
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

    /// Returns a language instruction to append to the system prompt, or empty string for auto
    private static func languageInstruction() -> String {
        let lang = ModelSettings.summarizationLanguage
        if lang == "auto" {
            return " Write your summary in the same language as the user's notes if provided, otherwise match the language of the transcript."
        }
        return " Write your summary in \(lang)."
    }

    // MARK: - MLX Summarization

    private func summarizeWithMLX(transcription: String, notes: String = "") async -> String? {
        progress = "Loading model..."

        // Unload stale model if user switched models in Settings
        let currentModelId = ModelSettings.selectedMLXModel
        if modelContainer != nil && loadedModelId != currentModelId {
            Logger.info("MLX model changed from \(loadedModelId ?? "nil") to \(currentModelId), reloading", category: Logger.processing)
            unloadModel()
        }

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
        systemPrompt += Self.languageInstruction()
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

        let maxTokens = ModelSettings.maxOutputTokens

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

    // MARK: - Chunked Summarization

    private func summarizeChunked(transcription: String, notes: String, charBudget: Int) async -> String? {
        // Split transcript into chunks at line boundaries
        let lines = transcription.components(separatedBy: "\n")
        var chunks: [String] = []
        var currentChunk = ""

        for line in lines {
            if !currentChunk.isEmpty && (currentChunk.count + line.count + 1) > charBudget {
                chunks.append(currentChunk)
                currentChunk = line
            } else {
                if !currentChunk.isEmpty { currentChunk += "\n" }
                currentChunk += line
            }
        }
        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        let totalParts = chunks.count
        Logger.info("Splitting transcript into \(totalParts) chunks for summarization", category: Logger.processing)

        // Summarize each chunk
        var chunkSummaries: [String] = []
        for (index, chunk) in chunks.enumerated() {
            progress = "Summarizing part \(index + 1) of \(totalParts)..."
            let notesForChunk = index == 0 ? notes : ""
            guard let summary = await summarizeWithMLX(transcription: chunk, notes: notesForChunk) else {
                Logger.error("Chunk \(index + 1) summarization failed", category: Logger.processing)
                return nil
            }
            chunkSummaries.append(summary)
        }

        // Final merge pass
        if chunkSummaries.count == 1 {
            return chunkSummaries[0]
        }

        progress = "Merging summaries..."
        let combined = chunkSummaries.enumerated()
            .map { "Part \($0.offset + 1):\n\($0.element)" }
            .joined(separator: "\n\n")

        let mergeTranscription = "The following are summaries of consecutive parts of a long meeting. Please merge them into a single cohesive summary:\n\n\(combined)"
        return await summarizeWithMLX(transcription: mergeTranscription, notes: "")
    }

    // MARK: - Apple Intelligence Summarization

    private func summarizeWithAppleIntelligence(transcription: String, notes: String = "") async -> String? {
        progress = "Summarizing with Apple Intelligence..."

        let systemPrompt = ModelSettings.summarizationSystemPrompt + Self.languageInstruction()
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
