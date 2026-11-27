import SwiftUI

/// Wordmark, date line and the three round buttons.
struct HeaderView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                ChromeText(text: "DAILY", style: .wordmark)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
                    .accessibilityLabel("Daily Flow")
                    .accessibilityAddTraits(.isHeader)
                Text(model.dateLine)
                    .dfStyle(.label)
                    .foregroundStyle(palette.inkSecondary)
                    .contentTransition(.opacity)
                    .animation(model.animated(Motion.settle), value: model.dateLine)
            }
            .layoutPriority(1)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                RoundIconButton(systemName: "slider.horizontal.3", label: "Change view") {
                    model.showsViewSwitcher = true
                }
                RoundIconButton(systemName: "gearshape", label: "Settings") {
                    model.sheet = .settings
                }
                RoundIconButton(systemName: "plus", label: "Add a task", isProminent: true) {
                    model.sheet = .add
                }
            }
        }
    }
}
