//
//  MeetingDetailView.swift
//  MeetSum
//
//  Detail view for a meeting session (recording, transcript, summary)
//

import SwiftUI

struct MeetingDetailView: View {
    @ObservedObject var viewModel: MeetingViewModel
    @ObservedObject var modelManager: ModelManager
    @Binding var selectedTab: Int
    @Environment(\.openWindow) private var openWindow
    @State private var isEditingTitle = false
    @State private var editableTitle = ""
    @State private var isSearchingTranscript = false
    @State private var transcriptSearchText = ""
    @State private var currentMatchIndex = 0

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color.blue.opacity(0.05), Color.purple.opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                // Header
                header

                // No Whisper model warning
                if !modelManager.availableModels.contains(where: { $0.type == .whisper && modelManager.isModelInstalled($0.id) }) {
                    noModelBanner
                        .padding(.horizontal)
                }

                // System audio capture failure warning
                if viewModel.systemAudioFailed && (viewModel.isRecording || viewModel.isPaused) {
                    systemAudioWarning
                        .padding(.horizontal)
                }

                // Error card
                if let error = viewModel.errorMessage {
                    errorCard(error)
                        .padding(.horizontal)
                }

                // Content: tab + notes side-by-side
                HStack(alignment: .top, spacing: 16) {
                    // Tab content (transcript or summary)
                    if selectedTab == 0 {
                        transcriptTab
                    } else {
                        summaryTab
                    }

                    // Notes panel (always visible, persists across tabs)
                    NotesView(
                        text: $viewModel.notes,
                        isRecording: viewModel.isRecording || viewModel.isPaused,
                        currentTimestamp: {
                            let total = Int(viewModel.currentRecordingTimeInterval)
                            let m = total / 60
                            let s = total % 60
                            return "\(m):\(String(format: "%02d", s))"
                        },
                        onTextChange: viewModel.isNewMeetingMode ? nil : { viewModel.saveNotes() }
                    )
                    .frame(minWidth: 250, idealWidth: 300, maxWidth: 400)
                }
                .padding(.horizontal)
            }
            .padding()
        }
    }

    // MARK: - Header

    private var canEditTitle: Bool {
        viewModel.isNewMeetingMode || (!viewModel.isRecording && !viewModel.isPaused && recordingSession != nil)
    }

    private var displayTitle: String {
        viewModel.recordingSession?.title ?? viewModel.pendingTitle ?? "New Meeting"
    }

    private var recordingSession: RecordingSession? {
        viewModel.recordingSession
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                if isEditingTitle {
                    TextField("Meeting title", text: $editableTitle, onCommit: {
                        viewModel.renameMeeting(editableTitle)
                        isEditingTitle = false
                    })
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .textFieldStyle(.roundedBorder)
                    .onExitCommand { isEditingTitle = false }
                } else {
                    HStack(spacing: 6) {
                        Text(displayTitle)
                            .font(.system(size: 24, weight: .bold, design: .rounded))

                        if canEditTitle {
                            Image(systemName: "pencil")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                        }
                    }
                    .onTapGesture {
                        guard canEditTitle else { return }
                        editableTitle = displayTitle
                        isEditingTitle = true
                    }
                }
            }

            Spacer()

            if !viewModel.totalDuration.isEmpty {
                Label(viewModel.totalDuration, systemImage: "clock")
                    .font(.headline)
                    .foregroundColor(.green)
            }
        }
        .padding()
    }

    // MARK: - Transcript Tab

    private var transcriptTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isRecording || viewModel.isPaused {
                // Live transcription during recording (or paused)
                HStack {
                    Label("Live Transcript", systemImage: "text.quote")
                        .font(.headline)

                    Spacer()

                    if viewModel.isPaused {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 8, height: 8)
                            Text("Paused")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else if !viewModel.liveSegments.isEmpty {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("Transcribing...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if viewModel.liveSegments.isEmpty {
                                Text("Listening...")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding()
                            } else {
                                ForEach(viewModel.liveSegments) { segment in
                                    segmentRow(segment)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .id("transcriptBottom")
                    }
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .onChange(of: viewModel.liveSegments.count) {
                        withAnimation {
                            proxy.scrollTo("transcriptBottom", anchor: .bottom)
                        }
                    }
                }

            } else if !viewModel.transcription.isEmpty {
                // Final transcript
                HStack {
                    Label("Transcription", systemImage: "text.quote")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        viewModel.retranscribe()
                    }) {
                        Label("Redo", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isRecording || viewModel.isPaused || viewModel.isProcessing || viewModel.recordingSession?.audioFileURL == nil)
                    .help("Re-transcribe audio")

                    Button(action: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(viewModel.transcription, forType: .string)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy transcription to clipboard")

                    Button(action: {
                        viewModel.exportTranscription()
                    }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button(action: {
                        withAnimation {
                            isSearchingTranscript.toggle()
                            if !isSearchingTranscript {
                                transcriptSearchText = ""
                                currentMatchIndex = 0
                            }
                        }
                    }) {
                        Label("Search", systemImage: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Search transcript")
                }

                // Summary progress banner
                if viewModel.isSummarizing {
                    HStack(spacing: 12) {
                        if viewModel.modelLoadFraction > 0 && viewModel.modelLoadFraction < 1 {
                            ProgressView(value: viewModel.modelLoadFraction)
                                .progressViewStyle(.linear)
                                .frame(width: 100)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Generating summary...")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if !viewModel.summarizationProgress.isEmpty {
                            Text(viewModel.summarizationProgress)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(Color.purple.opacity(0.1))
                    .cornerRadius(8)
                }

                // Search bar
                if isSearchingTranscript {
                    transcriptSearchBar
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        if let segments = viewModel.recordingSession?.segments, !segments.isEmpty {
                            let hasAudio = viewModel.recordingSession?.playbackAudioFileURL != nil
                            let matchingIDs = transcriptMatchingSegmentIDs(segments)
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(segments) { segment in
                                    let matchIndex = matchingIDs.firstIndex(of: segment.id)
                                    segmentRow(segment, seekable: hasAudio, highlight: transcriptSearchText)
                                        .padding(4)
                                        .background(
                                            matchIndex != nil && matchIndex == currentMatchIndex
                                                ? Color.yellow.opacity(0.3)
                                                : matchIndex != nil
                                                    ? Color.yellow.opacity(0.1)
                                                    : Color.clear
                                        )
                                        .cornerRadius(4)
                                        .id(segment.id)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        } else {
                            // Fallback for legacy meetings without segments
                            Text(viewModel.transcription)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                    }
                    .onChange(of: currentMatchIndex) {
                        scrollToCurrentMatch(proxy: proxy)
                    }
                    .onChange(of: transcriptSearchText) {
                        currentMatchIndex = 0
                        scrollToCurrentMatch(proxy: proxy)
                    }
                }
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)

            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "mic.slash")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Start recording to see live transcription")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }

    // MARK: - Transcript Search

    private var transcriptSearchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search transcript...", text: $transcriptSearchText)
                .textFieldStyle(.roundedBorder)
                .font(.body)

            if !transcriptSearchText.isEmpty {
                let matchCount = transcriptMatchCount
                Text("\(matchCount == 0 ? "No" : "\(currentMatchIndex + 1)/\(matchCount)") match\(matchCount == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize()

                Button(action: {
                    let count = transcriptMatchCount
                    if count > 0 {
                        currentMatchIndex = (currentMatchIndex - 1 + count) % count
                    }
                }) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(transcriptMatchCount == 0)

                Button(action: {
                    let count = transcriptMatchCount
                    if count > 0 {
                        currentMatchIndex = (currentMatchIndex + 1) % count
                    }
                }) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(transcriptMatchCount == 0)
            }

            Button(action: {
                withAnimation {
                    isSearchingTranscript = false
                    transcriptSearchText = ""
                    currentMatchIndex = 0
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }

    private var transcriptMatchCount: Int {
        guard !transcriptSearchText.isEmpty,
              let segments = viewModel.recordingSession?.segments else { return 0 }
        return transcriptMatchingSegmentIDs(segments).count
    }

    private func transcriptMatchingSegmentIDs(_ segments: [TranscriptSegment]) -> [UUID] {
        guard !transcriptSearchText.isEmpty else { return [] }
        let query = transcriptSearchText.lowercased()
        return segments.filter { $0.text.lowercased().contains(query) }.map(\.id)
    }

    private func scrollToCurrentMatch(proxy: ScrollViewProxy) {
        guard !transcriptSearchText.isEmpty,
              let segments = viewModel.recordingSession?.segments else { return }
        let matchingIDs = transcriptMatchingSegmentIDs(segments)
        guard currentMatchIndex < matchingIDs.count else { return }
        withAnimation {
            proxy.scrollTo(matchingIDs[currentMatchIndex], anchor: .center)
        }
    }

    // MARK: - Segment Row

    private func segmentRow(_ segment: TranscriptSegment, seekable: Bool = false, highlight: String = "") -> some View {
        HStack(alignment: .top, spacing: 12) {
            if seekable {
                Button(action: {
                    viewModel.seekPlayback(to: segment.startTime)
                    if !viewModel.isPlaying {
                        viewModel.playRecording()
                    }
                }) {
                    Text(segment.timecode)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.blue)
                        .frame(width: 40, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .help("Jump to \(segment.timecode)")
            } else {
                Text(segment.timecode)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)
            }
            highlightedText(segment.text, highlight: highlight)
                .font(.body)
                .textSelection(.enabled)
        }
    }

    private func highlightedText(_ text: String, highlight: String) -> Text {
        guard !highlight.isEmpty else { return Text(text) }
        let query = highlight.lowercased()
        guard text.lowercased().contains(query) else { return Text(text) }

        var attributed = AttributedString(text)
        var searchStart = attributed.startIndex
        while searchStart < attributed.endIndex {
            let remaining = attributed[searchStart...]
            guard let range = remaining.range(of: highlight, options: .caseInsensitive) else { break }
            attributed[range].backgroundColor = .yellow
            attributed[range].foregroundColor = .black
            searchStart = range.upperBound
        }
        return Text(attributed)
    }

    // MARK: - Summary Tab

    private var summaryTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.isRecording || viewModel.isPaused {
                // During recording or paused
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Summary will be generated after recording stops")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if viewModel.isSummarizing {
                // Summarizing
                VStack(spacing: 16) {
                    if viewModel.modelLoadFraction > 0 && viewModel.modelLoadFraction < 1 {
                        ProgressView(value: viewModel.modelLoadFraction)
                            .progressViewStyle(.linear)
                            .frame(width: 200)
                    } else {
                        ProgressView()
                            .scaleEffect(1.5)
                    }
                    Text("Generating summary...")
                        .font(.headline)
                    Text(viewModel.summarizationProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else if !viewModel.summary.isEmpty {
                // Summary available
                HStack {
                    Label("Summary", systemImage: "sparkles")
                        .font(.headline)

                    Spacer()

                    Button(action: {
                        viewModel.resummarize()
                    }) {
                        Label("Redo", systemImage: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(viewModel.isRecording || viewModel.isPaused || viewModel.isProcessing)
                    .help("Re-summarize transcription")

                    Button(action: {
                        let cleaned = ThinkingTagParser.parse(viewModel.summary).visibleContent
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(cleaned, forType: .string)
                    }) {
                        Label("Copy", systemImage: "doc.on.doc")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Copy summary to clipboard")

                    Menu {
                        Button("Export as Text") {
                            viewModel.exportSummary()
                        }
                        Button("Export as Markdown") {
                            viewModel.exportSummaryAsMarkdown()
                        }
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                MarkdownSummaryView(rawSummary: viewModel.summary)

            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("Record a meeting to generate a summary")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .background(Color.purple.opacity(0.1))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 10)
    }

    // MARK: - No Model Banner

    private var noModelBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.yellow)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text("No Whisper Model Installed")
                    .font(.headline)
                Text("You can still record — download a Whisper model in Settings to enable transcription.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Open Settings") {
                openWindow(id: "settings")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - System Audio Warning

    private var systemAudioWarning: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.slash.fill")
                .foregroundColor(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text("System Audio Unavailable")
                    .font(.headline)
                Text("Could not capture system audio. Recording will continue with microphone only. Check that screen recording permission is granted in System Settings > Privacy & Security.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Error Card

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.title2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Error")
                    .font(.headline)
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if message.contains("not found") {
                Button("Open Settings") {
                    openWindow(id: "settings")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            Button(action: { viewModel.errorMessage = nil }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}
