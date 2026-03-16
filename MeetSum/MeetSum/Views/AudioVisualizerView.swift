//
//  AudioVisualizerView.swift
//  MeetSum
//
//  Reusable audio frequency band visualizer — 9 animated rounded rectangles
//

import SwiftUI

/// Displays 9 frequency bands as animated rounded rectangles.
/// Pass an array of 9 Float values (0.0–1.0) for each band's amplitude.
struct AudioVisualizerView: View {
    let bands: [Float]

    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2
    private let maxHeight: CGFloat = 16
    private let minHeight: CGFloat = 2
    private let cornerRadius: CGFloat = 1.5

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<9, id: \.self) { index in
                let value = index < bands.count ? CGFloat(bands[index]) : 0
                let height = minHeight + value * (maxHeight - minHeight)

                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.accentColor)
                    .frame(width: barWidth, height: height)
                    .animation(.easeOut(duration: 0.08), value: value)
            }
        }
        .frame(height: maxHeight)
    }
}
