//
//  ModelMetadata.swift
//  MeetSum
//
//  Model definitions for downloadable models
//

import Foundation

/// Type of AI model
enum ModelType: String, Codable {
    case whisper
    case mlx

    var displayName: String {
        switch self {
        case .whisper: return "Whisper (Speech-to-Text)"
        case .mlx: return "MLX (Summarization)"
        }
    }
}

/// Metadata for a downloadable AI model
struct ModelMetadata: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: ModelType
    let filename: String
    let downloadURL: URL
    let sizeBytes: Int64
    let description: String

    /// HuggingFace model ID for MLX models (used by MLXLLM)
    let huggingFaceId: String?

    /// Context window size in tokens (nil for Whisper models)
    let contextWindowTokens: Int?

    var sizeMB: Double {
        Double(sizeBytes) / 1_048_576.0
    }

    var sizeFormatted: String {
        if sizeMB < 1024 {
            return String(format: "%.1f MB", sizeMB)
        } else {
            return String(format: "%.2f GB", sizeMB / 1024.0)
        }
    }

    init(id: String, name: String, type: ModelType, filename: String, downloadURL: URL, sizeBytes: Int64, description: String, huggingFaceId: String? = nil, contextWindowTokens: Int? = nil) {
        self.id = id
        self.name = name
        self.type = type
        self.filename = filename
        self.downloadURL = downloadURL
        self.sizeBytes = sizeBytes
        self.description = description
        self.huggingFaceId = huggingFaceId
        self.contextWindowTokens = contextWindowTokens
    }

    // MARK: - Whisper Models

    static let whisperTiny = ModelMetadata(
        id: "whisper-tiny",
        name: "Whisper Tiny",
        type: .whisper,
        filename: "ggml-tiny.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.bin")!,
        sizeBytes: 77_691_713,
        description: "Fast, lightweight model. Good for quick transcriptions."
    )

    static let whisperBase = ModelMetadata(
        id: "whisper-base",
        name: "Whisper Base",
        type: .whisper,
        filename: "ggml-base.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin")!,
        sizeBytes: 147_964_211,
        description: "Better accuracy than Tiny. Recommended for most users."
    )

    static let whisperSmall = ModelMetadata(
        id: "whisper-small",
        name: "Whisper Small",
        type: .whisper,
        filename: "ggml-small.bin",
        downloadURL: URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin")!,
        sizeBytes: 488_281_415,
        description: "High accuracy. Slower but more accurate transcriptions."
    )

    static let whisperNbSmall = ModelMetadata(
        id: "whisper-nb-small",
        name: "Norwegian Whisper Small",
        type: .whisper,
        filename: "ggml-nb-small.bin",
        downloadURL: URL(string: "https://huggingface.co/NbAiLab/nb-whisper-small/resolve/main/ggml-model.bin")!,
        sizeBytes: 488_281_415,
        description: "Norwegian specific model (Small). Better for Norwegian audio."
    )

    static let whisperNbLarge = ModelMetadata(
        id: "whisper-nb-large",
        name: "Norwegian Whisper Large",
        type: .whisper,
        filename: "ggml-nb-large.bin",
        downloadURL: URL(string: "https://huggingface.co/NbAiLab/nb-whisper-large/resolve/main/ggml-model.bin")!,
        sizeBytes: 3_090_000_000,
        description: "Norwegian specific model (Large). Best accuracy for Norwegian."
    )

    // MARK: - MLX Summarization Models

    static let qwen3_4b_mlx = ModelMetadata(
        id: "qwen3-4b-4bit",
        name: "Qwen3 4B 4-bit",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen3-4B-4bit")!,
        sizeBytes: 2_700_000_000,
        description: "Compact and fast. Good balance of quality and speed. ~3GB memory.",
        huggingFaceId: "mlx-community/Qwen3-4B-4bit",
        contextWindowTokens: 32_768
    )

    static let gptOss20b_mlx = ModelMetadata(
        id: "gpt-oss-20b-mxfp4-q4",
        name: "GPT-OSS 20B MXFP4-Q4",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/gpt-oss-20b-MXFP4-Q4")!,
        sizeBytes: 11_000_000_000,
        description: "High quality summaries. Requires ~12GB memory. Slower but more capable.",
        huggingFaceId: "mlx-community/gpt-oss-20b-MXFP4-Q4",
        contextWindowTokens: 32_768
    )

    static let qwen35_9b_mlx = ModelMetadata(
        id: "qwen3.5-9b-4bit",
        name: "Qwen3.5 9B 4-bit",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/Qwen3.5-9B-MLX-4bit")!,
        sizeBytes: 5_500_000_000,
        description: "Mid-size model. Higher quality than 4B with moderate memory use. ~6GB memory.",
        huggingFaceId: "mlx-community/Qwen3.5-9B-MLX-4bit",
        contextWindowTokens: 131_072
    )

    static let gemma3_12b_mlx = ModelMetadata(
        id: "gemma-3-12b-it-4bit",
        name: "Gemma 3 12B IT 4-bit",
        type: .mlx,
        filename: "",
        downloadURL: URL(string: "https://huggingface.co/mlx-community/gemma-3-12b-it-4bit")!,
        sizeBytes: 7_600_000_000,
        description: "Google's Gemma 3 instruction-tuned. Strong summarization quality. ~8GB memory.",
        huggingFaceId: "mlx-community/gemma-3-12b-it-4bit",
        contextWindowTokens: 131_072
    )

    static let allModels: [ModelMetadata] = [
        whisperTiny,
        whisperBase,
        whisperSmall,
        whisperNbSmall,
        whisperNbLarge,
        qwen3_4b_mlx,
        qwen35_9b_mlx,
        gemma3_12b_mlx,
        gptOss20b_mlx
    ]

    static let recommendedModels: [ModelMetadata] = [
        whisperBase,
        qwen3_4b_mlx
    ]

    /// Returns the context window size for the currently selected MLX model, defaulting to 32,768
    static func contextWindowForCurrentModel() -> Int {
        let selectedId = ModelSettings.selectedMLXModel
        if let model = allModels.first(where: { $0.huggingFaceId == selectedId || $0.id == selectedId }) {
            return model.contextWindowTokens ?? 32_768
        }
        return 32_768
    }
}
