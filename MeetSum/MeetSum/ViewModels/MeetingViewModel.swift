//
//  MeetingViewModel.swift
//  MeetSum
//
//  Main ViewModel coordinating all operations
//

import Foundation
import Combine
import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// Main ViewModel that coordinates recording, transcription, and summarization
@MainActor
class MeetingViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var recordingSession: RecordingSession?
    @Published var isProcessing = false
    @Published var errorMessage: String?
    @Published var recordingTime: String = "00:00"
    @Published var totalDuration: String = ""
    @Published var liveTranscription: String = ""
    @Published var isNewMeetingMode = true
    @Published var liveSegments: [TranscriptSegment] = []
    @Published var notes: String = ""
    @Published var isSummarizing = false
    @Published var summarizationProgress: String = ""
    @Published var processingMeetingIds: Set<UUID> = []

    // MARK: - Managers

    private let modelManager: ModelManager
    private let recordingManager = AudioRecordingManager()
    private let playbackManager = AudioPlaybackManager()
    let transcriptionManager: TranscriptionManager
    let summarizationManager: SummarizationManager
    private let meetingStore: MeetingStore

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private var segmentQueue: [(url: URL, startTime: TimeInterval)] = []
    private var isProcessingSegment = false

    // MARK: - Computed Properties

    var isRecording: Bool {
        recordingManager.isRecording
    }

    var isPaused: Bool {
        recordingManager.isPaused
    }

    var isStartingRecording: Bool {
        recordingManager.recordingState == .starting
    }

    var recordingState: RecordingState {
        recordingManager.recordingState
    }

    var isPlaying: Bool {
        playbackManager.isPlaying
    }

    var currentRecordingTimeInterval: TimeInterval {
        recordingManager.recordingTime
    }

    var transcription: String {
        recordingSession?.transcription ?? ""
    }

    var summary: String {
        recordingSession?.summary ?? ""
    }

    // MARK: - Initialization

    init(modelManager: ModelManager, meetingStore: MeetingStore) {
        self.modelManager = modelManager
        self.meetingStore = meetingStore
        self.transcriptionManager = TranscriptionManager(modelManager: modelManager)
        self.summarizationManager = SummarizationManager(modelManager: modelManager)

        Logger.info("MeetingViewModel initialized", category: Logger.ui)
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Forward recording state changes to trigger UI updates
        recordingManager.$recordingState
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Forward playback state changes to trigger UI updates
        playbackManager.$isPlaying
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        // Bind recording time
        recordingManager.$recordingTime
            .map { AudioUtils.formatDuration($0) }
            .assign(to: &$recordingTime)

        // Bind errors
        recordingManager.$error
            .compactMap { $0?.localizedDescription }
            .assign(to: &$errorMessage)

        playbackManager.$error
            .compactMap { $0?.localizedDescription }
            .assign(to: &$errorMessage)

        transcriptionManager.$error
            .compactMap { $0?.localizedDescription }
            .assign(to: &$errorMessage)

        summarizationManager.$error
            .compactMap { $0?.localizedDescription }
            .assign(to: &$errorMessage)

        // Bind processing state
        Publishers.CombineLatest(transcriptionManager.$isTranscribing, summarizationManager.$isSummarizing)
            .map { $0 || $1 }
            .assign(to: &$isProcessing)

        // Forward summarization state
        summarizationManager.$isSummarizing
            .assign(to: &$isSummarizing)

        summarizationManager.$progress
            .assign(to: &$summarizationProgress)

        // Observe new segments for real-time transcription
        recordingManager.$newSegment
            .compactMap { $0 }
            .sink { [weak self] segment in
                self?.enqueueSegment(segment.url, startTime: segment.startTime)
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording Commands

    func startRecording() {
        Logger.info("User started recording", category: Logger.ui)
        liveTranscription = ""
        liveSegments = []
        segmentQueue = []
        isProcessingSegment = false
        recordingManager.startRecording()
    }

    func stopRecording() {
        Logger.info("User stopped recording", category: Logger.ui)

        // Capture duration before stopping (stopRecording resets accumulatedTime)
        let duration = recordingManager.recordingTime

        guard let audioURL = recordingManager.stopRecording() else {
            Logger.error("Failed to get audio file URL after stopping recording", category: Logger.ui)
            errorMessage = "Failed to save recording"
            return
        }
        totalDuration = AudioUtils.formatDuration(duration)

        // Create session with filename-based storage
        let audioFilename = audioURL.lastPathComponent
        let playbackFilename = recordingManager.currentPlaybackFileURL?.lastPathComponent
        recordingSession = RecordingSession(
            audioFilename: audioFilename,
            playbackAudioFilename: playbackFilename,
            duration: duration,
            notes: notes
        )

        Logger.info("Recording session created with duration: \(totalDuration)", category: Logger.ui)

        // Load HQ file for playback (falls back to whisper file for old recordings)
        if let playbackURL = recordingManager.currentPlaybackFileURL {
            playbackManager.loadAudio(url: playbackURL)
        } else {
            playbackManager.loadAudio(url: audioURL)
        }

        // Wait for in-flight segments, then finalize
        Task {
            await waitForPendingSegments()

            // Set transcription and segments from live data
            recordingSession?.transcription = liveTranscription
            recordingSession?.segments = liveSegments

            // Save meeting immediately so it appears in sidebar
            guard let session = recordingSession else { return }
            let meetingId = session.id
            meetingStore.addMeeting(session)
            meetingStore.selectedMeetingId = meetingId
            isNewMeetingMode = false

            // Start summarization and update meeting when done
            guard !liveTranscription.isEmpty else { return }
            processingMeetingIds.insert(meetingId)
            defer { processingMeetingIds.remove(meetingId) }

            if let summaryText = await summarizationManager.summarize(transcription: liveTranscription, notes: notes) {
                updateMeetingInStore(id: meetingId) { $0.summary = summaryText }
                Logger.info("Processing pipeline completed successfully", category: Logger.processing)
            } else {
                Logger.error("Summarization failed", category: Logger.processing)
                errorMessage = "Summarization failed"
            }
        }
    }

    // MARK: - Playback Commands

    func playRecording() {
        Logger.info("User started playback", category: Logger.ui)
        if let url = recordingSession?.playbackAudioFileURL {
            playbackManager.loadAudio(url: url)
        }
        playbackManager.play()
    }

    func pausePlayback() {
        Logger.info("User paused playback", category: Logger.ui)
        playbackManager.pause()
    }

    func pauseRecording() {
        Logger.info("User paused recording", category: Logger.ui)
        recordingManager.pauseRecording()
    }

    func continueRecording() {
        Logger.info("User continuing recording", category: Logger.ui)
        recordingManager.resumeRecording()
    }

    // MARK: - Meeting Navigation

    func prepareNewMeeting() {
        guard !isRecording && !isPaused else { return }
        Logger.info("Preparing new meeting", category: Logger.ui)
        playbackManager.unload()
        recordingSession = nil
        totalDuration = ""
        errorMessage = nil
        liveTranscription = ""
        liveSegments = []
        notes = ""
        isNewMeetingMode = true
        meetingStore.selectedMeetingId = nil
    }

    func loadMeeting(_ meeting: RecordingSession) {
        guard !isRecording && !isPaused else { return }
        guard recordingSession?.id != meeting.id else { return }
        Logger.info("Loading meeting: \(meeting.title)", category: Logger.ui)
        playbackManager.unload()

        recordingSession = meeting
        totalDuration = meeting.duration > 0 ? AudioUtils.formatDuration(meeting.duration) : ""
        liveTranscription = ""
        liveSegments = []
        notes = meeting.notes
        errorMessage = nil
        isNewMeetingMode = false

        // Load audio for playback if available (prefer HQ file)
        if let audioURL = meeting.playbackAudioFileURL {
            playbackManager.loadAudio(url: audioURL)
        }
    }

    // MARK: - Notes & Title

    func saveNotes() {
        guard let id = recordingSession?.id else { return }
        updateMeetingInStore(id: id) { $0.notes = self.notes }
    }

    func renameMeeting(_ newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let id = recordingSession?.id, !isNewMeetingMode {
            // Saved meeting — update via store
            meetingStore.renameMeeting(id: id, newTitle: trimmed)
            recordingSession?.title = trimmed
        } else {
            // New meeting mode — update session directly
            recordingSession?.title = trimmed
        }
    }

    // MARK: - Import Audio

    func importAudioFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an audio file to import"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.processImportedAudio(url)
            }
        }
    }

    private func processImportedAudio(_ sourceURL: URL) async {
        Logger.info("Importing audio file: \(sourceURL.lastPathComponent)", category: Logger.ui)

        do {
            let recordingsDir = try AudioUtils.getRecordingsDirectory()
            let stem = sourceURL.deletingPathExtension().lastPathComponent
            let ext = sourceURL.pathExtension

            var destFilename = sourceURL.lastPathComponent
            var destURL = recordingsDir.appendingPathComponent(destFilename)

            // Avoid overwriting existing files
            if FileManager.default.fileExists(atPath: destURL.path) {
                destFilename = "\(stem)_\(UUID().uuidString.prefix(8)).\(ext)"
                destURL = recordingsDir.appendingPathComponent(destFilename)
            }

            try FileManager.default.copyItem(at: sourceURL, to: destURL)

            // Get audio duration
            var duration: TimeInterval = 0
            if let player = try? AVAudioPlayer(contentsOf: destURL) {
                duration = player.duration
            }

            let session = RecordingSession(
                title: stem,
                audioFilename: destFilename,
                duration: duration
            )
            let meetingId = session.id

            recordingSession = session
            totalDuration = duration > 0 ? AudioUtils.formatDuration(duration) : ""
            liveTranscription = ""
            liveSegments = []
            isNewMeetingMode = false

            // Load for playback
            playbackManager.loadAudio(url: destURL)

            // Save to store immediately
            meetingStore.addMeeting(session)
            meetingStore.selectedMeetingId = meetingId

            // Transcribe and summarize in background
            processingMeetingIds.insert(meetingId)
            defer { processingMeetingIds.remove(meetingId) }

            if let text = await transcriptionManager.transcribe(audioURL: destURL) {
                updateMeetingInStore(id: meetingId) { $0.transcription = text }

                if let summaryText = await summarizationManager.summarize(transcription: text, notes: "") {
                    updateMeetingInStore(id: meetingId) { $0.summary = summaryText }
                }
            }
        } catch {
            Logger.error("Failed to import audio", error: error, category: Logger.ui)
            errorMessage = "Failed to import audio: \(error.localizedDescription)"
        }
    }

    // MARK: - Export Commands

    func exportTranscription() {
        guard !transcription.isEmpty else { return }
        Logger.info("User exporting transcription", category: Logger.ui)
        exportText(transcription, filename: "transcription.txt")
    }

    func exportSummary() {
        guard !summary.isEmpty else { return }
        Logger.info("User exporting summary as text", category: Logger.ui)
        let cleaned = ThinkingTagParser.parse(summary).visibleContent
        exportText(cleaned, filename: "summary.txt")
    }

    func exportSummaryAsMarkdown() {
        guard !summary.isEmpty else { return }
        Logger.info("User exporting summary as markdown", category: Logger.ui)
        let cleaned = ThinkingTagParser.parse(summary).visibleContent
        exportFile(cleaned, filename: "summary.md", contentType: UTType(filenameExtension: "md", conformingTo: .text) ?? .plainText)
    }

    // MARK: - Redo Commands

    func retranscribe() {
        guard let session = recordingSession, let audioURL = session.audioFileURL else {
            errorMessage = "No audio file available for re-transcription"
            return
        }
        let meetingId = session.id
        Logger.info("Re-transcribing audio", category: Logger.ui)

        processingMeetingIds.insert(meetingId)

        Task {
            defer { processingMeetingIds.remove(meetingId) }

            guard let text = await transcriptionManager.transcribe(audioURL: audioURL) else {
                errorMessage = "Re-transcription failed"
                return
            }

            updateMeetingInStore(id: meetingId) { $0.transcription = text }
        }
    }

    func resummarize() {
        guard let session = recordingSession, !session.transcription.isEmpty else {
            errorMessage = "No transcription available for re-summarization"
            return
        }
        let meetingId = session.id
        let transcriptionText = session.transcription
        let notesText = session.notes
        Logger.info("Re-summarizing transcription", category: Logger.ui)

        processingMeetingIds.insert(meetingId)

        Task {
            defer { processingMeetingIds.remove(meetingId) }

            guard let summaryText = await summarizationManager.summarize(transcription: transcriptionText, notes: notesText) else {
                errorMessage = "Re-summarization failed"
                return
            }

            updateMeetingInStore(id: meetingId) { $0.summary = summaryText }
        }
    }

    // MARK: - Segment Processing

    private func enqueueSegment(_ url: URL, startTime: TimeInterval) {
        segmentQueue.append((url: url, startTime: startTime))
        processNextSegment()
    }

    private func processNextSegment() {
        guard !isProcessingSegment, !segmentQueue.isEmpty else { return }
        isProcessingSegment = true

        let segment = segmentQueue.removeFirst()

        Task {
            if let text = await transcriptionManager.transcribeSegment(audioURL: segment.url) {
                let transcriptSegment = TranscriptSegment(startTime: segment.startTime, text: text)
                liveSegments.append(transcriptSegment)

                if !liveTranscription.isEmpty {
                    liveTranscription += "\n"
                }
                liveTranscription += text
            }

            // Clean up segment file
            try? FileManager.default.removeItem(at: segment.url)

            isProcessingSegment = false
            processNextSegment()
        }
    }

    private func waitForPendingSegments() async {
        // Wait until all queued segments are processed
        while isProcessingSegment || !segmentQueue.isEmpty {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
    }

    // MARK: - Private Methods

    /// Update a meeting in the store by ID, and sync to recordingSession if still viewing it
    private func updateMeetingInStore(id: UUID, mutate: (inout RecordingSession) -> Void) {
        if var meeting = meetingStore.meetings.first(where: { $0.id == id }) {
            mutate(&meeting)
            meetingStore.updateMeeting(meeting)

            // Sync to local session if still viewing this meeting
            if recordingSession?.id == id {
                recordingSession = meeting
            }
        }
    }

    private func exportText(_ text: String, filename: String) {
        exportFile(text, filename: filename, contentType: .text)
    }

    private func exportFile(_ text: String, filename: String, contentType: UTType) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [contentType]
        savePanel.nameFieldStringValue = filename
        savePanel.begin { response in
            if response == .OK, let url = savePanel.url {
                do {
                    try text.write(to: url, atomically: true, encoding: .utf8)
                    Logger.info("Exported file to: \(url.path)", category: Logger.ui)
                } catch {
                    Logger.error("Failed to export file", error: error, category: Logger.ui)
                    self.errorMessage = "Failed to export file: \(error.localizedDescription)"
                }
            }
        }
    }
}
