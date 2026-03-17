//
//  SettingsView.swift
//  Audio Synopsis
//
//  Settings window for model management
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
import MLXLLM
import MLXLMCommon

struct SettingsView: View {
    @EnvironmentObject var modelManager: ModelManager
    @EnvironmentObject var llamaServerManager: LlamaServerManager

    @State private var showingWhisperDirectoryPicker = false
    @State private var showingMLXDirectoryPicker = false
    @State private var showingModelImporter = false
    @State private var downloadingModels: Set<String> = []
    @State private var selectedEngine: SummarizationEngine = ModelSettings.summarizationEngine
    @State private var customPrompt: String = ModelSettings.summarizationSystemPrompt
    @StateObject private var mlxLoader = MLXModelLoader()
    @State private var selectedWhisperModel: String = ModelSettings.selectedWhisperModel
    @State private var selectedMLXModel: String = ModelSettings.selectedMLXModel
    @State private var disableThinking: Bool = ModelSettings.disableModelThinking
    @State private var transcriptionLanguage: String = ModelSettings.transcriptionLanguage
    @State private var modelToDelete: ModelMetadata?
    @State private var maxOutputTokens: Double = Double(ModelSettings.maxOutputTokens)
    @State private var summarizationLanguage: String = ModelSettings.summarizationLanguage
    @State private var summarizationMode: SummarizationMode = ModelSettings.summarizationMode
    @State private var whisperCategory: WhisperModelCategory = .general
    @State private var showingCustomWhisperFilePicker = false
    @State private var showingCustomMLXFolderPicker = false
    @State private var customWhisperPathModels: [CustomModelEntry] = ModelSettings.customWhisperModels
    @State private var customMLXPathModels: [CustomModelEntry] = ModelSettings.customMLXModels
    @State private var chatEngine: ChatEngine = ModelSettings.chatEngine
    @State private var selectedGGUFModel: String = ModelSettings.selectedGGUFModel
    @State private var ggufContextSize: Double = Double(ModelSettings.ggufContextSize)
    @State private var chatSystemPrompt: String = ModelSettings.chatSystemPrompt
    @State private var showingCustomGGUFFilePicker = false
    @State private var autoSummarize: Bool = ModelSettings.autoSummarize

    var body: some View {
        TabView {
            // General tab
            ScrollView {
                VStack(spacing: 24) {
                    whisperDirectorySection
                    Divider()
                    mlxDirectorySection
                    Divider()
                    dataDirectorySection
                    Divider()
                    llamaServerSection
                }
                .padding()
            }
            .tabItem {
                Label("General", systemImage: "gearshape")
            }

            // Transcription tab
            ScrollView {
                VStack(spacing: 24) {
                    transcriptionLanguageSection
                    Divider()
                    activeWhisperModelIndicator
                }
                .padding()
            }
            .tabItem {
                Label("Transcription", systemImage: "waveform")
            }

            // Summarization tab
            ScrollView {
                VStack(spacing: 24) {
                    summarizationEngineSection

                    Divider()
                    autoSummarizeSection

                    Divider()
                    summarizationLanguageSection

                    Divider()
                    activeSummarizationModelIndicator

                    if selectedEngine == .mlx {
                        Divider()
                        summaryLengthSection
                        Divider()
                        contextCapacitySection
                        Divider()
                        thinkingSection
                    } else if selectedEngine == .gguf {
                        Divider()
                        summaryLengthSection
                        Divider()
                        ggufContextSizeSection
                        Divider()
                        thinkingSection
                    }

                    Divider()
                    summarizationPromptSection
                }
                .padding()
            }
            .tabItem {
                Label("Summarization", systemImage: "sparkles")
            }

            // Chat tab
            ScrollView {
                VStack(spacing: 24) {
                    chatEngineSection
                    Divider()
                    chatModelSection
                    Divider()
                    chatPromptSection
                }
                .padding()
            }
            .tabItem {
                Label("Chat", systemImage: "bubble.left.and.bubble.right")
            }

            // Models tab
            ScrollView {
                VStack(spacing: 24) {
                    if let error = modelManager.error {
                        Text(error.localizedDescription)
                            .font(.caption)
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Label("Whisper Models", systemImage: "waveform")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    installedModelsSection

                    if !modelManager.customModels.isEmpty {
                        customModelsSection
                    }

                    availableWhisperModelsSection
                    customWhisperPathsSection

                    Divider()

                    Label("MLX Models", systemImage: "brain")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    installedMLXModelsSection
                    availableMLXModelsSection
                    customMLXPathsSection

                    Divider()

                    Label("GGUF Models", systemImage: "cpu")
                        .font(.title3.weight(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    installedGGUFModelsSection
                    availableGGUFModelsSection
                    customGGUFPathsSection
                }
                .padding()
            }
            .tabItem {
                Label("Models", systemImage: "arrow.down.circle")
            }
        }
        .frame(width: 750, height: 590)
        .fileImporter(
            isPresented: $showingWhisperDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleWhisperDirectorySelection(result)
        }
        .fileImporter(
            isPresented: $showingMLXDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleMLXDirectorySelection(result)
        }
        .fileImporter(
            isPresented: $showingModelImporter,
            allowedContentTypes: [.data],
            allowsMultipleSelection: true
        ) { result in
            handleModelImport(result)
        }
        .fileImporter(
            isPresented: $showingCustomWhisperFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                addCustomWhisperModel(from: url)
            }
        }
        .fileImporter(
            isPresented: $showingCustomMLXFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                addCustomMLXModel(from: url)
            }
        }
        .fileImporter(
            isPresented: $showingCustomGGUFFilePicker,
            allowedContentTypes: [.data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                addCustomGGUFModel(from: url)
            }
        }
        .alert("Delete Model?", isPresented: Binding(
            get: { modelToDelete != nil },
            set: { if !$0 { modelToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) { modelToDelete = nil }
            Button("Delete", role: .destructive) {
                if let model = modelToDelete {
                    deleteModel(model)
                    modelToDelete = nil
                }
            }
        } message: {
            if let model = modelToDelete {
                Text("This will permanently delete \"\(model.name)\" (\(model.sizeFormatted)).")
            }
        }
    }

    // MARK: - Whisper Directory Section

    private var whisperDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Whisper Model Directory", systemImage: "folder.fill")
                .font(.headline)

            Text("Directory for Whisper speech-to-text model files (.bin).")
                .font(.caption)
                .foregroundColor(.secondary)

            if let directory = modelManager.whisperModelDirectory {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(directory.path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)

                        if let diskSpace = modelManager.whisperAvailableDiskSpace {
                            Text("Available: \(ByteCountFormatter.string(fromByteCount: diskSpace, countStyle: .file))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Spacer()

                    Button("Open in Finder") {
                        NSWorkspace.shared.open(directory)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Change...") {
                        showingWhisperDirectoryPicker = true
                    }
                    .controlSize(.small)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Button("Select Whisper Models Directory") {
                    showingWhisperDirectoryPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - MLX Directory Section

    private var mlxDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("MLX Model Directory", systemImage: "folder.fill")
                .font(.headline)

            Text("MLX models are stored in Application Support by default. Point this to an existing HuggingFace cache to reuse downloads from other apps.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let directory = modelManager.mlxModelDirectory {
                HStack {
                    Text(directory.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Open in Finder") {
                        NSWorkspace.shared.open(directory)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Change...") {
                        showingMLXDirectoryPicker = true
                    }
                    .controlSize(.small)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            } else {
                Button("Select MLX Models Directory") {
                    showingMLXDirectoryPicker = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Transcription Language Section

    private var transcriptionLanguageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Transcription Language", systemImage: "globe")
                .font(.headline)

            Text("Set the spoken language for transcription. Auto-detect works for most cases, but selecting a specific language can improve accuracy.")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Language", selection: $transcriptionLanguage) {
                ForEach(ModelSettings.whisperLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .labelsHidden()
            .onChange(of: transcriptionLanguage) { _, newValue in
                ModelSettings.transcriptionLanguage = newValue
            }
        }
    }

    // MARK: - Installed Models Section

    private var installedWhisperModels: [ModelMetadata] {
        modelManager.availableModels.filter { modelManager.isModelInstalled($0.id) && $0.type == .whisper }
    }

    private var installedModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installed Whisper Models", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundColor(.green)

            if installedWhisperModels.isEmpty && modelManager.customModels.isEmpty {
                Text("No Whisper models installed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(installedWhisperModels) { model in
                    installedModelRow(model)
                }
            }
        }
    }

    private func installedModelRow(_ model: ModelMetadata) -> some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline.weight(.medium))
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(model.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)

            Button(action: {
                modelToDelete = model
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Custom Models Section

    private var customModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Custom Models", systemImage: "doc.badge.gearshape")
                .font(.headline)

            Text("Models discovered in your model directory that aren't in the built-in list.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(modelManager.customModels) { model in
                installedModelRow(model)
            }
        }
    }

    // MARK: - Summarization Engine Section

    private var summarizationEngineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summarization Engine", systemImage: "cpu")
                .font(.headline)

            Text("Choose how transcriptions are summarized.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(SummarizationEngine.allCases) { engine in
                engineRow(engine)
            }
        }
    }

    private func engineRow(_ engine: SummarizationEngine) -> some View {
        let isSelected = selectedEngine == engine

        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .green : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(engine.displayName)
                        .font(.subheadline.weight(.medium))
                    if engine == .appleIntelligence {
                        Image(systemName: "apple.logo")
                            .font(.caption)
                    }
                }
                Text(engine.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isSelected {
                Button("Select") {
                    selectedEngine = engine
                    ModelSettings.summarizationEngine = engine
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Installed MLX Models Section

    private var cachedMLXModels: [ModelMetadata] {
        ModelMetadata.allModels.filter { $0.type == .mlx && (isMLXModelCached($0) || mlxLoader.downloadedModelIds.contains($0.huggingFaceId ?? $0.id)) }
    }

    private var installedMLXModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installed MLX Models", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundColor(.green)

            if cachedMLXModels.isEmpty {
                Text("No MLX models cached")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(cachedMLXModels) { model in
                    installedMLXModelRow(model)
                }
            }

            if let error = mlxLoader.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func installedMLXModelRow(_ model: ModelMetadata) -> some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(model.sizeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                Button(action: {
                    clearMLXModelCache(model)
                    mlxLoader.reset()
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }

            // Cache management row
            HStack {
                Spacer()

                Button("Open in Finder") {
                    if let dir = mlxModelCacheDirectory(model) {
                        NSWorkspace.shared.open(dir)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
            .padding(.top, 8)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Available MLX Downloads Section

    private var availableMLXModelsSection: some View {
        let allMLXModels = ModelMetadata.allModels.filter { $0.type == .mlx }

        return VStack(alignment: .leading, spacing: 12) {
            Label("Available MLX Downloads", systemImage: "arrow.down.circle")
                .font(.headline)

            ForEach(allMLXModels) { model in
                availableMLXModelRow(model)
            }

            if let error = mlxLoader.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func availableMLXModelRow(_ model: ModelMetadata) -> some View {
        let modelId = model.huggingFaceId ?? model.id
        let isCached = isMLXModelCached(model) || mlxLoader.downloadedModelIds.contains(modelId)

        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "brain")
                    .foregroundColor(.purple)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(model.sizeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                if isCached {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if mlxLoader.isLoading && mlxLoader.downloadingModelId == modelId {
                    Button(action: {
                        mlxLoader.cancel()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        mlxLoader.downloadAndLoad(modelId: modelId, sizeBytes: model.sizeBytes)
                    }) {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(mlxLoader.isLoading)
                }
            }

            // Progress bar + details below the model info row
            if mlxLoader.isLoading && mlxLoader.downloadingModelId == modelId {
                VStack(spacing: 6) {
                    ProgressView(value: mlxLoader.fractionCompleted)
                        .progressViewStyle(.linear)

                    HStack {
                        Text(mlxLoader.status)
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        if mlxLoader.isStalled {
                            Text("Downloading large model file...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if !mlxLoader.speedFormatted.isEmpty {
                            Text(mlxLoader.speedFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("\(Int(mlxLoader.fractionCompleted * 100))%")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Available Whisper Models Section

    private var availableWhisperModelsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Available Whisper Downloads", systemImage: "arrow.down.circle")
                    .font(.headline)

                Spacer()

                Button(action: {
                    showingModelImporter = true
                }) {
                    Label("Import Model...", systemImage: "doc.badge.plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Picker("Model Category", selection: $whisperCategory) {
                ForEach(WhisperModelCategory.allCases) { category in
                    Text(category.rawValue).tag(category)
                }
            }
            .pickerStyle(.segmented)

            ForEach(ModelMetadata.whisperModels(for: whisperCategory)) { model in
                availableModelRow(model)
            }

        }
    }

    private func availableModelRow(_ model: ModelMetadata) -> some View {
        let isDownloading = modelManager.downloadProgress[model.id] != nil

        return VStack(spacing: 0) {
            // Top row: model info + action button
            HStack {
                Image(systemName: "waveform")
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(model.sizeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                if modelManager.isModelInstalled(model.id) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isDownloading {
                    Button(action: {
                        modelManager.cancelDownload(for: model.id)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: {
                        downloadModel(model)
                    }) {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Progress bar + details below the model info row
            if let progress = modelManager.downloadProgress[model.id] {
                VStack(spacing: 6) {
                    if progress.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        ProgressView(value: progress.fractionCompleted)
                            .progressViewStyle(.linear)
                    }

                    HStack {
                        if progress.isConnecting {
                            Text("Connecting...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(progress.downloadedFormatted) of \(progress.totalFormatted)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if progress.bytesPerSecond > 0 {
                            Text(progress.speedFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if !progress.isConnecting {
                            Text("\(progress.percentComplete)%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Data Directory Section

    private var dataDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data Directory", systemImage: "internaldrive")
                .font(.headline)

            Text("Recordings, transcripts, and recording data are stored here.")
                .font(.caption)
                .foregroundColor(.secondary)

            if let dir = try? AudioUtils.getRecordingsDirectory().deletingLastPathComponent() {
                HStack {
                    Text(dir.path)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    Button("Open in Finder") {
                        NSWorkspace.shared.open(dir)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Llama Server Section

    @State private var llamaServerError: String?

    private var llamaServerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("llama-server (GGUF)", systemImage: "server.rack")
                .font(.headline)

            Text("The llama-server binary is required for GGUF model inference. Version: \(LlamaServerManager.llamaCppVersion)")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                if llamaServerManager.isBinaryAvailable {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Installed")
                        .font(.subheadline)
                } else {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text("Not installed")
                        .font(.subheadline)
                }

                Spacer()

                if llamaServerManager.isDownloadingBinary {
                    Button(action: {
                        llamaServerManager.cancelBinaryDownload()
                    }) {
                        Label("Cancel", systemImage: "xmark.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if llamaServerManager.isBinaryAvailable {
                    Button(action: {
                        llamaServerError = nil
                        Task {
                            do {
                                try await llamaServerManager.updateLlamaServer()
                            } catch {
                                llamaServerError = error.localizedDescription
                            }
                        }
                    }) {
                        Label("Re-download", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button(action: {
                        llamaServerError = nil
                        Task {
                            do {
                                try await llamaServerManager.downloadLlamaServer()
                            } catch {
                                llamaServerError = error.localizedDescription
                            }
                        }
                    }) {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            if llamaServerManager.isDownloadingBinary {
                if let progress = llamaServerManager.binaryDownloadProgress {
                    VStack(spacing: 6) {
                        if progress.isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            ProgressView(value: progress.fractionCompleted)
                                .progressViewStyle(.linear)
                        }
                        HStack {
                            if progress.isConnecting {
                                Text("Connecting...")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("\(progress.downloadedFormatted) of \(progress.totalFormatted)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if progress.bytesPerSecond > 0 {
                                Text(progress.speedFormatted)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            if !progress.isConnecting {
                                Text("\(progress.percentComplete)%")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            if let error = llamaServerError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Summarization Language Section

    private var summarizationLanguageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summary Language", systemImage: "globe")
                .font(.headline)

            Text("Choose the language for generated summaries. \"Match transcript/notes language\" will write the summary in the notes language if provided, otherwise in the transcript language.")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Language", selection: $summarizationLanguage) {
                ForEach(ModelSettings.summarizationLanguages, id: \.code) { lang in
                    Text(lang.name).tag(lang.code)
                }
            }
            .labelsHidden()
            .onChange(of: summarizationLanguage) { _, newValue in
                ModelSettings.summarizationLanguage = newValue
            }
        }
    }

    // MARK: - Summary Length Section

    private var summaryLengthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summary Length", systemImage: "text.justify.left")
                .font(.headline)

            Text("Maximum number of tokens the model can generate for a summary. Higher values produce longer, more detailed summaries.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack {
                Slider(value: $maxOutputTokens, in: 500...8000, step: 500)
                    .onChange(of: maxOutputTokens) { _, newValue in
                        ModelSettings.maxOutputTokens = Int(newValue)
                    }

                Text("\(Int(maxOutputTokens)) tokens")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 100, alignment: .trailing)
            }
        }
    }

    // MARK: - Context Capacity Section

    private var contextCapacitySection: some View {
        let contextWindow = ModelMetadata.contextWindowForCurrentModel()
        let outputBudget = ModelSettings.maxOutputTokens
        let inputBudget = Int(Double(contextWindow) * 0.8) - outputBudget
        let estimatedMinutes = max(0, inputBudget / 200)

        return VStack(alignment: .leading, spacing: 12) {
            Label("Context Capacity", systemImage: "gauge.with.dots.needle.33percent")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Model context window:")
                    Spacer()
                    Text("\(contextWindow.formatted()) tokens")
                        .foregroundColor(.secondary)
                }
                .font(.caption)

                HStack {
                    Text("Estimated single-pass capacity:")
                    Spacer()
                    Text("~\(estimatedMinutes) minutes of recorded audio")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Text("Longer recordings are automatically handled with multi-pass summarization, where the transcript is split into chunks and summaries are merged.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Thinking Section

    private var autoSummarizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Auto-Summarize", systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)

            Toggle(isOn: $autoSummarize) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Automatically summarize after recording")
                        .font(.subheadline)
                    Text("When enabled, a summary is generated automatically after recording stops or audio is imported. When disabled, you can generate summaries on demand from the Summary tab.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: autoSummarize) { _, newValue in
                ModelSettings.autoSummarize = newValue
            }
        }
    }

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Model Thinking", systemImage: "brain.head.profile")
                .font(.headline)

            Toggle(isOn: $disableThinking) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disable thinking")
                        .font(.subheadline)
                    Text("Prevents models like Qwen3 from using internal reasoning tokens, which speeds up generation and avoids wasting the token budget on hidden reasoning. Disable this if you want to see the model's thought process.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: disableThinking) { _, newValue in
                ModelSettings.disableModelThinking = newValue
            }
        }
    }

    // MARK: - Summarization Prompt Section

    private var summarizationPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summarization Prompt", systemImage: "text.bubble")
                .font(.headline)

            Text("Customize the system prompt used when generating summaries.")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Mode", selection: $summarizationMode) {
                ForEach(SummarizationMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: summarizationMode) { _, newMode in
                ModelSettings.summarizationMode = newMode
                // If the current prompt matches any known preset, switch to the new mode's prompt
                let isPreset = SummarizationMode.allCases.contains { $0.defaultPrompt == customPrompt }
                if isPreset {
                    customPrompt = newMode.defaultPrompt
                    ModelSettings.summarizationSystemPrompt = customPrompt
                }
            }

            TextEditor(text: $customPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(height: 100)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .onChange(of: customPrompt) { _, newValue in
                    ModelSettings.summarizationSystemPrompt = newValue
                }

            HStack {
                Spacer()
                if customPrompt != summarizationMode.defaultPrompt {
                    Button("Reset to Default") {
                        customPrompt = summarizationMode.defaultPrompt
                        ModelSettings.summarizationSystemPrompt = customPrompt
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Chat Settings

    private var chatEngineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Chat Engine", systemImage: "bubble.left.and.bubble.right")
                .font(.headline)

            Text("Choose which engine powers the Chat tab. Only one engine is active at a time.")
                .font(.caption)
                .foregroundColor(.secondary)

            ForEach(ChatEngine.allCases) { engine in
                chatEngineRow(engine)
            }
        }
    }

    private func chatEngineRow(_ engine: ChatEngine) -> some View {
        let isSelected = chatEngine == engine

        return HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .green : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(engine.displayName)
                    .font(.subheadline.weight(.medium))
                Text(engine.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !isSelected {
                Button("Select") {
                    chatEngine = engine
                    ModelSettings.chatEngine = engine
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Shared GGUF Model Settings

    private var installedGGUFModels: [ModelMetadata] {
        ModelMetadata.ggufModels.filter { modelManager.isModelInstalled($0.id) }
    }

    private var installedGGUFModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Installed GGUF Models", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundColor(.green)

            if installedGGUFModels.isEmpty && ModelSettings.customGGUFModels.isEmpty {
                Text("No GGUF models installed")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(installedGGUFModels) { model in
                    installedGGUFModelRow(model)
                }
            }
        }
    }

    private func installedGGUFModelRow(_ model: ModelMetadata) -> some View {
        HStack {
            Image(systemName: "cpu")
                .foregroundColor(.purple)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline.weight(.medium))
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(model.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)

            Button(action: {
                modelToDelete = model
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var availableGGUFModelsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Available GGUF Downloads", systemImage: "arrow.down.circle")
                .font(.headline)

            ForEach(ModelMetadata.ggufModels, id: \.id) { model in
                availableGGUFModelRow(model)
            }
        }
    }

    private func availableGGUFModelRow(_ model: ModelMetadata) -> some View {
        let isInstalled = modelManager.isModelInstalled(model.id)
        let isDownloading = modelManager.downloadProgress[model.id] != nil

        return VStack(spacing: 0) {
            HStack {
                Image(systemName: "cpu")
                    .foregroundColor(.purple)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(model.sizeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)

                if isInstalled {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else if isDownloading {
                    Button(action: {
                        modelManager.cancelDownload(for: model.id)
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else if downloadingModels.contains(model.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button(action: {
                        downloadModel(model)
                    }) {
                        Label("Download", systemImage: "arrow.down.circle.fill")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Progress bar + details below the model info row
            if let progress = modelManager.downloadProgress[model.id] {
                VStack(spacing: 6) {
                    if progress.isConnecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        ProgressView(value: progress.fractionCompleted)
                            .progressViewStyle(.linear)
                    }

                    HStack {
                        if progress.isConnecting {
                            Text("Connecting...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            Text("\(progress.downloadedFormatted) of \(progress.totalFormatted)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        if progress.bytesPerSecond > 0 {
                            Text(progress.speedFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        if !progress.isConnecting {
                            Text("\(progress.percentComplete)%")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var customGGUFPathsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Custom GGUF Models", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                Button(action: { showingCustomGGUFFilePicker = true }) {
                    Label("Add Model...", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Add GGUF model files from anywhere on your system.")
                .font(.caption)
                .foregroundColor(.secondary)

            if ModelSettings.customGGUFModels.isEmpty {
                Text("No custom models added")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(ModelSettings.customGGUFModels) { entry in
                    customGGUFPathRow(entry)
                }
            }
        }
    }

    private func customGGUFPathRow(_ entry: CustomModelEntry) -> some View {
        let url = entry.resolveURL()

        return HStack {
            Image(systemName: "cpu")
                .foregroundColor(.purple)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                if let url = url {
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Path unavailable")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            Button(action: {
                removeCustomGGUFModel(entry)
            }) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var ggufContextSizeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Context Window Size", systemImage: "gauge.with.dots.needle.33percent")
                .font(.headline)

            HStack {
                Slider(value: $ggufContextSize, in: 512...131072, step: 512)
                    .onChange(of: ggufContextSize) { _, newValue in
                        ModelSettings.ggufContextSize = Int(newValue)
                    }
                Text("\(Int(ggufContextSize))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 60, alignment: .trailing)
            }

            Text("Larger context uses more memory. Default: 4096.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Active Model Indicators

    private var activeWhisperModelIndicator: some View {
        let installed = installedWhisperModels + modelManager.customModels
        let customPaths = ModelSettings.customWhisperModels

        return VStack(alignment: .leading, spacing: 12) {
            Label("Transcription Model", systemImage: "waveform")
                .font(.headline)

            Text("Select the Whisper model used for transcription. Download more models in the Models tab.")
                .font(.caption)
                .foregroundColor(.secondary)

            if installed.isEmpty && customPaths.isEmpty {
                Text("No models installed — download one in the Models tab.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(installed) { model in
                    whisperModelPickerRow(id: model.id, name: model.name, detail: model.sizeFormatted)
                }
                ForEach(customPaths) { entry in
                    whisperModelPickerRow(id: entry.id, name: entry.name, detail: entry.resolveURL()?.lastPathComponent ?? "Custom")
                }
            }
        }
    }

    private func whisperModelPickerRow(id: String, name: String, detail: String) -> some View {
        let isActive = selectedWhisperModel == id

        return HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .green : .secondary)
                .frame(width: 30)

            Text(name)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)

            if !isActive {
                Button("Use") {
                    selectedWhisperModel = id
                    ModelSettings.selectedWhisperModel = id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var activeSummarizationModelIndicator: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summarization Model", systemImage: "sparkles")
                .font(.headline)

            Text("Select the model used for summarization. Download more models in the Models tab.")
                .font(.caption)
                .foregroundColor(.secondary)

            switch selectedEngine {
            case .appleIntelligence:
                HStack {
                    Image(systemName: "apple.logo")
                        .foregroundColor(.green)
                    Text("Apple Intelligence")
                        .font(.subheadline.weight(.medium))
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.05))
                .cornerRadius(8)

            case .mlx:
                let installed = cachedMLXModels
                let customPaths = ModelSettings.customMLXModels

                if installed.isEmpty && customPaths.isEmpty {
                    Text("No MLX models installed — download one in the Models tab.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(installed) { model in
                        mlxModelPickerRow(id: model.huggingFaceId ?? model.id, name: model.name, detail: model.sizeFormatted)
                    }
                    ForEach(customPaths) { entry in
                        mlxModelPickerRow(id: entry.id, name: entry.name, detail: "Custom")
                    }
                }

            case .gguf:
                let installed = installedGGUFModels
                let customPaths = ModelSettings.customGGUFModels

                if installed.isEmpty && customPaths.isEmpty {
                    Text("No GGUF models installed — download one in the Models tab.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(installed) { model in
                        ggufModelPickerRow(id: model.id, name: model.name, detail: model.sizeFormatted)
                    }
                    ForEach(customPaths) { entry in
                        ggufModelPickerRow(id: entry.id, name: entry.name, detail: "Custom")
                    }
                }
            }
        }
    }

    private func mlxModelPickerRow(id: String, name: String, detail: String) -> some View {
        let isActive = selectedMLXModel == id

        return HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .green : .secondary)
                .frame(width: 30)

            Text(name)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)

            if !isActive {
                Button("Use") {
                    selectedMLXModel = id
                    ModelSettings.selectedMLXModel = id
                    mlxLoader.reset()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private func ggufModelPickerRow(id: String, name: String, detail: String) -> some View {
        let isActive = selectedGGUFModel == id

        return HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .green : .secondary)
                .frame(width: 30)

            Text(name)
                .font(.subheadline.weight(.medium))

            Spacer()

            Text(detail)
                .font(.caption)
                .foregroundColor(.secondary)

            if !isActive {
                Button("Use") {
                    selectedGGUFModel = id
                    ModelSettings.selectedGGUFModel = id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var chatModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Chat Model", systemImage: "cpu")
                .font(.headline)

            if chatEngine == .mlx {
                Text("Uses the same MLX model selected in the Summarization tab.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let model = ModelMetadata.allModels.first(where: { ($0.huggingFaceId ?? $0.id) == selectedMLXModel && $0.type == .mlx }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(model.name)
                            .font(.subheadline.weight(.medium))
                        Text("(\(model.sizeFormatted))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(selectedMLXModel)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }
            } else {
                Text("Uses the same GGUF model selected in the Summarization tab.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let model = ModelMetadata.ggufModels.first(where: { $0.id == selectedGGUFModel }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(model.name)
                            .font(.subheadline.weight(.medium))
                        Text("(\(model.sizeFormatted))")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                } else if let custom = ModelSettings.customGGUFModels.first(where: { $0.id == selectedGGUFModel }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(custom.name)
                            .font(.subheadline.weight(.medium))
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(8)
                }
            }
        }
    }

    private var chatPromptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Chat System Prompt", systemImage: "text.bubble")
                .font(.headline)

            Text("Customize the system prompt used in chat conversations.")
                .font(.caption)
                .foregroundColor(.secondary)

            TextEditor(text: $chatSystemPrompt)
                .font(.system(.body, design: .monospaced))
                .frame(height: 80)
                .padding(4)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
                .onChange(of: chatSystemPrompt) { _, newValue in
                    ModelSettings.chatSystemPrompt = newValue
                }

            HStack {
                Spacer()
                if chatSystemPrompt != ModelSettings.defaultChatSystemPrompt {
                    Button("Reset to Default") {
                        chatSystemPrompt = ModelSettings.defaultChatSystemPrompt
                        ModelSettings.chatSystemPrompt = chatSystemPrompt
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - Custom Whisper Path Models

    private var customWhisperPathsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Custom Whisper Models", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                Button(action: { showingCustomWhisperFilePicker = true }) {
                    Label("Add Model...", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Add Whisper .bin model files from anywhere on your system.")
                .font(.caption)
                .foregroundColor(.secondary)

            if customWhisperPathModels.isEmpty {
                Text("No custom models added")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(customWhisperPathModels) { entry in
                    customWhisperPathRow(entry)
                }
            }
        }
    }

    private func customWhisperPathRow(_ entry: CustomModelEntry) -> some View {
        let url = entry.resolveURL()

        return HStack {
            Image(systemName: "waveform")
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                if let url = url {
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Path unavailable")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            Button(action: {
                removeCustomWhisperModel(entry)
            }) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Custom MLX Path Models

    private var customMLXPathsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Custom MLX Models", systemImage: "folder.badge.gearshape")
                    .font(.headline)
                Spacer()
                Button(action: { showingCustomMLXFolderPicker = true }) {
                    Label("Add Model...", systemImage: "plus")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Add MLX model directories from anywhere on your system.")
                .font(.caption)
                .foregroundColor(.secondary)

            if customMLXPathModels.isEmpty {
                Text("No custom models added")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(customMLXPathModels) { entry in
                    customMLXPathRow(entry)
                }
            }
        }
    }

    private func customMLXPathRow(_ entry: CustomModelEntry) -> some View {
        let url = entry.resolveURL()

        return HStack {
            Image(systemName: "brain")
                .foregroundColor(.purple)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.name)
                    .font(.subheadline.weight(.medium))
                if let url = url {
                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("Path unavailable")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            Button(action: {
                removeCustomMLXModel(entry)
            }) {
                Image(systemName: "minus.circle")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    // MARK: - Custom Model Actions

    private func addCustomWhisperModel(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            Logger.error("Failed to create bookmark for custom Whisper model", category: Logger.ui)
            return
        }

        let name = url.deletingPathExtension().lastPathComponent
        let entry = CustomModelEntry(
            id: "custom-whisper-\(UUID().uuidString)",
            name: name,
            bookmarkData: bookmarkData
        )

        customWhisperPathModels.append(entry)
        ModelSettings.customWhisperModels = customWhisperPathModels
        Logger.info("Added custom Whisper model: \(name) at \(url.path)", category: Logger.ui)
    }

    private func removeCustomWhisperModel(_ entry: CustomModelEntry) {
        customWhisperPathModels.removeAll { $0.id == entry.id }
        ModelSettings.customWhisperModels = customWhisperPathModels

        if selectedWhisperModel == entry.id {
            selectedWhisperModel = "whisper-base"
            ModelSettings.selectedWhisperModel = "whisper-base"
        }
        Logger.info("Removed custom Whisper model: \(entry.name)", category: Logger.ui)
    }

    private func addCustomMLXModel(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            Logger.error("Failed to create bookmark for custom MLX model", category: Logger.ui)
            return
        }

        let name = url.lastPathComponent
        let entry = CustomModelEntry(
            id: "custom-mlx-\(UUID().uuidString)",
            name: name,
            bookmarkData: bookmarkData
        )

        customMLXPathModels.append(entry)
        ModelSettings.customMLXModels = customMLXPathModels
        Logger.info("Added custom MLX model: \(name) at \(url.path)", category: Logger.ui)
    }

    private func removeCustomMLXModel(_ entry: CustomModelEntry) {
        customMLXPathModels.removeAll { $0.id == entry.id }
        ModelSettings.customMLXModels = customMLXPathModels

        if selectedMLXModel == entry.id {
            let defaultModel = "mlx-community/Qwen3.5-4B-OptiQ-4bit"
            selectedMLXModel = defaultModel
            ModelSettings.selectedMLXModel = defaultModel
            mlxLoader.reset()
        }
        Logger.info("Removed custom MLX model: \(entry.name)", category: Logger.ui)
    }

    // MARK: - Custom GGUF Model Helpers

    private func addCustomGGUFModel(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard url.pathExtension.lowercased() == "gguf" else {
            Logger.error("Selected file is not a .gguf file", category: Logger.ui)
            return
        }

        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) else {
            Logger.error("Failed to create bookmark for custom GGUF model", category: Logger.ui)
            return
        }

        let name = url.deletingPathExtension().lastPathComponent
        let entry = CustomModelEntry(
            id: "custom-gguf-\(UUID().uuidString)",
            name: name,
            bookmarkData: bookmarkData
        )

        var models = ModelSettings.customGGUFModels
        models.append(entry)
        ModelSettings.customGGUFModels = models

        // Auto-select the new model
        selectedGGUFModel = entry.id
        ModelSettings.selectedGGUFModel = entry.id
        Logger.info("Added custom GGUF model: \(name) at \(url.path)", category: Logger.ui)
    }

    private func removeCustomGGUFModel(_ entry: CustomModelEntry) {
        var models = ModelSettings.customGGUFModels
        models.removeAll { $0.id == entry.id }
        ModelSettings.customGGUFModels = models

        if selectedGGUFModel == entry.id {
            let fallback = ModelMetadata.ggufModels.first?.id ?? "qwen3.5-0.8b-q4_k_m"
            selectedGGUFModel = fallback
            ModelSettings.selectedGGUFModel = fallback
        }
        Logger.info("Removed custom GGUF model: \(entry.name)", category: Logger.ui)
    }

    // MARK: - MLX Cache Helpers

    /// Returns the cache directory for a model by checking all known locations.
    private func mlxModelCacheDirectory(_ model: ModelMetadata) -> URL? {
        guard let hfId = model.huggingFaceId else { return nil }
        let fm = FileManager.default

        // Check user-configured MLX directory (direct path: mlxDir/org/name)
        if let mlxDir = modelManager.mlxModelDirectory {
            let directPath = mlxDir.appendingPathComponent(hfId)
            if fm.fileExists(atPath: directPath.path) {
                return directPath
            }

            // HubApi layout: {downloadBase}/models/org/name
            let hubApiPath = mlxDir.appendingPathComponent("models").appendingPathComponent(hfId)
            if fm.fileExists(atPath: hubApiPath.path) {
                return hubApiPath
            }
        }

        // Check HuggingFace Hub cache: ~/.cache/huggingface/hub/models--org--name
        let hubCacheDir = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub")
        let hubDirName = "models--" + hfId.replacingOccurrences(of: "/", with: "--")
        let hubPath = hubCacheDir.appendingPathComponent(hubDirName)
        if fm.fileExists(atPath: hubPath.path) {
            return hubPath
        }

        return nil
    }

    private func isMLXModelCached(_ model: ModelMetadata) -> Bool {
        guard let cacheDir = mlxModelCacheDirectory(model) else { return false }

        // HuggingFace Hub downloads files as {hash}.incomplete and renames on completion.
        // If blobs/ contains any .incomplete files, the download is not finished.
        let blobsDir = cacheDir.appendingPathComponent("blobs")
        if FileManager.default.fileExists(atPath: blobsDir.path),
           let contents = try? FileManager.default.contentsOfDirectory(atPath: blobsDir.path),
           contents.contains(where: { $0.hasSuffix(".incomplete") }) {
            return false
        }

        return true
    }

    private func clearMLXModelCache(_ model: ModelMetadata) {
        guard let dir = mlxModelCacheDirectory(model) else { return }
        let modelId = model.huggingFaceId ?? model.id
        let wasActive = selectedMLXModel == modelId

        do {
            try FileManager.default.removeItem(at: dir)
            mlxLoader.downloadedModelIds.remove(modelId)
            Logger.info("Cleared MLX cache for \(model.name) at \(dir.path)", category: Logger.ui)

            // If the deleted model was active, fall back to another cached model or default
            if wasActive {
                let mlxModels = ModelMetadata.allModels.filter { $0.type == .mlx }
                if let fallback = mlxModels.first(where: { $0.id != model.id && (isMLXModelCached($0) || mlxLoader.downloadedModelIds.contains($0.huggingFaceId ?? $0.id)) }),
                   let fallbackId = fallback.huggingFaceId {
                    selectedMLXModel = fallbackId
                    ModelSettings.selectedMLXModel = fallbackId
                } else {
                    // Reset to default
                    let defaultModel = "mlx-community/Qwen3.5-4B-OptiQ-4bit"
                    selectedMLXModel = defaultModel
                    ModelSettings.selectedMLXModel = defaultModel
                }
            }
        } catch {
            Logger.error("Failed to clear MLX cache for \(model.name)", error: error, category: Logger.ui)
        }
    }

    // MARK: - Actions

    private func handleWhisperDirectorySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            modelManager.setWhisperModelDirectory(url)
            Logger.info("User selected Whisper model directory: \(url.path)", category: Logger.ui)

        case .failure(let error):
            Logger.error("Failed to select Whisper directory", error: error, category: Logger.ui)
        }
    }

    private func handleMLXDirectorySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            modelManager.setMLXModelDirectory(url)
            Logger.info("User selected MLX model directory: \(url.path)", category: Logger.ui)

        case .failure(let error):
            Logger.error("Failed to select MLX directory", error: error, category: Logger.ui)
        }
    }

    private func handleModelImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                do {
                    try modelManager.importModel(from: url)
                    Logger.info("Imported model: \(url.lastPathComponent)", category: Logger.ui)
                } catch {
                    Logger.error("Failed to import model: \(url.lastPathComponent)", error: error, category: Logger.ui)
                }
            }
        case .failure(let error):
            Logger.error("Model import picker failed", error: error, category: Logger.ui)
        }
    }

    private func downloadModel(_ model: ModelMetadata) {
        Logger.info("User initiated download for: \(model.name)", category: Logger.ui)
        downloadingModels.insert(model.id)

        Task {
            do {
                try await modelManager.downloadModel(model)
                await MainActor.run {
                    downloadingModels.remove(model.id)
                }
            } catch {
                Logger.error("Download failed for \(model.name)", error: error, category: Logger.ui)
                await MainActor.run {
                    downloadingModels.remove(model.id)
                    // Belt-and-suspenders: ensure stale progress is cleared
                    modelManager.downloadProgress.removeValue(forKey: model.id)
                }
            }
        }
    }

    private func deleteModel(_ model: ModelMetadata) {
        Logger.info("User deleting model: \(model.name)", category: Logger.ui)

        let wasActive = selectedWhisperModel == model.id

        do {
            try modelManager.deleteModel(model)

            // If the deleted model was active, fall back to the first installed model
            if wasActive {
                let remaining = (modelManager.availableModels.filter { modelManager.isModelInstalled($0.id) && $0.type == .whisper }
                    + modelManager.customModels)
                if let fallback = remaining.first(where: { $0.id != model.id }) {
                    selectedWhisperModel = fallback.id
                    ModelSettings.selectedWhisperModel = fallback.id
                }
            }
        } catch {
            Logger.error("Failed to delete model", error: error, category: Logger.ui)
        }
    }
}

// MARK: - MLX Model Loader Helper

@MainActor
class MLXModelLoader: ObservableObject {
    @Published var isLoading = false
    @Published var isLoaded = false
    @Published var status: String = ""
    @Published var error: String?
    @Published var fractionCompleted: Double = 0
    @Published var downloadingModelId: String?
    @Published var downloadedModelIds: Set<String> = []
    @Published var speedFormatted: String = ""
    @Published var isStalled: Bool = false

    private var downloadTask: Task<Void, Never>?
    private var totalSizeBytes: Int64 = 0

    // Interval-based speed measurement
    private var lastFraction: Double = 0
    private var lastSpeedTimestamp: CFAbsoluteTime = 0
    private var currentSpeed: Double = 0
    private var speedSampleCount: Int = 0

    // Stall detection
    private var lastProgressChangeTime: CFAbsoluteTime = 0
    private var lastReportedFraction: Double = -1

    func reset() {
        isLoading = false
        isLoaded = false
        status = ""
        error = nil
        fractionCompleted = 0
        downloadingModelId = nil
        speedFormatted = ""
        isStalled = false
        resetSpeedState()
    }

    private func resetSpeedState() {
        lastFraction = 0
        lastSpeedTimestamp = 0
        currentSpeed = 0
        speedSampleCount = 0
        lastProgressChangeTime = 0
        lastReportedFraction = -1
    }

    func downloadAndLoad(modelId: String, sizeBytes: Int64 = 0) {
        downloadTask?.cancel()

        downloadTask = Task {
            isLoading = true
            downloadingModelId = modelId
            error = nil
            fractionCompleted = 0
            speedFormatted = ""
            isStalled = false
            totalSizeBytes = sizeBytes
            resetSpeedState()
            status = "Downloading model..."

            do {
                let config = ModelConfiguration(id: modelId)
                let _ = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                    Task { @MainActor in
                        self.fractionCompleted = progress.fractionCompleted

                        // Stall detection: track when fraction actually changes
                        if progress.fractionCompleted != self.lastReportedFraction {
                            self.lastReportedFraction = progress.fractionCompleted
                            self.lastProgressChangeTime = CFAbsoluteTimeGetCurrent()
                            self.isStalled = false
                        }

                        self.updateSpeed()
                    }
                }

                guard !Task.isCancelled else {
                    isLoading = false
                    status = "Cancelled"
                    return
                }

                downloadedModelIds.insert(modelId)
                isLoaded = true
                isLoading = false
                status = "Model ready"

            } catch {
                if !Task.isCancelled {
                    self.error = error.localizedDescription
                    isLoading = false
                    status = "Failed"
                }
            }
        }
    }

    func cancel() {
        downloadTask?.cancel()
        isLoading = false
        downloadingModelId = nil
        fractionCompleted = 0
        speedFormatted = ""
        isStalled = false
        status = ""
    }

    private func updateSpeed() {
        guard totalSizeBytes > 0, fractionCompleted > 0 else { return }

        let now = CFAbsoluteTimeGetCurrent()

        // Initialize on first call
        if lastSpeedTimestamp == 0 {
            lastSpeedTimestamp = now
            lastFraction = fractionCompleted
            lastProgressChangeTime = now
            return
        }

        // Detect stalls (3+ seconds without progress change)
        if lastProgressChangeTime > 0 && now - lastProgressChangeTime > 3.0 && fractionCompleted < 0.95 {
            isStalled = true
            speedFormatted = ""
        }

        let elapsed = now - lastSpeedTimestamp
        guard elapsed >= 0.5 else { return }

        let fractionDelta = fractionCompleted - lastFraction
        let bytesDelta = Double(totalSizeBytes) * fractionDelta
        currentSpeed = bytesDelta / elapsed

        lastSpeedTimestamp = now
        lastFraction = fractionCompleted
        speedSampleCount += 1

        // Don't display speed until warmup (3 samples) to avoid initial burst
        if speedSampleCount >= 3 && currentSpeed > 0 && !isStalled {
            speedFormatted = DownloadProgress.formatSpeed(currentSpeed)
        }

        // Update status with estimated bytes
        let downloadedBytes = Double(totalSizeBytes) * fractionCompleted
        status = String(format: "%.0f MB of %.0f MB",
                        downloadedBytes / 1_000_000,
                        Double(totalSizeBytes) / 1_000_000)
    }
}
