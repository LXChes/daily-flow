import SwiftUI

/// A metal-edged switch with a springy knob.
struct ChromeSwitch: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? palette.accent : palette.switchOff)
            .frame(width: 50, height: 30)
            .overlay {
                Capsule().strokeBorder(palette.bevel, lineWidth: 1)
            }
            .overlay(alignment: .leading) {
                Circle()
                    .fill(palette.knob)
                    .frame(width: 24, height: 24)
                    .shadow(color: palette.scrim, radius: 2, y: 1)
                    .padding(3)
                    .offset(x: isOn ? 20 : 0)
            }
            .animation(Motion.resolve(Motion.tick, reduceMotion: reduceMotion), value: isOn)
    }
}

/// A settings row with a title, a quiet explanation and a switch. The whole row is the touch target.
struct SwitchRow: View {
    @Environment(\.palette) private var palette

    let title: String
    var subtitle: String?
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Button {
            onChange(!isOn)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .dfStyle(.body)
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.leading)
                    if let subtitle {
                        Text(subtitle)
                            .dfStyle(.caption)
                            .foregroundStyle(palette.inkSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 8)
                ChromeSwitch(isOn: isOn)
            }
            .padding(.vertical, 8)
            .frame(minHeight: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(subtitle ?? "")
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}
