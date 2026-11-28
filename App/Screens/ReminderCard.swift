import SwiftUI

/// "Let Daily Flow remind you": shown once, so the system prompt arrives with a reason instead of
/// unannounced at first launch. Either button retires the card for good.
struct ReminderCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "bell.badge")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 36, height: 36)
                    .background(palette.accentSoft, in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Let Daily Flow remind you")
                        .dfStyle(.cardTitle)
                        .foregroundStyle(palette.ink)
                    Text("Your morning brief and urgent nudges, with Complete, Snooze and Tomorrow on the Lock Screen.")
                        .dfStyle(.caption)
                        .foregroundStyle(palette.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Button("Not now") {
                    withAnimation(model.animated(Motion.settle)) {
                        model.dismissReminderPrompt()
                    }
                }
                .dfFont(.control)
                .foregroundStyle(palette.inkSecondary)
                .padding(.horizontal, 12)
                .frame(minHeight: Metrics.hit)
                .contentShape(Rectangle())
                .buttonStyle(PressScaleStyle())

                AccentPill(title: "Allow reminders") {
                    Task { await model.requestReminders() }
                }
            }
        }
        .padding(14)
        .cardSurface()
        .accessibilityElement(children: .contain)
    }
}
