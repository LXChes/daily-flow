import DailyFlowCore
import SwiftUI

/// The drop-down that opens from the sliders button: layout, categories, theme, progress style,
/// notices on or off, and a preview of an upcoming notice day.
struct ViewSwitcherOverlay: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack(alignment: .top) {
            if model.showsViewSwitcher {
                palette.scrim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { close() }
                    .transition(.opacity)
                    .accessibilityHidden(true)

                ViewSwitcherCard(close: close)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityAddTraits(.isModal)
            }
        }
        .animation(model.animated(Motion.sheet), value: model.showsViewSwitcher)
    }

    private func close() {
        model.showsViewSwitcher = false
    }
}

private struct ViewSwitcherCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("View")
                    .dfStyle(.heading)
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                AccentPill(title: "Done", action: close)
            }

            ViewThatFits(in: .vertical) {
                groups
                ScrollView {
                    groups
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(EdgeInsets(top: 16, leading: 18, bottom: 18, trailing: 18))
        .background(palette.sheet, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(palette.bevel, lineWidth: 1))
        .shadow(color: palette.scrim, radius: 24, y: 14)
        .accessibilityAction(.escape) { close() }
    }

    private var groups: some View {
        VStack(alignment: .leading, spacing: 14) {
            group("Layout") {
                ChipGroup(
                    values: [LayoutMode.playTheDay, LayoutMode.list],
                    label: { $0.title },
                    selection: model.layout
                ) { value in
                    model.updateSettings { $0.layout = value }
                }
            }
            group("Categories") {
                ChipGroup(
                    values: CategoryMode.allCases,
                    label: { $0.title },
                    selection: model.settings.categoryMode
                ) { value in
                    model.updateSettings { $0.categoryMode = value }
                }
            }
            group("Theme") {
                ChipGroup(
                    values: ThemeMode.allCases,
                    label: { $0.title },
                    selection: model.settings.theme
                ) { value in
                    model.updateSettings { $0.theme = value }
                }
            }
            group("Progress") {
                ChipGroup(
                    values: ProgressStyle.allCases,
                    label: { $0.title },
                    selection: model.settings.progressStyle
                ) { value in
                    model.updateSettings { $0.progressStyle = value }
                }
            }
            group("Notices") {
                ChipGroup(
                    values: [true, false],
                    label: { $0 ? "On" : "Off" },
                    selection: model.settings.noticesEnabled
                ) { value in
                    model.updateSettings { $0.noticesEnabled = value }
                }
            }
            group("Preview a notice day") {
                ChipGroup(
                    values: PreviewMode.allCases,
                    label: { model.previewLabel($0) },
                    selection: model.preview
                ) { value in
                    model.setPreview(value)
                }
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .dfStyle(.captionStrong)
                .foregroundStyle(palette.inkSecondary)
            content()
        }
    }
}
