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
        static let transcriptionLanguage = "transcriptionLanguage"
        static let insertTimecodeInNotes = "insertTimecodeInNotes"
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

    // MARK: - Notes

    /// Whether to auto-insert timecodes when pressing Enter in notes during recording
    static var insertTimecodeInNotes: Bool {
        get {
            if defaults.object(forKey: Keys.insertTimecodeInNotes) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.insertTimecodeInNotes)
        }
        set {
            defaults.set(newValue, forKey: Keys.insertTimecodeInNotes)
        }
    }

    // MARK: - Transcription Language

    /// Language code for Whisper transcription (e.g. "auto", "en", "no")
    static var transcriptionLanguage: String {
        get {
            defaults.string(forKey: Keys.transcriptionLanguage) ?? "auto"
        }
        set {
            defaults.set(newValue, forKey: Keys.transcriptionLanguage)
            Logger.info("Transcription language: \(newValue)", category: Logger.general)
        }
    }

    /// Supported Whisper languages with display names
    static let whisperLanguages: [(code: String, name: String)] = [
        ("auto", "Auto-detect"),
        ("en", "English"),
        ("zh", "Chinese"),
        ("de", "German"),
        ("es", "Spanish"),
        ("ru", "Russian"),
        ("ko", "Korean"),
        ("fr", "French"),
        ("ja", "Japanese"),
        ("pt", "Portuguese"),
        ("tr", "Turkish"),
        ("pl", "Polish"),
        ("ca", "Catalan"),
        ("nl", "Dutch"),
        ("ar", "Arabic"),
        ("sv", "Swedish"),
        ("it", "Italian"),
        ("id", "Indonesian"),
        ("hi", "Hindi"),
        ("fi", "Finnish"),
        ("vi", "Vietnamese"),
        ("he", "Hebrew"),
        ("uk", "Ukrainian"),
        ("el", "Greek"),
        ("ms", "Malay"),
        ("cs", "Czech"),
        ("ro", "Romanian"),
        ("da", "Danish"),
        ("hu", "Hungarian"),
        ("ta", "Tamil"),
        ("no", "Norwegian"),
        ("th", "Thai"),
        ("ur", "Urdu"),
        ("hr", "Croatian"),
        ("bg", "Bulgarian"),
        ("lt", "Lithuanian"),
        ("la", "Latin"),
        ("mi", "Maori"),
        ("ml", "Malayalam"),
        ("cy", "Welsh"),
        ("sk", "Slovak"),
        ("te", "Telugu"),
        ("fa", "Persian"),
        ("lv", "Latvian"),
        ("bn", "Bengali"),
        ("sr", "Serbian"),
        ("az", "Azerbaijani"),
        ("sl", "Slovenian"),
        ("kn", "Kannada"),
        ("et", "Estonian"),
        ("mk", "Macedonian"),
        ("br", "Breton"),
        ("eu", "Basque"),
        ("is", "Icelandic"),
        ("hy", "Armenian"),
        ("ne", "Nepali"),
        ("mn", "Mongolian"),
        ("bs", "Bosnian"),
        ("kk", "Kazakh"),
        ("sq", "Albanian"),
        ("sw", "Swahili"),
        ("gl", "Galician"),
        ("mr", "Marathi"),
        ("pa", "Punjabi"),
        ("si", "Sinhala"),
        ("km", "Khmer"),
        ("sn", "Shona"),
        ("yo", "Yoruba"),
        ("so", "Somali"),
        ("af", "Afrikaans"),
        ("oc", "Occitan"),
        ("ka", "Georgian"),
        ("be", "Belarusian"),
        ("tg", "Tajik"),
        ("sd", "Sindhi"),
        ("gu", "Gujarati"),
        ("am", "Amharic"),
        ("yi", "Yiddish"),
        ("lo", "Lao"),
        ("uz", "Uzbek"),
        ("fo", "Faroese"),
        ("ht", "Haitian Creole"),
        ("ps", "Pashto"),
        ("tk", "Turkmen"),
        ("nn", "Nynorsk"),
        ("mt", "Maltese"),
        ("sa", "Sanskrit"),
        ("lb", "Luxembourgish"),
        ("my", "Myanmar"),
        ("bo", "Tibetan"),
        ("tl", "Tagalog"),
        ("mg", "Malagasy"),
        ("as", "Assamese"),
        ("tt", "Tatar"),
        ("haw", "Hawaiian"),
        ("ln", "Lingala"),
        ("ha", "Hausa"),
        ("ba", "Bashkir"),
        ("jw", "Javanese"),
        ("su", "Sundanese"),
    ]

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
        defaults.removeObject(forKey: Keys.transcriptionLanguage)
        defaults.removeObject(forKey: Keys.insertTimecodeInNotes)
        Logger.info("Model settings reset", category: Logger.general)
    }
}
