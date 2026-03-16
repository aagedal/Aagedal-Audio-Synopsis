//
//  AudioUtils.swift
//  MeetSum
//
//  Centralized audio utilities
//

import Foundation
import AVFoundation

/// Audio utility errors
enum AudioUtilsError: LocalizedError {
    case directoryCreationFailed(String)
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let message):
            return "Directory creation failed: \(message)"
        case .fileNotFound(let message):
            return "File not found: \(message)"
        }
    }
}

struct AudioUtils {

    // MARK: - Audio Format Constants

    /// Standard audio format settings for recording (legacy, kept for reference)
    static let standardRecordingSettings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 44100,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
    ]

    /// Whisper-native recording format: 16kHz, mono, 16-bit PCM
    static let whisperRecordingFormat: AVAudioFormat = {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            fatalError("Failed to create 16kHz Int16 audio format")
        }
        return format
    }()

    /// Intermediate Float32 format for audio mixing: 16kHz, mono
    static let whisperFloat32Format: AVAudioFormat = {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        ) else {
            fatalError("Failed to create 16kHz Float32 audio format")
        }
        return format
    }()

    /// File extension for recordings
    static let recordingFileExtension = "wav"

    // MARK: - Directory Management

    /// Get or create the recordings directory in Application Support
    static func getRecordingsDirectory() throws -> URL {
        let fileManager = FileManager.default

        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            Logger.error("Could not locate Application Support directory", category: Logger.audio)
            throw AudioUtilsError.directoryCreationFailed("Could not locate Application Support directory")
        }

        let bundleID = Bundle.main.bundleIdentifier ?? "MeetSum"
        let appDirectory = appSupport.appendingPathComponent(bundleID)
        let recordingsDirectory = appDirectory.appendingPathComponent("Recordings")

        if !fileManager.fileExists(atPath: recordingsDirectory.path) {
            do {
                try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true, attributes: nil)
                Logger.info("Created recordings directory at: \(recordingsDirectory.path)", category: Logger.audio)
            } catch {
                Logger.error("Failed to create recordings directory", error: error, category: Logger.audio)
                throw AudioUtilsError.directoryCreationFailed(error.localizedDescription)
            }
        }

        return recordingsDirectory
    }

    /// Get or create the segments directory for real-time transcription
    static func getSegmentsDirectory() throws -> URL {
        let recordingsDir = try getRecordingsDirectory()
        let segmentsDir = recordingsDir.appendingPathComponent("Segments")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: segmentsDir.path) {
            try fileManager.createDirectory(at: segmentsDir, withIntermediateDirectories: true, attributes: nil)
            Logger.info("Created segments directory at: \(segmentsDir.path)", category: Logger.audio)
        }

        return segmentsDir
    }

    /// Clean up segment files
    static func cleanSegmentsDirectory() {
        do {
            let segmentsDir = try getSegmentsDirectory()
            let files = try FileManager.default.contentsOfDirectory(at: segmentsDir, includingPropertiesForKeys: nil)
            for file in files {
                try FileManager.default.removeItem(at: file)
            }
            Logger.debug("Cleaned segments directory", category: Logger.audio)
        } catch {
            Logger.error("Failed to clean segments directory", error: error, category: Logger.audio)
        }
    }

    /// Generate a unique filename for a new recording
    static func generateRecordingFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "recording_\(dateString).\(recordingFileExtension)"
    }

    /// Generate a unique filename for a high-quality playback recording
    static func generatePlaybackFilename() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd_HHmmss"
        let dateString = dateFormatter.string(from: Date())
        return "recording_\(dateString)_hq.m4a"
    }

    // MARK: - Time Formatting

    /// Format a time interval as MM:SS string
    static func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Audio Analysis

    /// Compute normalized RMS energy from Int16 PCM data.
    /// Returns 0.0–1.0 where typical speech is ~0.02–0.10, silence/room noise < 0.005.
    static func rmsEnergy(of pcmData: Data) -> Float {
        let sampleCount = pcmData.count / 2
        guard sampleCount > 0 else { return 0.0 }

        var sumSquares: Float = 0.0
        pcmData.withUnsafeBytes { rawBuffer in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<sampleCount {
                let normalized = Float(samples[i]) / Float(Int16.max)
                sumSquares += normalized * normalized
            }
        }

        return sqrtf(sumSquares / Float(sampleCount))
    }

    // MARK: - WAV File Writing

    /// Write a WAV header to a file handle for 16kHz mono 16-bit PCM
    static func writeWAVHeader(to fileHandle: FileHandle, dataSize: UInt32) {
        var header = Data()

        let sampleRate: UInt32 = 16000
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate: UInt32 = sampleRate * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign: UInt16 = numChannels * (bitsPerSample / 8)
        let chunkSize: UInt32 = 36 + dataSize

        // RIFF header
        header.append(contentsOf: "RIFF".utf8)
        header.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) })
        header.append(contentsOf: "WAVE".utf8)

        // fmt sub-chunk
        header.append(contentsOf: "fmt ".utf8)
        header.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) }) // Sub-chunk size
        header.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })  // PCM format
        header.append(contentsOf: withUnsafeBytes(of: numChannels.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian) { Array($0) })
        header.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian) { Array($0) })

        // data sub-chunk
        header.append(contentsOf: "data".utf8)
        header.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian) { Array($0) })

        fileHandle.write(header)
    }

    /// Update WAV header with final data size
    static func updateWAVHeader(at url: URL, dataSize: UInt32) {
        guard let fileHandle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? fileHandle.close() }

        let chunkSize = 36 + dataSize

        // Update RIFF chunk size at offset 4
        fileHandle.seek(toFileOffset: 4)
        fileHandle.write(Data(withUnsafeBytes(of: chunkSize.littleEndian) { Array($0) }))

        // Update data sub-chunk size at offset 40
        fileHandle.seek(toFileOffset: 40)
        fileHandle.write(Data(withUnsafeBytes(of: dataSize.littleEndian) { Array($0) }))
    }
}
