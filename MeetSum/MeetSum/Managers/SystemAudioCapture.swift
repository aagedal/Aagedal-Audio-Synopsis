//
//  SystemAudioCapture.swift
//  MeetSum
//
//  Captures system audio using ScreenCaptureKit and provides a mixing buffer
//  for combining system audio with microphone audio for transcription.
//

import Foundation
import AVFoundation
import ScreenCaptureKit

// MARK: - Audio Mixing Buffer

/// Thread-safe ring buffer for mixing system audio with microphone audio.
/// System audio is written from ScreenCaptureKit's callback queue,
/// and read from AVAudioEngine's tap callback queue.
nonisolated final class AudioMixingBuffer: @unchecked Sendable {

    private var buffer: [Float]
    private let capacity: Int
    private var writeIndex = 0
    private var readIndex = 0
    private var storedCount = 0
    private let lock = NSLock()

    init(capacity: Int) {
        self.capacity = capacity
        self.buffer = [Float](repeating: 0, count: capacity)
    }

    /// Write Float32 samples from system audio capture.
    func write(_ samples: UnsafePointer<Float>, count: Int) {
        lock.lock()
        defer { lock.unlock() }

        for i in 0..<count {
            if storedCount == capacity {
                // Buffer full — overwrite oldest sample
                readIndex = (readIndex + 1) % capacity
                storedCount -= 1
            }
            buffer[writeIndex] = samples[i]
            writeIndex = (writeIndex + 1) % capacity
            storedCount += 1
        }
    }

    /// Read up to `count` samples into `output`. Pads with silence if fewer samples are available.
    func read(into output: UnsafeMutablePointer<Float>, count: Int) {
        lock.lock()
        defer { lock.unlock() }

        let toRead = min(count, storedCount)
        for i in 0..<toRead {
            output[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        // Fill remainder with silence
        for i in toRead..<count {
            output[i] = 0
        }
        storedCount -= toRead
    }

    /// Number of samples currently available to read.
    var availableCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedCount
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        writeIndex = 0
        readIndex = 0
        storedCount = 0
    }
}

// MARK: - System Audio Capture

/// Captures system audio using ScreenCaptureKit and writes 16kHz mono Float32 samples
/// to an AudioMixingBuffer for real-time mixing with microphone audio.
nonisolated class SystemAudioCapture: @unchecked Sendable {

    private var stream: SCStream?
    private var streamOutput: AudioStreamOutput?
    private var audioConverter: AVAudioConverter?
    private var _isCapturing = false
    private let lock = NSLock()

    private(set) var isCapturing: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _isCapturing }
        set { lock.lock(); defer { lock.unlock() }; _isCapturing = newValue }
    }

    private let mixingBuffer: AudioMixingBuffer
    private let targetFormat: AVAudioFormat = {
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

    init(mixingBuffer: AudioMixingBuffer) {
        self.mixingBuffer = mixingBuffer
    }

    /// Start capturing system audio. Requires screen recording permission.
    func startCapture() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)

        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.noDisplayFound
        }

        // Filter captures the display (required) but we only use the audio
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48000
        config.channelCount = 1

        // Minimize video capture overhead since we only need audio
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false

        let output = AudioStreamOutput { [weak self] sampleBuffer in
            self?.handleAudioBuffer(sampleBuffer)
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let audioQueue = DispatchQueue(label: "com.meetsum.systemaudio", qos: .userInitiated)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: audioQueue)

        try await stream.startCapture()

        self.stream = stream
        self.streamOutput = output
        self.isCapturing = true

        Logger.info("System audio capture started", category: Logger.audio)
    }

    /// Stop capturing system audio.
    func stopCapture() async {
        guard let stream = stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
        self.streamOutput = nil
        lock.lock()
        self.audioConverter = nil
        lock.unlock()
        self.isCapturing = false

        Logger.info("System audio capture stopped", category: Logger.audio)
    }

    // MARK: - Audio Processing

    /// Convert incoming system audio to 16kHz mono Float32 and write to mixing buffer.
    private func handleAudioBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let pcmBuffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        let sourceFormat = pcmBuffer.format

        // Create or recreate converter if source format changed (thread-safe)
        lock.lock()
        if audioConverter == nil || audioConverter!.inputFormat != sourceFormat {
            audioConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        }
        guard let converter = audioConverter else { lock.unlock(); return }
        lock.unlock()

        // Convert to 16kHz mono Float32
        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(pcmBuffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        guard error == nil,
              outputBuffer.frameLength > 0,
              let floatData = outputBuffer.floatChannelData else { return }

        // Write converted samples to the mixing buffer
        mixingBuffer.write(floatData[0], count: Int(outputBuffer.frameLength))
    }

    /// Convert a CMSampleBuffer from ScreenCaptureKit into an AVAudioPCMBuffer.
    static func pcmBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
        guard let format = AVAudioFormat(streamDescription: asbdPtr),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )

        guard status == noErr else { return nil }
        return buffer
    }
}

// MARK: - Stream Output Delegate

nonisolated private class AudioStreamOutput: NSObject, SCStreamOutput {
    let handler: (CMSampleBuffer) -> Void

    init(handler: @escaping (CMSampleBuffer) -> Void) {
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        handler(sampleBuffer)
    }
}

// MARK: - Errors

nonisolated enum SystemAudioCaptureError: LocalizedError {
    case noDisplayFound
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .noDisplayFound:
            return "No display found for system audio capture"
        case .permissionDenied:
            return "Screen recording permission is required to capture system audio. Enable it in System Settings > Privacy & Security > Screen Recording."
        }
    }
}
