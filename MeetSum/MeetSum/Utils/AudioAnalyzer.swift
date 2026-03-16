//
//  AudioAnalyzer.swift
//  MeetSum
//
//  FFT-based frequency band extraction using Accelerate/vDSP
//

import Foundation
import AVFoundation
import Accelerate

/// Stateless FFT frequency band analyzer for audio visualization.
/// Extracts 9 logarithmic frequency bands from audio buffers.
struct AudioAnalyzer {

    /// Number of frequency bands produced
    static let bandCount = 9

    // MARK: - FFT Configuration

    private static let fftSize = 4096
    private static let log2n = vDSP_Length(log2(Double(fftSize)))

    /// Pre-computed Hann window (allocated once, thread-safe reads)
    private static let hannWindow: [Float] = {
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        return window
    }()

    /// FFT setup (allocated once, thread-safe reads)
    private static let fftSetup: FFTSetup = {
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("Failed to create FFT setup")
        }
        return setup
    }()

    /// Logarithmic frequency band edges in Hz
    /// Sub-bass, Bass, Low-mid, Mid, Upper-mid, Presence, Brilliance, High, Air
    private static let bandEdges: [Float] = [20, 60, 150, 400, 800, 1500, 3000, 6000, 12000, 20000]

    // MARK: - Public API

    /// Extract 9 frequency bands from an AVAudioPCMBuffer (operates on native sample rate).
    /// Returns array of 9 floats normalized to 0.0–1.0.
    static func frequencyBands(from buffer: AVAudioPCMBuffer) -> [Float] {
        guard buffer.frameLength > 0 else {
            return [Float](repeating: 0, count: bandCount)
        }

        let sampleRate = Float(buffer.format.sampleRate)

        // Get float samples — AVAudioPCMBuffer may be Float32 or Int16
        if let floatData = buffer.floatChannelData {
            return frequencyBands(from: floatData[0], count: Int(buffer.frameLength), sampleRate: sampleRate)
        }

        // Int16 format — convert to float
        if let int16Data = buffer.int16ChannelData {
            let frameCount = Int(buffer.frameLength)
            var floatSamples = [Float](repeating: 0, count: frameCount)
            for i in 0..<frameCount {
                floatSamples[i] = Float(int16Data[0][i]) / Float(Int16.max)
            }
            return floatSamples.withUnsafeBufferPointer { ptr in
                frequencyBands(from: ptr.baseAddress!, count: frameCount, sampleRate: sampleRate)
            }
        }

        return [Float](repeating: 0, count: bandCount)
    }

    /// Extract 9 frequency bands from raw Float32 samples.
    /// Used by the system-audio-only drain path.
    static func frequencyBands(from samples: UnsafePointer<Float>, count: Int, sampleRate: Float) -> [Float] {
        guard count > 0 else {
            return [Float](repeating: 0, count: bandCount)
        }

        let frameCount = min(count, fftSize)

        // Copy samples and apply Hann window
        var windowed = [Float](repeating: 0, count: fftSize)
        for i in 0..<frameCount {
            windowed[i] = samples[i]
        }
        vDSP_vmul(windowed, 1, hannWindow, 1, &windowed, 1, vDSP_Length(fftSize))

        // Pack into split complex format for FFT
        let halfN = fftSize / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)
        var magnitudes = [Float](repeating: 0, count: halfN)

        realPart.withUnsafeMutableBufferPointer { realBuf in
            imagPart.withUnsafeMutableBufferPointer { imagBuf in
                var splitComplex = DSPSplitComplex(realp: realBuf.baseAddress!, imagp: imagBuf.baseAddress!)

                windowed.withUnsafeBufferPointer { windowedBuf in
                    windowedBuf.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { complexPtr in
                        vDSP_ctoz(complexPtr, 2, &splitComplex, 1, vDSP_Length(halfN))
                    }
                }

                // Forward FFT
                vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))

                // Compute magnitudes squared
                vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(halfN))
            }
        }

        // Scale by 1/(2*N) to normalize
        var scale = 1.0 / Float(2 * fftSize)
        vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))

        // Sum magnitudes into frequency bands
        let binResolution = sampleRate / Float(fftSize)

        var bands = [Float](repeating: 0, count: bandCount)
        for band in 0..<bandCount {
            let lowFreq = bandEdges[band]
            let highFreq = bandEdges[band + 1]

            let lowBin = max(1, Int(lowFreq / binResolution))
            let highBin = min(halfN - 1, Int(highFreq / binResolution))

            guard lowBin <= highBin else { continue }

            var sum: Float = 0
            let binCount = vDSP_Length(highBin - lowBin + 1)
            vDSP_sve(Array(magnitudes[lowBin...highBin]), 1, &sum, binCount)

            // RMS-like: sqrt of mean magnitude
            let mean = sum / Float(binCount)
            let amplitude = sqrtf(mean)

            // Convert to dB, normalize with -60dB floor
            let db = amplitude > 0 ? 20.0 * log10f(amplitude) : -60.0
            bands[band] = max(0.0, min(1.0, (db + 60.0) / 60.0))
        }

        return bands
    }
}
