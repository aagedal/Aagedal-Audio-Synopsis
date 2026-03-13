//
//  SettingsView.swift
//  MeetSum
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

    @State private var showingWhisperDirectoryPicker = false
    @State private var showingMLXDirectoryPicker = false
    @State private var showingModelImporter = false
    @State private var downloadingModels: Set<String> = []
    @State private var selectedEngine: SummarizationEngine = ModelSettings.summarizationEngine
    @State private var customPrompt: String = ModelSettings.summarizationSystemPrompt
    @StateObject private var mlxLoader = MLXModelLoader()
    @State private var selectedWhisperModel: String = ModelSettings.selectedWhisperModel
    @State private var disableThinking: Bool = ModelSettings.disableModelThinking
    @State private var transcriptionLanguage: String = ModelSettings.transcriptionLanguage
    @State private var modelToDelete: ModelMetadata?
    @State private var maxOutputTokens: Double = Double(ModelSettings.maxOutputTokens)
    @State private var summarizationLanguage: String = ModelSettings.summarizationLanguage

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
                    installedModelsSection

                    if !modelManager.customModels.isEmpty {
                        Divider()
                        customModelsSection
                    }

                    Divider()
                    availableWhisperModelsSection
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
                    summarizationLanguageSection

                    if selectedEngine == .mlx {
                        Divider()
                        mlxModelSection
                        Divider()
                        summaryLengthSection
                        Divider()
                        contextCapacitySection
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
        }
        .frame(width: 620, height: 520)
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

            Text("Directory for MLX summarization model caches. Point this to an existing HuggingFace cache to reuse downloads from other apps.")
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

            if let activeName = (installedWhisperModels + modelManager.customModels)
                .first(where: { $0.id == selectedWhisperModel })?.name {
                Text("Active: \(activeName)")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }

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
        let isActive = selectedWhisperModel == model.id

        return HStack {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isActive ? .green : .secondary)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                    if isActive {
                        Text("Active")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.15))
                            .foregroundColor(.green)
                            .cornerRadius(4)
                    }
                }
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(model.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)

            if !isActive {
                Button("Use") {
                    selectedWhisperModel = model.id
                    ModelSettings.selectedWhisperModel = model.id
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button(action: {
                modelToDelete = model
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(isActive ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
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

            Text("Choose how meeting transcriptions are summarized.")
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

    // MARK: - MLX Model Section

    private var mlxModelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("MLX Model Selection", systemImage: "brain")
                .font(.headline)

            Text("Select a model for meeting summarization. The model will be downloaded on first use.")
                .font(.caption)
                .foregroundColor(.secondary)

            let mlxModels = ModelMetadata.allModels.filter { $0.type == .mlx }
            ForEach(mlxModels) { model in
                mlxModelRow(model)
            }

            if let error = mlxLoader.error {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    private func mlxModelRow(_ model: ModelMetadata) -> some View {
        let isSelected = ModelSettings.selectedMLXModel == (model.huggingFaceId ?? model.id)
        let isCached = isMLXModelCached(model)

        return VStack(spacing: 0) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .green : .secondary)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .font(.subheadline.weight(.medium))
                    Text(model.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(spacing: 8) {
                        Text("Size: ~\(model.sizeFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if isCached {
                            Text("Downloaded")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                }

                Spacer()

                if !isSelected {
                    Button("Select") {
                        if let hfId = model.huggingFaceId {
                            ModelSettings.selectedMLXModel = hfId
                            mlxLoader.reset()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else if mlxLoader.isLoading {
                    VStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text(mlxLoader.status)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } else if mlxLoader.isLoaded {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Ready")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                } else {
                    Button(isCached ? "Verify" : "Download") {
                        Task {
                            await mlxLoader.downloadAndLoad()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            // Cache management row for selected model
            if isSelected && isCached && !mlxLoader.isLoading {
                HStack {
                    Spacer()

                    Button("Open in Finder") {
                        if let dir = mlxModelCacheDirectory(model) {
                            NSWorkspace.shared.open(dir)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button("Clear Cache") {
                        clearMLXModelCache(model)
                        mlxLoader.reset()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(.red)
                }
                .padding(.top, 8)
            }
        }
        .padding()
        .background(isSelected ? Color.blue.opacity(0.05) : Color(NSColor.controlBackgroundColor))
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

            ForEach(modelManager.availableModels.filter { $0.type == .whisper }) { model in
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
                    ProgressView(value: progress.fractionCompleted)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(progress.downloadedFormatted) of \(progress.totalFormatted)")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Spacer()

                        if progress.bytesPerSecond > 0 {
                            Text(progress.speedFormatted)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text("\(progress.percentComplete)%")
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

    // MARK: - Data Directory Section

    private var dataDirectorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Data Directory", systemImage: "internaldrive")
                .font(.headline)

            Text("Recordings, transcripts, and meeting data are stored here.")
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
                    Text("~\(estimatedMinutes) minutes of meeting audio")
                        .foregroundColor(.secondary)
                }
                .font(.caption)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)

            Text("Longer meetings are automatically handled with multi-pass summarization, where the transcript is split into chunks and summaries are merged.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Thinking Section

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

            Text("Customize the system prompt used when generating meeting summaries.")
                .font(.caption)
                .foregroundColor(.secondary)

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
                if customPrompt != ModelSettings.defaultSummarizationPrompt {
                    Button("Reset to Default") {
                        customPrompt = ModelSettings.defaultSummarizationPrompt
                        ModelSettings.summarizationSystemPrompt = customPrompt
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - MLX Cache Helpers

    private func mlxModelCacheDirectory(_ model: ModelMetadata) -> URL? {
        guard let hfId = model.huggingFaceId else { return nil }
        guard let mlxDir = modelManager.mlxModelDirectory else { return nil }
        return mlxDir.appendingPathComponent(hfId)
    }

    private func isMLXModelCached(_ model: ModelMetadata) -> Bool {
        guard let dir = mlxModelCacheDirectory(model) else { return false }
        return FileManager.default.fileExists(atPath: dir.path)
    }

    private func clearMLXModelCache(_ model: ModelMetadata) {
        guard let dir = mlxModelCacheDirectory(model) else { return }
        do {
            try FileManager.default.removeItem(at: dir)
            Logger.info("Cleared MLX cache for \(model.name) at \(dir.path)", category: Logger.ui)
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

    func reset() {
        isLoading = false
        isLoaded = false
        status = ""
        error = nil
    }

    func downloadAndLoad() async {
        isLoading = true
        error = nil
        status = "Downloading model..."

        do {
            let config = ModelConfiguration(id: ModelSettings.selectedMLXModel)
            let _ = try await LLMModelFactory.shared.loadContainer(configuration: config) { progress in
                Task { @MainActor in
                    self.status = "Downloading: \(Int(progress.fractionCompleted * 100))%"
                }
            }

            isLoaded = true
            isLoading = false
            status = "Model ready"

        } catch {
            self.error = error.localizedDescription
            isLoading = false
            status = "Failed"
        }
    }
}
