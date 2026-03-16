//
//  ContentView.swift
//  MeetSum
//
//  Created by Truls Aagedal on 24/11/2025.
//

import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject var modelManager: ModelManager
    @ObservedObject var meetingStore: MeetingStore
    @StateObject private var viewModel: MeetingViewModel

    @State private var showingModelSetup = false
    @State private var selectedTab: Int = 0
    @State private var captureMicrophone: Bool = ModelSettings.captureMicrophone
    @State private var captureSystemAudio: Bool = ModelSettings.captureSystemAudio
    @State private var keyMonitor: Any?
    @State private var showEndRecordingConfirmation = false
    @Environment(\.openWindow) private var openWindow

    init(modelManager: ModelManager, meetingStore: MeetingStore) {
        self.modelManager = modelManager
        self.meetingStore = meetingStore
        _viewModel = StateObject(wrappedValue: MeetingViewModel(modelManager: modelManager, meetingStore: meetingStore))
    }

    var body: some View {
        mainContent
            .focusedSceneValue(\.newMeetingAction) {
                viewModel.prepareNewMeeting()
            }
            .onAppear { installKeyMonitor() }
            .onDisappear {
                if let monitor = keyMonitor {
                    NSEvent.removeMonitor(monitor)
                    keyMonitor = nil
                }
                viewModel.saveNotes()
            }
    }

    private var mainContent: some View {
        NavigationSplitView {
            SidebarView(meetingStore: meetingStore, processingMeetingIds: viewModel.processingMeetingIds, onNewMeeting: {
                viewModel.prepareNewMeeting()
            }, onImportAudio: {
                viewModel.importAudioFile()
            })
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            detailContent
        }
        .frame(minWidth: 900, minHeight: 600)
        .alert("End Recording?", isPresented: $showEndRecordingConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("End Recording", role: .destructive) {
                viewModel.stopRecording()
            }
        } message: {
            Text("This will stop the current recording and begin processing the transcription.")
        }
        .sheet(isPresented: $showingModelSetup) {
            ModelSetupView(modelManager: modelManager, isPresented: $showingModelSetup)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 20) {
                    toolbarPrincipal
                        .padding(.trailing, 4)

                    Picker("View", selection: $selectedTab) {
                        Text("Transcript").tag(0)
                        Text("Summary").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
            ToolbarItem(placement: .automatic) {
                shareButton
            }
            ToolbarItem(placement: .automatic) {
                Button(action: { openWindow(id: "settings") }) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: meetingStore.selectedMeetingId) { _, newId in
            if let id = newId, let meeting = meetingStore.meetings.first(where: { $0.id == id }) {
                viewModel.loadMeeting(meeting)
            } else if newId == nil {
                viewModel.prepareNewMeeting()
            }
        }
    }

    // MARK: - Extracted Subviews

    private var detailContent: some View {
        VStack(spacing: 0) {
            if !viewModel.isRecording && !viewModel.isPaused && !viewModel.isNewMeetingMode &&
                viewModel.recordingSession?.playbackAudioFileURL != nil {
                PlaybackTimelineView(viewModel: viewModel)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }

            MeetingDetailView(
                viewModel: viewModel,
                modelManager: modelManager,
                selectedTab: $selectedTab
            )
        }
    }

    @ViewBuilder
    private var toolbarPrincipal: some View {
        if viewModel.isRecording || viewModel.isStartingRecording {
            recordingToolbar
        } else if viewModel.isPaused {
            pausedToolbar
        } else if viewModel.isNewMeetingMode && viewModel.recordingSession?.playbackAudioFileURL == nil {
            newMeetingToolbar
        } else if viewModel.recordingSession?.playbackAudioFileURL != nil {
            playbackToolbar
        }
    }

    private var recordingToolbar: some View {
        HStack(spacing: 8) {
            Button(action: {
                if viewModel.recordingState == .recording {
                    viewModel.pauseRecording()
                }
            }) {
                HStack(spacing: 6) {
                    if viewModel.isStartingRecording {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "pause.circle.fill")
                            .foregroundColor(.orange)
                    }
                    Text(viewModel.isRecording ? viewModel.recordingTime : "Starting...")
                        .monospacedDigit()
                }
            }
            .disabled(viewModel.isStartingRecording)

            AudioVisualizerView(bands: viewModel.frequencyBands)

            Button(action: { showEndRecordingConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                    Text("End")
                }
            }
            .disabled(viewModel.isStartingRecording)
        }
    }

    private var pausedToolbar: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.continueRecording() }) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .foregroundColor(.red)
                    Text("Continue")
                }
            }

            Button(action: { showEndRecordingConfirmation = true }) {
                HStack(spacing: 6) {
                    Image(systemName: "stop.circle.fill")
                        .foregroundColor(.red)
                    Text("End Meeting")
                }
            }

            Text(viewModel.recordingTime)
                .monospacedDigit()
                .foregroundColor(.secondary)

            Text("Paused")
                .font(.caption)
                .foregroundColor(.orange)

            AudioSourceToggles(captureMicrophone: $captureMicrophone, captureSystemAudio: $captureSystemAudio)
        }
    }

    private var newMeetingToolbar: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.startRecording() }) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                    Text("Record")
                }
            }
            .disabled(!captureMicrophone && !captureSystemAudio)

            AudioSourceToggles(captureMicrophone: $captureMicrophone, captureSystemAudio: $captureSystemAudio)
        }
    }

    private var playbackToolbar: some View {
        Button(action: {
            if viewModel.isPlaying { viewModel.pausePlayback() } else { viewModel.playRecording() }
        }) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                Text(viewModel.isPlaying ? "Pause" : "Play")
            }
        }
    }

    @ViewBuilder
    private var shareButton: some View {
        if !viewModel.isRecording && !viewModel.isPaused && !viewModel.isNewMeetingMode &&
            viewModel.recordingSession != nil &&
            (!viewModel.transcription.isEmpty || !viewModel.summary.isEmpty) {
            Button(action: { viewModel.exportCombinedMarkdown() }) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .help("Export meeting as Markdown")
        }
    }

    // MARK: - Key Monitor

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let textFieldFocused: Bool = {
                guard let responder = event.window?.firstResponder else { return false }
                return responder is NSTextView || responder is NSTextField
            }()

            // Only act when a playback file is available and not recording
            guard !viewModel.isRecording && !viewModel.isPaused && !viewModel.isNewMeetingMode,
                  viewModel.recordingSession?.playbackAudioFileURL != nil else {
                return event
            }

            // Cmd+P — play/pause (works even when typing in notes)
            if event.keyCode == 35 && event.modifierFlags.contains(.command) {
                if viewModel.isPlaying { viewModel.pausePlayback() } else { viewModel.playRecording() }
                return nil
            }

            // Remaining shortcuts only work when no text field is focused
            guard !textFieldFocused else { return event }

            switch event.keyCode {
            case 49: // Space — play/pause
                if viewModel.isPlaying { viewModel.pausePlayback() } else { viewModel.playRecording() }
                return nil

            case 123: // Left arrow — seek backward
                let step: TimeInterval = event.modifierFlags.contains(.shift) ? 30 : 5
                viewModel.seekPlayback(to: viewModel.playbackCurrentTime - step)
                return nil

            case 124: // Right arrow — seek forward
                let step: TimeInterval = event.modifierFlags.contains(.shift) ? 30 : 5
                viewModel.seekPlayback(to: viewModel.playbackCurrentTime + step)
                return nil

            default:
                return event
            }
        }
    }
}

// MARK: - Audio Source Toggles

private struct AudioSourceToggles: View {
    @Binding var captureMicrophone: Bool
    @Binding var captureSystemAudio: Bool

    var body: some View {
        Button(action: {
            captureMicrophone.toggle()
            ModelSettings.captureMicrophone = captureMicrophone
        }) {
            Image(systemName: captureMicrophone ? "mic.fill" : "mic.slash")
                .foregroundColor(captureMicrophone ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .help(captureMicrophone ? "Microphone on" : "Microphone off")

        Button(action: {
            captureSystemAudio.toggle()
            ModelSettings.captureSystemAudio = captureSystemAudio
        }) {
            Image(systemName: captureSystemAudio ? "speaker.wave.2.fill" : "speaker.slash")
                .foregroundColor(captureSystemAudio ? .blue : .secondary)
        }
        .buttonStyle(.plain)
        .help(captureSystemAudio ? "System audio on (Teams, FaceTime)" : "System audio off")
    }
}

#Preview {
    ContentView(modelManager: ModelManager(), meetingStore: MeetingStore())
}
