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
                    .textFieldStyle(.plain)
                } else {
                    Text(viewModel.recordingSession?.title ?? "New Meeting")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .onTapGesture(count: 2) {
                            guard canEditTitle else { return }
                            editableTitle = viewModel.recordingSession?.title ?? "New Meeting"
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
                        viewModel.exportTranscription()
                    }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Summary progress banner
                if viewModel.isSummarizing {
                    HStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.small)
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

                ScrollView {
                    if let segments = viewModel.recordingSession?.segments, !segments.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(segments) { segment in
                                segmentRow(segment)
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

    // MARK: - Segment Row

    private func segmentRow(_ segment: TranscriptSegment) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(segment.timecode)
                .font(.caption.monospacedDigit())
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
            Text(segment.text)
                .font(.body)
                .textSelection(.enabled)
        }
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
                    ProgressView()
                        .scaleEffect(1.5)
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
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }
}
