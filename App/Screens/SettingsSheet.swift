import DailyFlowCore
import SwiftUI

/// Settings: notice days (with the custom-notice form), mornings, urgent timing, sorting, widgets, feel.
struct SettingsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private static let briefTimes = [7 * 60, 7 * 60 + 30, 8 * 60, 8 * 60 + 30]
    private static let nudgeTimes = [9 * 60, 12 * 60, 15 * 60, 18 * 60]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .dfStyle(.heading)
                    .foregroundStyle(palette.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                AccentPill(title: "Done") { dismiss() }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.top, 22)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    noticeSection
                    morningSection
                    urgentSection
                    sortingSection
                    widgetSection
                    feelSection

                    Text("Everything stays on your phone. Nothing is uploaded.")
                        .dfStyle(.caption)
                        .foregroundStyle(palette.inkSecondary)
                        .padding(.top, 18)
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay {
            ToastHost().padding(.bottom, 8)
        }
        .presentationDetents([.large])
        .presentationBackground(palette.sheet)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    // MARK: Sections

    private var noticeSection: some View {
        section("NOTICE DAYS") {
            SwitchRow(
                title: "Show notices on the day",
                subtitle: "e.g. \u{201C}It\u{2019}s Christmas Day\u{201D} at the top of the app and widgets",
                isOn: model.settings.noticesEnabled
            ) { value in
                model.updateSettings { $0.noticesEnabled = value }
            }
            ForEach(model.noticeRows) { row in
                RowDivider()
                NoticeRow(row: row)
            }
            RowDivider()
            AddNoticeForm()
        }
    }

    private var morningSection: some View {
        section("MORNINGS") {
            SwitchRow(
                title: "Morning brief",
                subtitle: "A gentle notification with your day ahead",
                isOn: model.settings.morningBriefEnabled
            ) { value in
                model.updateSettings { $0.morningBriefEnabled = value }
            }
            if model.settings.morningBriefEnabled {
                ChipGroup(
                    values: options(Self.briefTimes, including: model.settings.morningBriefTime),
                    label: { Fmt.clock($0) },
                    selection: model.settings.morningBriefTime
                ) { value in
                    model.updateSettings { $0.morningBriefTime = value }
                }
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            RowDivider()
            SwitchRow(
                title: "Sort yesterday\u{2019}s leftovers",
                subtitle: "Each morning: keep, push back or bin unfinished tasks",
                isOn: model.settings.leftoversTriageEnabled
            ) { value in
                model.updateSettings { $0.leftoversTriageEnabled = value }
            }
        }
        .animation(model.animated(Motion.settle), value: model.settings.morningBriefEnabled)
    }

    private var urgentSection: some View {
        section("URGENT TASKS") {
            optionRow(title: "Before a timed urgent task", subtitle: "How early to notify you") {
                ChipGroup(
                    values: ReminderTiming.leadTimeChoices,
                    label: { leadLabel($0) },
                    selection: model.settings.urgentLead
                ) { value in
                    model.updateSettings { $0.urgentLead = value }
                }
            }
            RowDivider()
            optionRow(title: "Urgent tasks with no time", subtitle: "When to nudge you") {
                ChipGroup(
                    values: options(Self.nudgeTimes, including: model.settings.untimedReminderTime),
                    label: { Fmt.clock($0) },
                    selection: model.settings.untimedReminderTime
                ) { value in
                    model.updateSettings { $0.untimedReminderTime = value }
                }
            }
        }
    }

    private var sortingSection: some View {
        section("SORTING") {
            SwitchRow(
                title: "Auto-sort my day",
                subtitle: "Orders tasks by time, urgent first. Off keeps your own order.",
                isOn: model.settings.autoSortEnabled
            ) { value in
                model.updateSettings { $0.autoSortEnabled = value }
            }
        }
    }

    private var widgetSection: some View {
        section("WIDGETS") {
            optionRow(title: "Widget style", subtitle: "Long-press any widget to give it its own style") {
                ChipGroup(
                    values: WidgetStyle.allCases,
                    label: { $0.title },
                    selection: model.settings.widgetStyle
                ) { value in
                    model.updateSettings { $0.widgetStyle = value }
                }
            }
        }
    }

    private var feelSection: some View {
        section("FEEL") {
            SwitchRow(
                title: "Haptic tick",
                subtitle: "A little tap when you tick something off",
                isOn: model.settings.hapticTickEnabled
            ) { value in
                model.updateSettings { $0.hapticTickEnabled = value }
            }
            RowDivider()
            SwitchRow(
                title: "Tick sound",
                subtitle: "A soft click when you tick something off",
                isOn: model.settings.tickSoundEnabled
            ) { value in
                model.updateSettings { $0.tickSoundEnabled = value }
            }
        }
    }

    // MARK: Helpers

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Overline(text: title)
                .padding(.top, 18)
            VStack(spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .cardSurface(fill: \.sheetCard, line: \.sheetLine)
        }
    }

    private func optionRow<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).dfStyle(.body).foregroundStyle(palette.ink)
                Text(subtitle).dfStyle(.caption).foregroundStyle(palette.inkSecondary)
            }
            content()
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func options(_ base: [Int], including current: Int) -> [Int] {
        base.contains(current) ? base : (base + [current]).sorted()
    }

    private func leadLabel(_ minutes: Int) -> String {
        minutes == 60 ? "1 hour" : "\(minutes) min"
    }
}

private struct RowDivider: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle().fill(palette.sheetLine).frame(height: 1)
    }
}

private struct NoticeRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    let row: NoticeRowItem

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .dfStyle(.body)
                    .foregroundStyle(palette.ink)
                Text(row.detail)
                    .dfStyle(.caption)
                    .foregroundStyle(palette.inkSecondary)
            }
            Spacer(minLength: 4)

            if row.isCustom {
                Button {
                    model.removeNotice(row.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(palette.inkSecondary)
                        .frame(width: Metrics.hit, height: Metrics.hit)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle(scale: 0.88))
                .accessibilityLabel("Delete \(row.title)")
            }

            Button {
                model.setNotice(row.id, enabled: !row.isEnabled)
            } label: {
                ChromeSwitch(isOn: row.isEnabled)
                    .frame(minWidth: Metrics.hit, minHeight: Metrics.hit)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.title)
            .accessibilityHint(row.detail)
            .accessibilityValue(row.isEnabled ? "On" : "Off")
            .accessibilityAddTraits(.isToggle)
        }
        .frame(minHeight: 54)
        .opacity(model.settings.noticesEnabled ? 1 : 0.4)
    }
}

/// Name, date and "every year" for a custom notice day.
private struct AddNoticeForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    @State private var name = ""
    @State private var date = Date()
    @State private var yearly = true

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a notice day")
                .dfStyle(.bodyStrong)
                .foregroundStyle(palette.ink)

            TextField(
                text: $name,
                prompt: Text("e.g. a birthday or graduation").foregroundStyle(palette.inkSecondary)
            ) {
                Text("Notice name")
            }
            .dfFont(.body)
            .foregroundStyle(palette.ink)
            .tint(palette.accent)
            .padding(.horizontal, 12)
            .frame(minHeight: 48)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            HStack(spacing: 8) {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                    .labelsHidden()
                    .tint(palette.accent)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .environment(\.calendar, model.clock.calendar)
                    .environment(\.timeZone, model.clock.calendar.timeZone)
                Spacer(minLength: 0)
                Button {
                    withAnimation(model.animated(Motion.settle)) {
                        yearly.toggle()
                    }
                } label: {
                    Text("Every year")
                        .dfStyle(.control)
                        .foregroundStyle(yearly ? palette.onAccent : palette.ink)
                        .padding(.horizontal, 14)
                        .frame(minHeight: Metrics.hit)
                        .background(yearly ? palette.accent : palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityAddTraits(yearly ? .isSelected : [])
            }

            AccentButton(title: "Add notice day", isEnabled: !trimmed.isEmpty, action: add)
        }
        .padding(.vertical, 12)
        .onAppear {
            date = model.today.startDate(in: model.clock.calendar)
        }
    }

    private func add() {
        guard !trimmed.isEmpty else { return }
        model.addNotice(
            title: trimmed,
            day: CalendarDay(date, calendar: model.clock.calendar),
            repeatsEveryYear: yearly
        )
        name = ""
    }
}
