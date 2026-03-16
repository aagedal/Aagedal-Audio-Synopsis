//
//  PlaybackTimelineView.swift
//  MeetSum
//
//  Playback timeline bar with scrubber, shown below toolbar during playback
//

import SwiftUI

struct PlaybackTimelineView: View {
    @ObservedObject var viewModel: MeetingViewModel

    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    private var displayTime: TimeInterval {
        isScrubbing ? scrubTime : viewModel.playbackCurrentTime
    }

    var body: some View {
        HStack(spacing: 12) {
            // Stop button
            Button(action: { viewModel.stopPlayback() }) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop")

            // Play/Pause button
            Button(action: {
                if viewModel.isPlaying {
                    viewModel.pausePlayback()
                } else {
                    viewModel.playRecording()
                }
            }) {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help(viewModel.isPlaying ? "Pause" : "Play")

            // Current time
            Text(AudioUtils.formatDuration(displayTime))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)

            // Timeline slider
            GeometryReader { geometry in
                let trackWidth = geometry.size.width
                let progress = viewModel.playbackDuration > 0
                    ? displayTime / viewModel.playbackDuration
                    : 0

                ZStack(alignment: .leading) {
                    // Track background
                    Capsule()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 4)

                    // Filled portion
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, trackWidth * progress), height: 4)

                    // Playhead
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 10, height: 10)
                        .offset(x: max(0, trackWidth * progress - 5))
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                }
                .frame(height: geometry.size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isScrubbing = true
                            let fraction = max(0, min(1, value.location.x / trackWidth))
                            scrubTime = fraction * viewModel.playbackDuration
                        }
                        .onEnded { value in
                            let fraction = max(0, min(1, value.location.x / trackWidth))
                            let seekTime = fraction * viewModel.playbackDuration
                            viewModel.seekPlayback(to: seekTime)
                            isScrubbing = false
                        }
                )
            }
            .frame(height: 14)

            // Total duration
            Text(AudioUtils.formatDuration(viewModel.playbackDuration))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .leading)

            // Speed button
            Button(action: { viewModel.cyclePlaybackRate() }) {
                Text(viewModel.playbackRate == 1.0 ? "1x" : "\(viewModel.playbackRate, specifier: "%g")x")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(viewModel.playbackRate == 1.0 ? .secondary : .accentColor)
                    .frame(width: 32)
            }
            .buttonStyle(.plain)
            .help("Playback speed (click to cycle)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
