import SwiftUI

/// "Left over from yesterday": opens the triage sheet.
struct LeftoversCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        Button {
            model.sheet = .triage
        } label: {
            HStack(spacing: 12) {
                Text("\(model.leftovers.count)")
                    .dfStyle(.cardTitle)
                    .foregroundStyle(palette.accent)
                    .frame(width: 36, height: 36)
                    .background(palette.accentSoft, in: Circle())
                    .contentTransition(.numericText())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Left over from yesterday")
                        .dfStyle(.cardTitle)
                        .foregroundStyle(palette.ink)
                        .multilineTextAlignment(.leading)
                    Text("Keep, push to tomorrow or bin")
                        .dfStyle(.caption)
                        .foregroundStyle(palette.inkSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(palette.inkSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: Metrics.hit)
            .cardSurface()
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.98))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Left over from yesterday, \(model.leftovers.count) tasks")
        .accessibilityHint("Opens the morning sort")
    }
}
