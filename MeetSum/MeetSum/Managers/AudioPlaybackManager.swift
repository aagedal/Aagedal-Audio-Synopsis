//
//  AudioPlaybackManager.swift
//  MeetSum
//
//  Manages audio playback operations
//

import Foundation
import AVFoundation
import Combine

/// Manages audio playback using AVAudioPlayer
@MainActor
class AudioPlaybackManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0.0
    @Published var duration: TimeInterval = 0.0
    @Published var error: Error?
    
    // MARK: - Private Properties

    private var audioPlayer: AVAudioPlayer?
    private var playbackURL: URL?
    private var timeUpdateTimer: Timer?
    
    // MARK: - Public Methods
    
    /// Load an audio file for playback
    /// - Parameter url: URL of the audio file
    func loadAudio(url: URL) {
        Logger.info("Loading audio file for playback: \(url.lastPathComponent)", category: Logger.audio)
        
        playbackURL = url
        
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0.0
            Logger.info("Audio file loaded successfully. Duration: \(AudioUtils.formatDuration(duration))", category: Logger.audio)
        } catch {
            Logger.error("Failed to load audio file", error: error, category: Logger.audio)
            self.error = error
        }
    }
    
    /// Play the loaded audio
    func play() {
        guard let player = audioPlayer else {
            Logger.warning("Cannot play: no audio loaded", category: Logger.audio)
            return
        }

        Logger.info("Starting audio playback", category: Logger.audio)
        player.play()
        isPlaying = true
        startTimeUpdateTimer()
    }
    
    /// Pause the audio playback
    func pause() {
        guard let player = audioPlayer else {
            Logger.warning("Cannot pause: no audio loaded", category: Logger.audio)
            return
        }

        Logger.info("Pausing audio playback", category: Logger.audio)
        player.pause()
        isPlaying = false
        stopTimeUpdateTimer()
        currentTime = player.currentTime
    }
    
    /// Stop the audio playback and reset to beginning
    func stop() {
        guard let player = audioPlayer else {
            Logger.warning("Cannot stop: no audio loaded", category: Logger.audio)
            return
        }

        Logger.info("Stopping audio playback", category: Logger.audio)
        player.stop()
        player.currentTime = 0
        isPlaying = false
        stopTimeUpdateTimer()
        currentTime = 0
    }

    /// Seek to a specific time
    func seek(to time: TimeInterval) {
        guard let player = audioPlayer else { return }
        let clampedTime = max(0, min(time, player.duration))
        player.currentTime = clampedTime
        currentTime = clampedTime
    }

    /// Unload the current audio
    func unload() {
        Logger.debug("Unloading audio player", category: Logger.audio)
        stop()
        audioPlayer = nil
        playbackURL = nil
        duration = 0
    }

    // MARK: - Timer

    private func startTimeUpdateTimer() {
        stopTimeUpdateTimer()
        timeUpdateTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let player = self.audioPlayer, self.isPlaying else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimeUpdateTimer() {
        timeUpdateTimer?.invalidate()
        timeUpdateTimer = nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPlaybackManager: AVAudioPlayerDelegate {
    
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            Logger.info("Audio playback finished", category: Logger.audio)
            isPlaying = false
            stopTimeUpdateTimer()
            currentTime = 0
        }
    }
    
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            Logger.error("Audio player decode error", error: error, category: Logger.audio)
            self.error = error
            isPlaying = false
        }
    }
}
