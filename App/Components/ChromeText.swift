import SwiftUI

/// Display text filled with the theme's polished-steel gradient.
struct ChromeText: View {
    @Environment(\.palette) private var palette

    let text: String
    let style: DFTextStyle

    var body: some View {
        Text(text)
            .dfStyle(style)
            .foregroundStyle(palette.chrome)
    }
}

/// The big clock. Each digit sits in a fixed cell, so the numerals never jitter while the day plays.
struct ClockText: View {
    @Environment(\.palette) private var palette
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 76

    let text: String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, character in
                Text(String(character))
                    .frame(width: character == ":" ? size * 0.34 : size * 0.72)
            }
        }
        .font(DFTextStyle.clock.font(fixedSize: size))
        .foregroundStyle(palette.chrome)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}
