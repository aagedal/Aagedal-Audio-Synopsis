//
//  AudioRecordingManager.swift
//  MeetSum
//
//  Manages audio recording using AVAudioEngine with segmented output
//

import Foundation
import AVFoundation
import Combine

/// Recording lifecycle states
enum RecordingState {
    case idle
    case starting
    case recording
    case paused
}

/// Info about a completed audio segment ready for transcription
struct SegmentInfo {
    let url: URL
    let startTime: TimeInterval // offset from recording start
}

/// Manages audio recording using AVAudioEngine for real-time segment access
@MainActor
class AudioRecordingManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published var recordingState: RecordingState = .idle
    @Published var recordingTime: TimeInterval = 0.0
    @Published var currentFileURL: URL?
    @Published var currentPlaybackFileURL: URL?
    @Published var error: Error?
    /// Published when a new segment file is ready for transcription
    @Published var newSegment: SegmentInfo?
    /// True when system audio capture was requested but failed to start
    @Published var systemAudioFailed = false

    // MARK: - Private Properties

    private var audioEngine: AVAudioEngine?
    private var timer: Timer?
    private var startTime: Date?

    /// Serial queue for safe segment rotation from audio tap callback
    private let segmentQueue = DispatchQueue(label: "com.meetsum.segment", qos: .userInitiated)

    // Segment management
    private var segmentIndex: Int = 0
    private var segmentFileHandle: FileHandle?
    private var segmentDataSize: UInt32 = 0
    private var segmentURL: URL?
    private var segmentsDirectory: URL?

    // Full recording (16kHz Whisper format)
    private var recordingFileHandle: FileHandle?
    private var recordingDataSize: UInt32 = 0

    // High-quality playback recording
    private var playbackFile: AVAudioFile?

    // Cached audio converters (expensive to create — reuse across callbacks)
    private var cachedConverter: AVAudioConverter?
    private var cachedConverterSourceFormat: AVAudioFormat?
    private var cachedMixedConverter: AVAudioConverter?
    private var cachedMixedConverterSourceFormat: AVAudioFormat?

    // Segment rotation (silence-based)
    private let minSegmentDuration: TimeInterval = 5.0    // Don't split before 5s
    private let maxSegmentDuration: TimeInterval = 30.0    // Force split at 30s
    private let silenceThreshold: Float = 0.01             // Normalized RMS (~-40dB)
    private let silenceDurationRequired: TimeInterval = 0.4 // 400ms of silence to trigger
    private var segmentStartTime: Date?
    private var silenceStartTime: Date?   // When current silence period began
    private var lastSpeechTime: Date?     // Last time energy was above threshold

    // System audio capture (for mixing with microphone)
    private var systemAudioCapture: SystemAudioCapture?
    private var mixingBuffer: AudioMixingBuffer?

    // Drain timer for system-audio-only mode (no mic tap to drive writes)
    private var drainTimer: DispatchSourceTimer?

    // Pause/resume support
    private var accumulatedTime: TimeInterval = 0
    private var timeOffset: TimeInterval = 0

    // MARK: - Public Methods

    var isRecording: Bool {
        recordingState == .starting || recordingState == .recording
    }

    var isPaused: Bool {
        recordingState == .paused
    }

    func startRecording() {
        Logger.info("Starting audio recording", category: Logger.audio)

        error = nil
        systemAudioFailed = false
        guard recordingState == .idle else { return }
        recordingState = .starting
        accumulatedTime = 0
        timeOffset = 0

        let useMic = ModelSettings.captureMicrophone
        let useSystemAudio = ModelSettings.captureSystemAudio

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            // Request mic permission only when microphone is needed
            if useMic {
                let granted = await self.requestMicrophonePermission()
                guard granted else {
                    await MainActor.run {
                        self.error = NSError(domain: "AudioRecordingManager", code: 4, userInfo: [NSLocalizedDescriptionKey: "Microphone permission denied"])
                        self.recordingState = .idle
                        Logger.error("Microphone permission denied", category: Logger.audio)
                    }
                    return
                }
            }

            do {
                // Setup directories and WAV files (common to all modes)
                let recordingsDir = try AudioUtils.getRecordingsDirectory()
                let segDir = try AudioUtils.getSegmentsDirectory()
                AudioUtils.cleanSegmentsDirectory()

                let filename = AudioUtils.generateRecordingFilename()
                let fileURL = recordingsDir.appendingPathComponent(filename)

                FileManager.default.createFile(atPath: fileURL.path, contents: nil)
                let recHandle = try FileHandle(forWritingTo: fileURL)
                AudioUtils.writeWAVHeader(to: recHandle, dataSize: 0)

                let firstSegURL = segDir.appendingPathComponent("segment_000.wav")
                FileManager.default.createFile(atPath: firstSegURL.path, contents: nil)
                let segHandle = try FileHandle(forWritingTo: firstSegURL)
                AudioUtils.writeWAVHeader(to: segHandle, dataSize: 0)

                await MainActor.run {
                    self.currentFileURL = fileURL
                    self.currentPlaybackFileURL = nil
                    self.segmentsDirectory = segDir
                    self.segmentIndex = 0
                    self.playbackFile = nil
                    self.recordingFileHandle = recHandle
                    self.recordingDataSize = 0
                    self.segmentFileHandle = segHandle
                    self.segmentDataSize = 0
                    self.segmentURL = firstSegURL
                    self.segmentStartTime = Date()
                }

                // Setup microphone via AVAudioEngine (if enabled)
                var engine: AVAudioEngine?
                if useMic {
                    let (eng, inputFormat) = await MainActor.run { self.setupMicrophoneEngine() }

                    // Create high-quality AAC playback file from mic
                    let playbackFilename = AudioUtils.generatePlaybackFilename()
                    let playbackURL = recordingsDir.appendingPathComponent(playbackFilename)
                    let playbackAudioFile = try AVAudioFile(
                        forWriting: playbackURL,
                        settings: [
                            AVFormatIDKey: kAudioFormatMPEG4AAC,
                            AVSampleRateKey: inputFormat.sampleRate,
                            AVNumberOfChannelsKey: inputFormat.channelCount,
                            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
                            AVEncoderBitRateKey: 128000
                        ]
                    )

                    await MainActor.run {
                        self.currentPlaybackFileURL = playbackURL
                        self.playbackFile = playbackAudioFile
                    }

                    engine = eng
                }

                // Start system audio capture (if enabled)
                if useSystemAudio {
                    await self.startSystemAudioCapture()
                }

                // Start the engine (mic modes) or drain timer (system-only mode)
                try await self.startEngineOrDrainTimer(engine)

                await MainActor.run {
                    self.audioEngine = engine
                    self.recordingState = .recording
                    self.startTime = Date()
                    self.startTimer()

                    var sources: [String] = []
                    if useMic { sources.append("mic") }
                    if self.systemAudioCapture != nil { sources.append("system") }
                    Logger.info("Recording started [\(sources.joined(separator: "+"))] to: \(fileURL.path)", category: Logger.audio)
                }

            } catch {
                await MainActor.run {
                    Logger.error("Failed to setup recording", error: error, category: Logger.audio)
                    self.error = error
                    self.recordingState = .idle
                }
            }
        }
    }

    /// Pause recording — tears down audio engine but keeps file handles open
    func pauseRecording() {
        guard recordingState == .recording else { return }
        Logger.info("Pausing audio recording", category: Logger.audio)

        stopTimer()
        stopDrainTimer()

        // Stop engine
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        // Finalize current segment and clean up mixing state on the segment queue,
        // so in-flight tap callbacks complete before we nil out the buffer.
        segmentQueue.sync {
            self.finalizeCurrentSegment(publish: true)
            self.silenceStartTime = nil
            self.lastSpeechTime = nil
            self.cachedConverter = nil
            self.cachedConverterSourceFormat = nil
            self.cachedMixedConverter = nil
            self.cachedMixedConverterSourceFormat = nil
            self.mixingBuffer?.reset()
            self.mixingBuffer = nil
        }

        // Stop system audio capture (after segment queue is drained)
        let capture = systemAudioCapture
        systemAudioCapture = nil
        if let capture = capture {
            Task { await capture.stopCapture() }
        }

        // Update WAV header for crash safety (but don't close the handle)
        if let url = currentFileURL, recordingDataSize > 0 {
            AudioUtils.updateWAVHeader(at: url, dataSize: recordingDataSize)
        }

        // Save accumulated time
        accumulatedTime = recordingTime

        recordingState = .paused
        Logger.info("Recording paused at \(AudioUtils.formatDuration(accumulatedTime))", category: Logger.audio)
    }

    /// Resume recording from paused state
    func resumeRecording() {
        guard recordingState == .paused else { return }
        Logger.info("Resuming audio recording", category: Logger.audio)
        recordingState = .starting

        timeOffset = accumulatedTime

        let useMic = ModelSettings.captureMicrophone
        let useSystemAudio = ModelSettings.captureSystemAudio

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }

            do {
                // Setup microphone via AVAudioEngine (if enabled)
                var engine: AVAudioEngine?
                if useMic {
                    let (eng, _) = await MainActor.run { self.setupMicrophoneEngine() }
                    engine = eng
                }

                // Start system audio capture (if enabled)
                if useSystemAudio {
                    await self.startSystemAudioCapture()
                }

                // Start the engine or drain timer
                try await self.startEngineOrDrainTimer(engine)

                // Open new segment file (continuing from current index)
                await MainActor.run {
                    self.audioEngine = engine
                    self.openNewSegment()
                    self.startTime = Date()
                    self.startTimer()
                    self.recordingState = .recording

                    var sources: [String] = []
                    if useMic { sources.append("mic") }
                    if self.systemAudioCapture != nil { sources.append("system") }
                    Logger.info("Recording resumed [\(sources.joined(separator: "+"))]", category: Logger.audio)
                }
            } catch {
                await MainActor.run {
                    Logger.error("Failed to resume recording", error: error, category: Logger.audio)
                    self.error = error
                    self.recordingState = .paused
                }
            }
        }
    }

    /// Stop recording audio
    /// - Returns: URL of the 16kHz Whisper file, or nil if recording failed
    func stopRecording() -> URL? {
        Logger.info("Stopping audio recording", category: Logger.audio)

        if recordingState == .paused {
            // Already paused — just finalize the recording file
            segmentQueue.sync {
                self.finalizeRecordingFile()
                self.playbackFile = nil
            }
            recordingState = .idle
            accumulatedTime = 0
            timeOffset = 0

            let fileURL = currentFileURL
            if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
                Logger.info("Paused recording finalized. File saved at: \(url.path)", category: Logger.audio)
            }
            return fileURL
        }

        stopTimer()
        stopDrainTimer()

        // Stop engine (stops mic tap — no more reads from mixing buffer)
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        recordingState = .idle

        // Finalize files and clean up mixing state on the segment queue,
        // so in-flight tap callbacks complete before we nil out the buffer.
        segmentQueue.sync {
            self.finalizeCurrentSegment(publish: true)
            self.finalizeRecordingFile()
            self.playbackFile = nil
            self.silenceStartTime = nil
            self.lastSpeechTime = nil
            self.cachedConverter = nil
            self.cachedConverterSourceFormat = nil
            self.cachedMixedConverter = nil
            self.cachedMixedConverterSourceFormat = nil
            self.mixingBuffer?.reset()
            self.mixingBuffer = nil
        }

        // Stop system audio capture (after segment queue is drained)
        let capture = systemAudioCapture
        systemAudioCapture = nil
        if let capture = capture {
            Task { await capture.stopCapture() }
        }

        // Reset pause/resume state
        accumulatedTime = 0
        timeOffset = 0

        let fileURL = currentFileURL

        if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
            Logger.info("Audio recording stopped. File saved at: \(url.path)", category: Logger.audio)
        } else {
            Logger.warning("Audio recording stopped but file may not exist", category: Logger.audio)
        }

        return fileURL
    }

    // MARK: - Recording Setup Helpers

    /// Create an AVAudioEngine with a mic tap that writes to playback file and processes audio segments.
    /// Returns the engine and the mic input format.
    private func setupMicrophoneEngine() -> (AVAudioEngine, AVAudioFormat) {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let targetFormat = AudioUtils.whisperRecordingFormat

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.segmentQueue.async {
                try? self.playbackFile?.write(from: buffer)
                if self.mixingBuffer != nil {
                    self.processAudioBufferMixed(buffer, from: inputFormat)
                } else {
                    self.processAudioBuffer(buffer, from: inputFormat, to: targetFormat)
                }
            }
        }

        return (engine, inputFormat)
    }

    /// Start system audio capture if enabled. Logs a warning and continues if capture fails.
    private func startSystemAudioCapture() async {
        let buffer = AudioMixingBuffer(capacity: 32000) // 2 seconds at 16kHz
        let capture = SystemAudioCapture(mixingBuffer: buffer)
        do {
            try await capture.startCapture()
            await MainActor.run {
                self.mixingBuffer = buffer
                self.systemAudioCapture = capture
            }
        } catch {
            Logger.warning("System audio capture failed: \(error.localizedDescription)", category: Logger.audio)
            await MainActor.run {
                self.systemAudioFailed = true
            }
        }
    }

    /// Start the audio engine (mic mode) or drain timer (system-audio-only mode).
    private func startEngineOrDrainTimer(_ engine: AVAudioEngine?) async throws {
        if let engine = engine {
            try engine.start()
        } else {
            let hasSystemAudio = await MainActor.run { self.systemAudioCapture != nil }
            if hasSystemAudio {
                await MainActor.run { self.startDrainTimer() }
            }
        }
    }

    // MARK: - Private Methods

    /// Process an audio buffer: convert to 16kHz PCM and write to segment + full recording
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) {
        // Reuse converter if source format hasn't changed
        if cachedConverter == nil || cachedConverterSourceFormat != sourceFormat {
            cachedConverter = AVAudioConverter(from: sourceFormat, to: targetFormat)
            cachedConverterSourceFormat = sourceFormat
        }
        guard let converter = cachedConverter else { return }

        let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
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
            return buffer
        }

        guard error == nil, outputBuffer.frameLength > 0 else { return }

        // Extract raw PCM data (Int16)
        let pcmData: Data
        if let int16Data = outputBuffer.int16ChannelData {
            pcmData = Data(bytes: int16Data[0], count: Int(outputBuffer.frameLength) * 2)
        } else {
            return
        }

        // Write to full Whisper recording
        recordingFileHandle?.write(pcmData)
        recordingDataSize += UInt32(pcmData.count)

        // Write to current segment
        segmentFileHandle?.write(pcmData)
        segmentDataSize += UInt32(pcmData.count)

        checkSegmentRotation(pcmData: pcmData)
    }

    /// Process mic audio mixed with system audio: convert to Float32, mix, then write Int16 PCM
    private func processAudioBufferMixed(_ buffer: AVAudioPCMBuffer, from sourceFormat: AVAudioFormat) {
        let float32Format = AudioUtils.whisperFloat32Format

        // Reuse converter if source format hasn't changed
        if cachedMixedConverter == nil || cachedMixedConverterSourceFormat != sourceFormat {
            cachedMixedConverter = AVAudioConverter(from: sourceFormat, to: float32Format)
            cachedMixedConverterSourceFormat = sourceFormat
        }
        guard let converter = cachedMixedConverter else { return }

        let ratio = float32Format.sampleRate / sourceFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: float32Format, frameCapacity: outputFrameCount) else { return }

        var error: NSError?
        var inputConsumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil,
              outputBuffer.frameLength > 0,
              let micFloats = outputBuffer.floatChannelData else { return }
        guard let mixingBuffer = self.mixingBuffer else { return }

        let frameCount = Int(outputBuffer.frameLength)

        // Read system audio samples from ring buffer
        let systemSamples = UnsafeMutablePointer<Float>.allocate(capacity: frameCount)
        defer { systemSamples.deallocate() }
        mixingBuffer.read(into: systemSamples, count: frameCount)

        // Mix mic + system audio and convert to Int16
        var pcmBytes = Data(count: frameCount * 2)
        pcmBytes.withUnsafeMutableBytes { rawBuffer in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<frameCount {
                let mixed = micFloats[0][i] + systemSamples[i]
                let clamped = max(-1.0, min(1.0, mixed))
                int16Ptr[i] = Int16(clamped * Float(Int16.max))
            }
        }

        // Write to full Whisper recording
        recordingFileHandle?.write(pcmBytes)
        recordingDataSize += UInt32(pcmBytes.count)

        // Write to current segment
        segmentFileHandle?.write(pcmBytes)
        segmentDataSize += UInt32(pcmBytes.count)

        checkSegmentRotation(pcmData: pcmBytes)
    }

    /// Decide whether to rotate the current segment based on silence detection and duration limits.
    /// Called from all three audio write paths (mic-only, mixed, system-only drain).
    private func checkSegmentRotation(pcmData: Data) {
        guard let start = segmentStartTime else { return }
        let elapsed = Date().timeIntervalSince(start)
        let now = Date()

        let rms = AudioUtils.rmsEnergy(of: pcmData)

        if rms >= silenceThreshold {
            // Speech detected — reset silence tracking
            silenceStartTime = nil
            lastSpeechTime = now
        } else {
            // Silence detected — start tracking if not already
            if silenceStartTime == nil {
                silenceStartTime = now
            }
        }

        // Force rotate at max duration (safety valve)
        if elapsed >= maxSegmentDuration {
            finalizeCurrentSegment(publish: true)
            openNewSegment()
            silenceStartTime = nil
            return
        }

        // Rotate at natural silence boundary after minimum duration
        if elapsed >= minSegmentDuration,
           let silenceStart = silenceStartTime,
           now.timeIntervalSince(silenceStart) >= silenceDurationRequired {
            finalizeCurrentSegment(publish: true)
            openNewSegment()
            silenceStartTime = nil
        }
    }

    /// Finalize the current segment WAV file and optionally publish it
    private func finalizeCurrentSegment(publish: Bool) {
        guard let url = segmentURL else { return }

        // Close file handle
        try? segmentFileHandle?.close()
        segmentFileHandle = nil

        // Update WAV header with actual data size
        if segmentDataSize > 0 {
            AudioUtils.updateWAVHeader(at: url, dataSize: segmentDataSize)

            if publish {
                let publishURL = url
                let offset: TimeInterval
                if let segStart = segmentStartTime, let recStart = startTime {
                    offset = timeOffset + segStart.timeIntervalSince(recStart)
                } else {
                    offset = timeOffset
                }
                Task { @MainActor in
                    self.newSegment = SegmentInfo(url: publishURL, startTime: offset)
                }
            }
        } else {
            // Empty segment, remove file
            try? FileManager.default.removeItem(at: url)
        }

        segmentDataSize = 0
        segmentURL = nil
    }

    /// Open a new segment file
    private func openNewSegment() {
        segmentIndex += 1
        guard let segDir = segmentsDirectory else { return }

        let segFilename = String(format: "segment_%03d.wav", segmentIndex)
        let newURL = segDir.appendingPathComponent(segFilename)
        FileManager.default.createFile(atPath: newURL.path, contents: nil)

        do {
            let handle = try FileHandle(forWritingTo: newURL)
            AudioUtils.writeWAVHeader(to: handle, dataSize: 0)
            segmentFileHandle = handle
            segmentDataSize = 0
            segmentURL = newURL
            segmentStartTime = Date()
        } catch {
            Logger.error("Failed to open new segment file", error: error, category: Logger.audio)
        }
    }

    /// Finalize the full Whisper recording WAV file
    private func finalizeRecordingFile() {
        guard let url = currentFileURL else { return }
        try? recordingFileHandle?.close()
        recordingFileHandle = nil

        if recordingDataSize > 0 {
            AudioUtils.updateWAVHeader(at: url, dataSize: recordingDataSize)
        }
    }

    // MARK: - System-Audio-Only Drain Timer

    /// Start a timer to periodically drain the system audio ring buffer (when mic is off).
    private func startDrainTimer() {
        let timer = DispatchSource.makeTimerSource(queue: segmentQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.drainSystemAudioBuffer()
        }
        timer.resume()
        drainTimer = timer
    }

    private func stopDrainTimer() {
        drainTimer?.cancel()
        drainTimer = nil
    }

    /// Read all available system audio from the ring buffer and write to WAV files.
    private func drainSystemAudioBuffer() {
        guard let mixingBuffer = self.mixingBuffer else { return }
        let available = mixingBuffer.availableCount
        guard available > 0 else { return }

        let samples = UnsafeMutablePointer<Float>.allocate(capacity: available)
        defer { samples.deallocate() }
        mixingBuffer.read(into: samples, count: available)

        // Convert Float32 to Int16 PCM
        var pcmData = Data(count: available * 2)
        pcmData.withUnsafeMutableBytes { rawBuffer in
            let int16Ptr = rawBuffer.bindMemory(to: Int16.self)
            for i in 0..<available {
                let clamped = max(-1.0, min(1.0, samples[i]))
                int16Ptr[i] = Int16(clamped * Float(Int16.max))
            }
        }

        recordingFileHandle?.write(pcmData)
        recordingDataSize += UInt32(pcmData.count)
        segmentFileHandle?.write(pcmData)
        segmentDataSize += UInt32(pcmData.count)

        checkSegmentRotation(pcmData: pcmData)
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Logger.info("Microphone permission: \(granted ? "granted" : "denied")", category: Logger.audio)
                continuation.resume(returning: granted)
            }
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startTime else { return }
                self.recordingTime = self.accumulatedTime + Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
