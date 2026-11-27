import SwiftUI

extension View {
    /// A quiet card: a flat fill, a hairline, and a bevel highlight on the top-left edge.
    func cardSurface(
        fill: KeyPath<Palette, Color> = \.card,
        line: KeyPath<Palette, Color> = \.line,
        radius: CGFloat = 18
    ) -> some View {
        modifier(CardSurface(fill: fill, line: line, radius: radius))
    }
}

private struct CardSurface: ViewModifier {
    @Environment(\.palette) private var palette

    let fill: KeyPath<Palette, Color>
    let line: KeyPath<Palette, Color>
    let radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(palette[keyPath: fill], in: shape)
            .overlay(shape.strokeBorder(palette[keyPath: line], lineWidth: 1))
            .overlay(shape.strokeBorder(palette.bevel, lineWidth: 1).opacity(0.7))
    }
}

/// The round buttons in the header.
struct RoundIconButton: View {
    @Environment(\.palette) private var palette

    let systemName: String
    let label: String
    var isProminent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isProminent ? palette.onAccent : palette.ink)
                .frame(width: Metrics.hit, height: Metrics.hit)
                .background(isProminent ? palette.accent : palette.control, in: Circle())
                .overlay(Circle().strokeBorder(palette.bevel, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.92))
        .accessibilityLabel(label)
    }
}

/// Small all-caps section label.
struct Overline: View {
    @Environment(\.palette) private var palette

    let text: String

    var body: some View {
        Text(text)
            .dfStyle(.overline)
            .foregroundStyle(palette.inkSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A full-width call-to-action in the accent colour.
struct AccentButton: View {
    @Environment(\.palette) private var palette

    let title: String
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dfStyle(.bodyStrong)
                .foregroundStyle(palette.onAccent)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(palette.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.bevel, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .disabled(!isEnabled)
    }
}

/// The small accent "Done" pill that closes a sheet.
struct AccentPill: View {
    @Environment(\.palette) private var palette

    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dfStyle(.control)
                .foregroundStyle(palette.onAccent)
                .padding(.horizontal, 18)
                .frame(minHeight: Metrics.hit)
                .background(palette.accent, in: Capsule())
                .overlay(Capsule().strokeBorder(palette.bevel, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressScaleStyle())
    }
}
