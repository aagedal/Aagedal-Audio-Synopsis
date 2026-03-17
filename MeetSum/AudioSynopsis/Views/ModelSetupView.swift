//
//  ModelSetupView.swift
//  Audio Synopsis
//
//  First-launch model setup view
//

import SwiftUI

struct ModelSetupView: View {
    @ObservedObject var modelManager: ModelManager
    @Binding var isPresented: Bool

    @State private var downloadingModels: Set<String> = []
    @State private var selectedDirectory = false

    var body: some View {
        VStack(spacing: 24) {
            Text("AI Models Required")
                .font(.title.bold())

            Text("Audio Synopsis uses AI models for transcription and summarization. Select where to store Whisper models and download the ones you need. The MLX summarization model will download automatically on first use (~5GB).")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .frame(maxWidth: 400)

            // Directory Selection
            VStack(spacing: 12) {
                if let directory = modelManager.whisperModelDirectory {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Models directory: \(directory.lastPathComponent)")
                            .font(.subheadline)
                        Spacer()
                    }
                    .padding()
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(8)
                } else {
                    Button(action: {
                        // TODO: Show directory picker
                    }) {
                        Label("Select Models Directory", systemImage: "folder.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            // Recommended Models
            VStack(alignment: .leading, spacing: 12) {
                Text("Recommended Models")
                    .font(.headline)

                ForEach(ModelMetadata.recommendedModels) { model in
                    recommendedModelRow(model)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)

            Spacer()

            // Actions
            HStack {
                Button("Skip for Now") {
                    isPresented = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    downloadRecommendedModels()
                }) {
                    if downloadingModels.isEmpty {
                        Text("Download & Continue")
                    } else {
                        let aggregate = aggregateProgress
                        VStack(spacing: 4) {
                            ProgressView(value: aggregate)
                                .progressViewStyle(.linear)
                                .frame(width: 120)
                            Text("Downloading \(Int(aggregate * 100))%...")
                                .font(.caption2)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!downloadingModels.isEmpty)
            }
        }
        .padding(32)
        .frame(width: 500, height: 600)
    }

    private func recommendedModelRow(_ model: ModelMetadata) -> some View {
        HStack {
            Image(systemName: model.type == .whisper ? "waveform" : "brain")
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.name)
                    .font(.subheadline.weight(.medium))
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if model.type == .mlx {
                Text("Auto-downloads")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if modelManager.isModelInstalled(model.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if downloadingModels.contains(model.id) {
                if let progress = modelManager.downloadProgress[model.id] {
                    VStack(alignment: .trailing, spacing: 4) {
                        if progress.isConnecting {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Connecting...")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            ProgressView(value: progress.fractionCompleted)
                                .progressViewStyle(.linear)
                                .frame(width: 120)
                            HStack(spacing: 6) {
                                Text("\(progress.downloadedFormatted) of \(progress.totalFormatted)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                if progress.bytesPerSecond > 0 {
                                    Text(progress.speedFormatted)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                } else {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            } else {
                Text(model.sizeFormatted)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }

    private var aggregateProgress: Double {
        let progresses = downloadingModels.compactMap { modelManager.downloadProgress[$0] }
        guard !progresses.isEmpty else { return 0 }
        return progresses.map(\.fractionCompleted).reduce(0, +) / Double(progresses.count)
    }

    private func downloadRecommendedModels() {
        // Only download Whisper models; MLX model auto-downloads on first use
        for model in ModelMetadata.recommendedModels where model.type == .whisper {
            downloadingModels.insert(model.id)

            Task {
                do {
                    try await modelManager.downloadModel(model)
                    await MainActor.run {
                        downloadingModels.remove(model.id)
                        if downloadingModels.isEmpty {
                            isPresented = false
                        }
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

        // If no whisper models to download, close immediately
        if downloadingModels.isEmpty {
            isPresented = false
        }
    }
}
