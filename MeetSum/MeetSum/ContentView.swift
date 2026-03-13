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
    @State private var spaceKeyMonitor: Any?
    @Environment(\.openWindow) private var openWindow

    init(modelManager: ModelManager, meetingStore: MeetingStore) {
        self.modelManager = modelManager
        self.meetingStore = meetingStore
        _viewModel = StateObject(wrappedValue: MeetingViewModel(modelManager: modelManager, meetingStore: meetingStore))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(meetingStore: meetingStore, processingMeetingIds: viewModel.processingMeetingIds, onNewMeeting: {
                viewModel.prepareNewMeeting()
            }, onImportAudio: {
                viewModel.importAudioFile()
            })
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            VStack(spacing: 0) {
                // Playback timeline bar
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
        .frame(minWidth: 900, minHeight: 600)
        .sheet(isPresented: $showingModelSetup) {
            ModelSetupView(modelManager: modelManager, isPresented: $showingModelSetup)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 16) {
                    // Record/Play/Stop button
                    Group {
                        if viewModel.isRecording || viewModel.isStartingRecording {
                            // While recording: Pause + End buttons
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

                                Button(action: {
                                    viewModel.stopRecording()
                                }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "stop.circle.fill")
                                            .foregroundColor(.red)
                                        Text("End")
                                    }
                                }
                                .disabled(viewModel.isStartingRecording)
                            }
                        } else if viewModel.isPaused {
                            // While paused: Continue + End Meeting + audio toggles
                            HStack(spacing: 8) {
                                Button(action: { viewModel.continueRecording() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "record.circle")
                                            .foregroundColor(.red)
                                        Text("Continue")
                                    }
                                }

                                Button(action: { viewModel.stopRecording() }) {
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
                        } else if viewModel.isNewMeetingMode && viewModel.recordingSession?.playbackAudioFileURL == nil {
                            HStack(spacing: 8) {
                                Button(action: { viewModel.startRecording() }) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "record.circle")
                                        Text("Record")
                                    }
                                }
                                .disabled(!captureMicrophone && !captureSystemAudio)

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
                        } else if viewModel.recordingSession?.playbackAudioFileURL != nil {
                            Button(action: {
                                if viewModel.isPlaying {
                                    viewModel.pausePlayback()
                                } else {
                                    viewModel.playRecording()
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: viewModel.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    Text(viewModel.isPlaying ? "Pause" : "Play")
                                }
                            }
                        }
                    }

                    // Tab picker
                    Picker("View", selection: $selectedTab) {
                        Text("Transcript").tag(0)
                        Text("Summary").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    openWindow(id: "settings")
                }) {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: meetingStore.selectedMeetingId) { oldId, newId in
            if let id = newId, let meeting = meetingStore.meetings.first(where: { $0.id == id }) {
                viewModel.loadMeeting(meeting)
            } else if newId == nil {
                viewModel.prepareNewMeeting()
            }
        }
        .onAppear {
            spaceKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Space key = keyCode 49
                guard event.keyCode == 49 else { return event }

                // Don't intercept if a text field or text view is focused
                if let responder = event.window?.firstResponder,
                   responder is NSTextView || responder is NSTextField {
                    return event
                }

                // Only act when a playback file is available and not recording
                guard !viewModel.isRecording && !viewModel.isPaused && !viewModel.isNewMeetingMode,
                      viewModel.recordingSession?.playbackAudioFileURL != nil else {
                    return event
                }

                if viewModel.isPlaying {
                    viewModel.pausePlayback()
                } else {
                    viewModel.playRecording()
                }
                return nil // consume the event
            }
        }
        .onDisappear {
            if let monitor = spaceKeyMonitor {
                NSEvent.removeMonitor(monitor)
                spaceKeyMonitor = nil
            }
        }
    }
}

#Preview {
    ContentView(modelManager: ModelManager(), meetingStore: MeetingStore())
}
