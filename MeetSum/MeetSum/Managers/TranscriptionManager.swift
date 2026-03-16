//
//  TranscriptionManager.swift
//  MeetSum
//
//  Manages Whisper transcription processing
//

import Foundation
import Combine

/// Manages transcription using Whisper CLI
@MainActor
class TranscriptionManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isTranscribing = false
    @Published var progress: String = ""
    @Published var error: Error?

    // MARK: - Dependencies

    private let modelManager: ModelManager

    // MARK: - Initialization

    init(modelManager: ModelManager) {
        self.modelManager = modelManager
    }

    // MARK: - Public Methods

    /// Transcribe an audio file using Whisper (full recording, with UI state)
    func transcribe(audioURL: URL) async -> String? {
        Logger.info("Starting transcription for: \(audioURL.lastPathComponent)", category: Logger.transcription)

        await MainActor.run {
            isTranscribing = true
            progress = "Preparing transcription..."
            error = nil
        }

        let result = await runWhisper(audioURL: audioURL, outputSuffix: "transcription")

        await MainActor.run {
            isTranscribing = false
            progress = result != nil ? "Transcription complete" : ""
        }

        return result
    }

    /// Transcribe a segment file (no UI state changes, used during recording)
    func transcribeSegment(audioURL: URL, prompt: String? = nil) async -> String? {
        Logger.info("Transcribing segment: \(audioURL.lastPathComponent)", category: Logger.transcription)
        return await runWhisper(audioURL: audioURL, outputSuffix: audioURL.deletingPathExtension().lastPathComponent, prompt: prompt)
    }

    // MARK: - Private Methods

    private func runWhisper(audioURL: URL, outputSuffix: String, prompt: String? = nil) async -> String? {
        let selectedModelId = ModelSettings.selectedWhisperModel
        guard let modelPath = modelManager.getModelPath(for: selectedModelId) else {
            Logger.error("Whisper model not found: \(selectedModelId)", category: Logger.transcription)
            await MainActor.run {
                error = ModelManagerError.modelNotFound(selectedModelId)
            }
            return nil
        }

        guard let binaryPath = Bundle.main.path(forResource: "whisper-cli", ofType: nil) else {
            Logger.error("Whisper binary not found in app bundle", category: Logger.transcription)
            await MainActor.run {
                error = NSError(domain: "TranscriptionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Whisper binary not found in app bundle"])
            }
            return nil
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let outputPath = documentsPath.appendingPathComponent("\(outputSuffix).txt").path

        Logger.info("Transcribing with model: \(modelPath.lastPathComponent)", category: Logger.transcription)

        // Run the blocking Whisper process off the main thread
        let result: Result<String, Error> = await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            var arguments = ["-m", modelPath.path, "-f", audioURL.path, "-otxt", "-of", outputPath.replacingOccurrences(of: ".txt", with: "")]
            let language = ModelSettings.transcriptionLanguage
            if language != "auto" {
                arguments += ["-l", language]
            }
            if let prompt = prompt, !prompt.isEmpty {
                // Use last ~200 characters to keep the prompt concise
                let trimmedPrompt = String(prompt.suffix(200))
                arguments += ["--prompt", trimmedPrompt]
            }
            process.arguments = arguments

            let stderrPipe = Pipe()
            let stdoutPipe = Pipe()
            process.standardError = stderrPipe
            process.standardOutput = stdoutPipe

            do {
                try process.run()

                // Read pipe data BEFORE waitUntilExit to avoid deadlock.
                // If the process writes more than the pipe buffer (~64KB) to
                // stderr/stdout, it blocks waiting for the reader. If we call
                // waitUntilExit() first, both sides block forever.
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let _ = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

                process.waitUntilExit()

                let exitCode = process.terminationStatus
                let stderrOutput = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                Logger.info("Whisper process completed with exit code: \(exitCode)", category: Logger.transcription)
                if !stderrOutput.isEmpty {
                    Logger.error("Whisper stderr: \(stderrOutput)", category: Logger.transcription)
                }

                guard exitCode == 0 else {
                    let errorDetail = stderrOutput.isEmpty ? "Exit code \(exitCode)" : stderrOutput
                    Logger.error("Whisper failed: \(errorDetail)", category: Logger.transcription)
                    return .failure(NSError(domain: "TranscriptionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Whisper transcription failed: \(errorDetail)"]))
                }

                if FileManager.default.fileExists(atPath: outputPath) {
                    let transcriptionText = try String(contentsOfFile: outputPath, encoding: .utf8)
                    let trimmed = transcriptionText.trimmingCharacters(in: .whitespacesAndNewlines)

                    Logger.info("Transcription completed. Length: \(trimmed.count) characters", category: Logger.transcription)

                    // Clean up output file
                    try? FileManager.default.removeItem(atPath: outputPath)

                    return .success(trimmed)
                } else {
                    Logger.error("Transcription output file not found at: \(outputPath)", category: Logger.transcription)
                    return .failure(NSError(domain: "TranscriptionManager", code: 3, userInfo: [NSLocalizedDescriptionKey: "Transcription output file not found. Whisper may have failed silently."]))
                }

            } catch {
                Logger.error("Failed to run Whisper process", error: error, category: Logger.transcription)
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let text):
            return text
        case .failure(let err):
            self.error = err
            return nil
        }
    }
}
