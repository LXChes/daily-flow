import SwiftUI

/// A slow cyan-violet-pink sweep. Static when Reduce Motion is on or `animated` is false.
struct IridescentFill: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var animated = true

    private let period = 5.0

    var body: some View {
        if animated && !reduceMotion {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: period) / period
                sweep(phase: phase)
            }
        } else {
            LinearGradient(colors: Palette.iridescentStatic, startPoint: .leading, endPoint: .trailing)
        }
    }

    /// The gradient is two widths wide and repeats every width, so sliding it by one width loops seamlessly.
    private func sweep(phase: Double) -> some View {
        GeometryReader { proxy in
            LinearGradient(colors: Palette.iridescentLoop, startPoint: .leading, endPoint: .trailing)
                .frame(width: proxy.size.width * 2, height: proxy.size.height)
                .offset(x: -proxy.size.width * phase)
        }
        .clipped()
    }
}
