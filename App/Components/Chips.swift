import SwiftUI

/// One selectable choice. The accent highlight is a matched-geometry shape, so changing the selection
/// slides the highlight across to the new chip instead of swapping colours.
struct ChoiceChip: View {
    enum Style {
        /// Sits inside a shared track.
        case track
        /// A free-standing pill with its own fill.
        case pill
    }

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    let isSelected: Bool
    let namespace: Namespace.ID
    var style: Style = .pill
    /// Fill the width the parent offers (equal-width segments).
    var fillsWidth = false
    let action: () -> Void

    private var corner: CGFloat { style == .track ? 11 : 12 }

    var body: some View {
        Button {
            withAnimation(Motion.resolve(Motion.settle, reduceMotion: reduceMotion), action)
        } label: {
            Text(label)
                .dfStyle(.control)
                .foregroundStyle(isSelected ? palette.onAccent : palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 14)
                .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: Metrics.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .fill(palette.accent)
                    .matchedGeometryEffect(id: "chip.selection", in: namespace)
            }
        }
        .background {
            if style == .pill {
                RoundedRectangle(cornerRadius: corner, style: .continuous).fill(palette.chip)
            }
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A labelled group of choices in a shared track, wrapping when the labels get long.
struct ChipGroup<Value: Hashable>: View {
    struct Option: Identifiable {
        let value: Value
        let label: String

        var id: Value { value }
    }

    @Environment(\.palette) private var palette
    @Namespace private var namespace

    let options: [Option]
    let selection: Value?
    let onSelect: (Value) -> Void
    /// One full-width option per line instead of equal segments side by side.
    var stacked = false

    init(options: [Option], selection: Value?, stacked: Bool = false, onSelect: @escaping (Value) -> Void) {
        self.stacked = stacked
        self.options = options
        self.selection = selection
        self.onSelect = onSelect
    }

    /// Builds the options from plain values and a label for each.
    init(
        values: [Value],
        label: (Value) -> String,
        selection: Value?,
        stacked: Bool = false,
        onSelect: @escaping (Value) -> Void
    ) {
        self.init(
            options: values.map { Option(value: $0, label: label($0)) },
            selection: selection,
            stacked: stacked,
            onSelect: onSelect
        )
    }

    var body: some View {
        let chips = ForEach(options) { option in
            ChoiceChip(
                label: option.label,
                isSelected: option.value == selection,
                namespace: namespace,
                style: .track,
                fillsWidth: true
            ) {
                onSelect(option.value)
            }
        }
        Group {
            if stacked {
                VStack(spacing: 4) { chips }
            } else {
                HStack(spacing: 4) { chips }
            }
        }
        .padding(4)
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A single horizontally scrolling row of pill choices (days, times, durations).
struct ChipScroller<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                content()
            }
            .padding(.horizontal, Metrics.gutter)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, -Metrics.gutter)
    }
}
