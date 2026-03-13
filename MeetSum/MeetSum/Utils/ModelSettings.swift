//
//  ModelSettings.swift
//  MeetSum
//
//  UserDefaults wrapper for model preferences
//

import Foundation

/// Which summarization engine to use
enum SummarizationEngine: String, CaseIterable, Identifiable {
    case mlx = "mlx"
    case appleIntelligence = "appleIntelligence"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mlx: return "MLX Model"
        case .appleIntelligence: return "Apple Intelligence"
        }
    }

    var description: String {
        switch self {
        case .mlx: return "On-device MLX model (download required)"
        case .appleIntelligence: return "Built-in Apple Intelligence (no download needed)"
        }
    }
}

/// UserDefaults storage for model preferences
struct ModelSettings {

    private static let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Keys {
        static let modelDirectoryBookmark = "modelDirectoryBookmark"
        static let mlxModelDirectoryBookmark = "mlxModelDirectoryBookmark"
        static let selectedWhisperModel = "selectedWhisperModel"
        static let selectedMLXModel = "selectedMLXModel"
        static let summarizationEngine = "summarizationEngine"
        static let hasCompletedInitialSetup = "hasCompletedInitialSetup"
        static let summarizationSystemPrompt = "summarizationSystemPrompt"
        static let disableModelThinking = "disableModelThinking"
        static let captureSystemAudio = "captureSystemAudio"
        static let captureMicrophone = "captureMicrophone"
    }

    // MARK: - Defaults

    static let defaultSummarizationPrompt = "You are a helpful assistant that summarizes meeting transcriptions. Format your response in Markdown. Provide clear, concise bullet-point summaries that capture key topics, decisions, and action items. Use headings, bold text, and lists for readability."

    // MARK: - Model Directory Bookmark

    static var modelDirectoryBookmark: Data? {
        get {
            defaults.data(forKey: Keys.modelDirectoryBookmark)
        }
        set {
            defaults.set(newValue, forKey: Keys.modelDirectoryBookmark)
            Logger.info("Model directory bookmark saved", category: Logger.general)
        }
    }

    static var mlxModelDirectoryBookmark: Data? {
        get {
            defaults.data(forKey: Keys.mlxModelDirectoryBookmark)
        }
        set {
            defaults.set(newValue, forKey: Keys.mlxModelDirectoryBookmark)
            Logger.info("MLX model directory bookmark saved", category: Logger.general)
        }
    }

    // MARK: - Selected Models

    static var selectedWhisperModel: String {
        get {
            defaults.string(forKey: Keys.selectedWhisperModel) ?? "whisper-base"
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedWhisperModel)
            Logger.info("Selected Whisper model: \(newValue)", category: Logger.general)
        }
    }

    static var selectedMLXModel: String {
        get {
            defaults.string(forKey: Keys.selectedMLXModel) ?? "mlx-community/Qwen3-4B-4bit"
        }
        set {
            defaults.set(newValue, forKey: Keys.selectedMLXModel)
            Logger.info("Selected MLX model: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Summarization Engine

    static var summarizationEngine: SummarizationEngine {
        get {
            if let raw = defaults.string(forKey: Keys.summarizationEngine),
               let engine = SummarizationEngine(rawValue: raw) {
                return engine
            }
            return .appleIntelligence
        }
        set {
            defaults.set(newValue.rawValue, forKey: Keys.summarizationEngine)
            Logger.info("Selected summarization engine: \(newValue.displayName)", category: Logger.general)
        }
    }

    // MARK: - Summarization Prompt

    static var summarizationSystemPrompt: String {
        get {
            defaults.string(forKey: Keys.summarizationSystemPrompt) ?? defaultSummarizationPrompt
        }
        set {
            defaults.set(newValue, forKey: Keys.summarizationSystemPrompt)
        }
    }

    // MARK: - Model Thinking

    /// When enabled, appends /no_think to the system prompt to suppress thinking tokens (Qwen3)
    static var disableModelThinking: Bool {
        get {
            if defaults.object(forKey: Keys.disableModelThinking) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.disableModelThinking)
        }
        set {
            defaults.set(newValue, forKey: Keys.disableModelThinking)
            Logger.info("Disable model thinking: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Audio Capture

    /// Whether to capture microphone audio
    static var captureMicrophone: Bool {
        get {
            if defaults.object(forKey: Keys.captureMicrophone) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.captureMicrophone)
        }
        set {
            defaults.set(newValue, forKey: Keys.captureMicrophone)
            Logger.info("Capture microphone: \(newValue)", category: Logger.general)
        }
    }

    /// Whether to capture system audio (Teams, FaceTime, etc.)
    static var captureSystemAudio: Bool {
        get {
            if defaults.object(forKey: Keys.captureSystemAudio) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.captureSystemAudio)
        }
        set {
            defaults.set(newValue, forKey: Keys.captureSystemAudio)
            Logger.info("Capture system audio: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Setup Status

    static var hasCompletedInitialSetup: Bool {
        get {
            defaults.bool(forKey: Keys.hasCompletedInitialSetup)
        }
        set {
            defaults.set(newValue, forKey: Keys.hasCompletedInitialSetup)
            Logger.info("Initial setup completed: \(newValue)", category: Logger.general)
        }
    }

    // MARK: - Reset

    static func reset() {
        defaults.removeObject(forKey: Keys.modelDirectoryBookmark)
        defaults.removeObject(forKey: Keys.mlxModelDirectoryBookmark)
        defaults.removeObject(forKey: Keys.selectedWhisperModel)
        defaults.removeObject(forKey: Keys.selectedMLXModel)
        defaults.removeObject(forKey: Keys.summarizationEngine)
        defaults.removeObject(forKey: Keys.hasCompletedInitialSetup)
        defaults.removeObject(forKey: Keys.summarizationSystemPrompt)
        defaults.removeObject(forKey: Keys.disableModelThinking)
        defaults.removeObject(forKey: Keys.captureSystemAudio)
        defaults.removeObject(forKey: Keys.captureMicrophone)
        Logger.info("Model settings reset", category: Logger.general)
    }
}
