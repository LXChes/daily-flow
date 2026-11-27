import DailyFlowCore
import SwiftUI

/// The add sheet: name (auto-categorised), day, optional time, optional length, urgent.
struct AddTaskSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    private enum DayChoice: Hashable {
        case quick(Int)
        case custom
    }

    private enum TimeChoice: Hashable {
        case anytime
        case preset(Int)
        case custom
    }

    private static let timePresets = [9 * 60, 13 * 60, 18 * 60]

    @State private var title = ""
    @State private var categoryOverride: TaskCategory?
    @State private var dayChoice: DayChoice = .quick(0)
    @State private var customDate = Date()
    @State private var showsCalendar = false
    @State private var timeChoice: TimeChoice = .anytime
    @State private var customTime = Date()
    @State private var duration: Int?
    @State private var isUrgent = false

    @Namespace private var dayNamespace
    @Namespace private var timeNamespace
    @Namespace private var durationNamespace

    // MARK: Derived

    private var trimmed: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canAdd: Bool { !trimmed.isEmpty }
    private var category: TaskCategory { categoryOverride ?? TaskCategoriser.category(for: trimmed) }
    private var quickDays: [CalendarDay] { DayRollover.quickPickDays(from: model.today) }

    private var selectedDay: CalendarDay {
        switch dayChoice {
        case .quick(let index):
            let days = quickDays
            return days.indices.contains(index) ? days[index] : model.today
        case .custom:
            return CalendarDay(customDate, calendar: model.clock.calendar)
        }
    }

    private var startMinute: Int? {
        switch timeChoice {
        case .anytime: return nil
        case .preset(let minute): return minute
        case .custom: return MinuteOfDay.of(customTime, calendar: model.clock.calendar)
        }
    }

    private var categoryNote: String {
        if categoryOverride != nil { return "set by you" }
        return trimmed.isEmpty ? "type to see" : "auto \u{00B7} tap to change"
    }

    private var endsLabel: String {
        guard let duration else { return "optional" }
        guard let startMinute else { return "blocks out time on the day" }
        return "ends \(Fmt.clockEnd(startMinute + duration))"
    }

    private func dayLabel(_ index: Int, _ day: CalendarDay) -> String {
        if index == 0 { return "Today" }
        if index == 1 { return "Tomorrow" }
        return DateText.chip(day, calendar: model.clock.calendar)
    }

    private var addTitle: String {
        guard canAdd else { return "Type a task first" }
        let day = selectedDay
        let away = day.days(since: model.today)
        if away == 0 { return "Add to today" }
        if away == 1 { return "Add to tomorrow" }
        return "Add to " + DateText.long(day, calendar: model.clock.calendar)
    }

    private func durationLabel(_ minutes: Int) -> String {
        minutes == 90 ? "1\u{00BD}h" : Fmt.duration(minutes)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    nameField
                    categoryRow
                    dayRow
                    timeRow
                    durationRow
                    urgentRow
                }
                .padding(.horizontal, Metrics.gutter)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)

            AccentButton(title: addTitle, isEnabled: canAdd, action: add)
                .padding(.horizontal, Metrics.gutter)
                .padding(.top, 8)
                .padding(.bottom, 12)
        }
        .presentationDetents([.large])
        .presentationBackground(palette.sheet)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var header: some View {
        HStack {
            Text("Add a task")
                .dfStyle(.heading)
                .foregroundStyle(palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Cancel") { dismiss() }
                .dfFont(.control)
                .foregroundStyle(palette.inkSecondary)
                .frame(minHeight: Metrics.hit)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.top, 22)
        .padding(.bottom, 4)
    }

    private func fieldLabel(_ text: String, trailing: String? = nil) -> some View {
        HStack {
            Text(text)
                .dfStyle(.captionStrong)
                .foregroundStyle(palette.inkSecondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .dfStyle(.captionStrong)
                    .foregroundStyle(palette.inkSecondary)
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("What needs doing?")
            TextField(
                text: $title,
                prompt: Text("e.g. Essay plan, buy milk, call a friend").foregroundStyle(palette.inkSecondary)
            ) {
                Text("What needs doing?")
            }
            .dfFont(.rowTitle)
            .foregroundStyle(palette.ink)
            .tint(palette.accent)
            .submitLabel(.done)
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(palette.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var categoryRow: some View {
        HStack(spacing: 8) {
            Text("Sorts itself into")
                .dfStyle(.label)
                .foregroundStyle(palette.inkSecondary)
            Menu {
                ForEach(TaskCategory.allCases) { option in
                    Button(option.title) { categoryOverride = option }
                }
                if categoryOverride != nil {
                    Button("Let it sort itself") { categoryOverride = nil }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle().fill(palette.category(category)).frame(width: 8, height: 8)
                    Text(category.title).dfStyle(.captionStrong)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 12)
                .frame(minHeight: Metrics.hit)
                .background(palette.chip, in: Capsule())
            }
            .accessibilityLabel("Category: \(category.title)")
            Text(categoryNote)
                .dfStyle(.label)
                .foregroundStyle(palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.top, 8)
    }

    private var dayRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("Which day")
            ChipScroller {
                ForEach(Array(quickDays.enumerated()), id: \.offset) { index, day in
                    ChoiceChip(
                        label: dayLabel(index, day),
                        isSelected: dayChoice == .quick(index),
                        namespace: dayNamespace
                    ) {
                        dayChoice = .quick(index)
                        showsCalendar = false
                    }
                }
                ChoiceChip(
                    label: dayChoice == .custom
                        ? "Other \u{00B7} " + DateText.medium(selectedDay, calendar: model.clock.calendar)
                        : "Other",
                    isSelected: dayChoice == .custom,
                    namespace: dayNamespace
                ) {
                    dayChoice = .custom
                    showsCalendar.toggle()
                }
            }
            if showsCalendar {
                DatePicker(
                    "Date",
                    selection: $customDate,
                    in: model.today.startDate(in: model.clock.calendar)...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "en_GB"))
                .environment(\.calendar, model.clock.calendar)
                .environment(\.timeZone, model.clock.calendar.timeZone)
                .labelsHidden()
                .tint(palette.accent)
                .padding(8)
                .background(palette.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 8)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .animation(model.animated(Motion.settle), value: showsCalendar)
    }

    private var timeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("Time (optional)")
            ChipScroller {
                ChoiceChip(
                    label: "Any time",
                    isSelected: timeChoice == .anytime,
                    namespace: timeNamespace
                ) {
                    timeChoice = .anytime
                }
                ForEach(Self.timePresets, id: \.self) { minute in
                    ChoiceChip(
                        label: Fmt.clock(minute),
                        isSelected: timeChoice == .preset(minute),
                        namespace: timeNamespace
                    ) {
                        timeChoice = .preset(minute)
                    }
                }
                ChoiceChip(
                    label: "Custom",
                    isSelected: timeChoice == .custom,
                    namespace: timeNamespace
                ) {
                    if timeChoice != .custom {
                        let nextHour = min((Int(model.liveMinute) / 60 + 1) * 60, 23 * 60)
                        customTime = model.today.date(atMinute: nextHour, in: model.clock.calendar)
                    }
                    timeChoice = .custom
                }
                if timeChoice == .custom {
                    DatePicker("Time", selection: $customTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .tint(palette.accent)
                        .frame(minHeight: Metrics.hit)
                }
            }
        }
    }

    private var durationRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            fieldLabel("How long", trailing: endsLabel)
            ChipScroller {
                stepper
                ChoiceChip(
                    label: "None",
                    isSelected: duration == nil,
                    namespace: durationNamespace
                ) {
                    duration = nil
                }
                ForEach(DurationRules.quickPicks, id: \.self) { minutes in
                    ChoiceChip(
                        label: durationLabel(minutes),
                        isSelected: duration == minutes,
                        namespace: durationNamespace
                    ) {
                        duration = minutes
                    }
                }
            }
        }
    }

    private var stepper: some View {
        HStack(spacing: 0) {
            stepButton(systemName: "minus", label: "Shorter by 15 minutes", steps: -1)
            Text(duration.map { Fmt.duration($0) } ?? "\u{2014}")
                .dfStyle(.captionStrong)
                .foregroundStyle(palette.ink)
                .frame(minWidth: 46)
                .contentTransition(.numericText())
            stepButton(systemName: "plus", label: "Longer by 15 minutes", steps: 1)
        }
        .background(palette.chip, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize()
    }

    private func stepButton(systemName: String, label: String, steps: Int) -> some View {
        Button {
            withAnimation(model.animated(Motion.settle)) {
                duration = DurationRules.adjust(duration, bySteps: steps)
            }
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(palette.ink)
                .frame(width: Metrics.hit, height: Metrics.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.88))
        .accessibilityLabel(label)
    }

    private var urgentRow: some View {
        Button {
            isUrgent.toggle()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isUrgent ? "bell.fill" : "bell")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isUrgent ? palette.urgent : palette.inkSecondary)
                    .symbolEffect(.bounce, value: isUrgent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Urgent").dfStyle(.bodyStrong).foregroundStyle(palette.ink)
                    Text("Send me a notification for this one")
                        .dfStyle(.caption)
                        .foregroundStyle(palette.inkSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                ChromeSwitch(isOn: isUrgent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 56)
            .background(isUrgent ? palette.urgentTint : palette.chip, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(model.animated(Motion.settle), value: isUrgent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Urgent")
        .accessibilityHint("Send me a notification for this one")
        .accessibilityValue(isUrgent ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
        .padding(.top, 16)
    }

    private func add() {
        guard canAdd else { return }
        let added = model.addTask(
            title: trimmed,
            day: selectedDay,
            startMinute: startMinute,
            durationMinutes: duration,
            isUrgent: isUrgent,
            category: categoryOverride
        )
        if added {
            dismiss()
        }
    }
}
