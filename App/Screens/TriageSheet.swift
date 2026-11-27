import DailyFlowCore
import SwiftUI

/// The morning sort: keep each leftover today, push it to tomorrow, or bin it.
struct TriageSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private var subtitle: String {
        let count = model.leftovers.count
        if count == 0 { return "Yesterday\u{2019}s leftovers are sorted." }
        let things = count == 1 ? "1 thing didn\u{2019}t" : "\(count) things didn\u{2019}t"
        return "\(things) get done. What should happen to them?"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ChromeText(text: model.greeting, style: .sheetTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityAddTraits(.isHeader)
                .padding(.top, 20)

            Text(subtitle)
                .dfStyle(.label)
                .foregroundStyle(palette.inkSecondary)
                .padding(.top, 4)
                .padding(.bottom, 12)
                .contentTransition(.opacity)
                .animation(model.animated(Motion.settle), value: subtitle)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(model.leftovers) { item in
                        LeftoverRow(item: item)
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .move(edge: .leading).combined(with: .opacity)
                            ))
                    }
                    if model.leftovers.isEmpty {
                        Text("All sorted. Have a good one.")
                            .dfStyle(.heading)
                            .foregroundStyle(palette.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 18)
                            .transition(.opacity)
                    }
                }
                .animation(model.animated(Motion.settle), value: model.leftovers)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)

            Button {
                dismiss()
            } label: {
                Text("Start my day")
                    .dfStyle(.bodyStrong)
                    .foregroundStyle(palette.background)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(palette.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(palette.bevel, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle(scale: 0.97))
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .padding(.horizontal, Metrics.gutter)
        .presentationDetents([.fraction(0.7), .large])
        .presentationBackground(palette.sheet)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }
}

private struct LeftoverRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let item: TaskItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .dfStyle(.rowTitle)
                .foregroundStyle(palette.ink)
                .lineLimit(2)
            Text(model.fromLabel(for: item))
                .dfStyle(.caption)
                .foregroundStyle(palette.inkSecondary)

            HStack(spacing: 8) {
                choiceButton(.keepToday)
                choiceButton(.tomorrow)
                choiceButton(.bin)
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Rectangle().fill(palette.sheetLine).frame(height: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func choiceButton(_ choice: LeftoverChoice) -> some View {
        let isPrimary = choice == .keepToday
        return Button {
            model.triage(item.id, choice)
        } label: {
            Text(choice.title)
                .dfStyle(.control)
                .foregroundStyle(isPrimary ? palette.onAccent : (choice == .bin ? palette.urgent : palette.ink))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, minHeight: Metrics.hit)
                .background(
                    isPrimary ? palette.accent : palette.sheetCard,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(isPrimary ? Color.clear : palette.sheetLine, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.95))
        .accessibilityLabel("\(choice.title): \(item.title)")
    }
}
