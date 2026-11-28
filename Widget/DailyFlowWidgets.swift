import AppIntents
import DailyFlowCore
import SwiftUI
import WidgetKit

// MARK: Per-widget style (long-press > Edit Widget)

enum DFStyleOption: String, AppEnum {
    case matchApp, darkChrome, lightVintage

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Style" }
    static var caseDisplayRepresentations: [DFStyleOption: DisplayRepresentation] {
        [
            .matchApp: "Match app",
            .darkChrome: "Dark chrome",
            .lightVintage: "Light vintage"
        ]
    }

    var style: WidgetStyle {
        switch self {
        case .matchApp: .matchApp
        case .darkChrome: .darkChrome
        case .lightVintage: .lightVintage
        }
    }
}

struct DFStyleIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Widget style" }
    static var description: IntentDescription { IntentDescription("Match the app, or pick dark chrome or light vintage.") }

    @Parameter(title: "Style", default: .matchApp)
    var style: DFStyleOption

    init() {}
}

// MARK: Timeline

/// Builds entries from the shared snapshot, the widget's cached copy, or nothing at all, in that order.
/// It never throws and never force-unwraps, so a free-sideload install without the App Group still draws.
struct DFProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DFWidgetEntry {
        WidgetSamples.entry(now: .now, calendar: .current)
    }

    func snapshot(for configuration: DFStyleIntent, in context: Context) async -> DFWidgetEntry {
        if context.isPreview {
            // The widget picker shows a sample day, styled as chosen.
            let sample = WidgetSamples.entry(now: .now, calendar: .current)
            let theme = WidgetStyle.resolvedTheme(widget: configuration.style.style, global: .matchApp, appTheme: .dark)
            return DFWidgetEntry(date: sample.date, day: sample.day, theme: theme, minute: sample.minute)
        }
        return entries(for: configuration, dates: [.now]).first ?? placeholder(in: context)
    }

    func timeline(for configuration: DFStyleIntent, in context: Context) async -> Timeline<DFWidgetEntry> {
        let calendar = Calendar.current
        let now = Date.now
        let sources = WidgetDataStore.loadSources()
        let dates = WidgetTimeline.entryDates(now: now, snapshot: sources.shared ?? sources.cached, calendar: calendar)
        return Timeline(entries: entries(for: configuration, dates: dates), policy: .atEnd)
    }

    private func entries(for configuration: DFStyleIntent, dates: [Date]) -> [DFWidgetEntry] {
        let calendar = Calendar.current
        let sources = WidgetDataStore.loadSources()
        return dates.map { date in
            // Resolved per entry, so an entry after midnight drops yesterday's tasks.
            let day = WidgetDataResolver.resolve(shared: sources.shared, cached: sources.cached, now: date, calendar: calendar)
            let theme = WidgetStyle.resolvedTheme(
                widget: configuration.style.style,
                global: day.snapshot.widgetStyle,
                appTheme: day.snapshot.theme
            )
            return DFWidgetEntry(date: date, day: day, theme: theme, minute: MinuteOfDay.of(date, calendar: calendar))
        }
    }
}

// MARK: Widgets

/// Reads the family and rendering mode from the environment and hands them to the shared views.
struct DFWidgetContainer: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    let kind: DFWidgetKind
    let entry: DFWidgetEntry

    var body: some View {
        DFWidgetView(kind: kind, family: family, renderingMode: renderingMode, entry: entry)
            .containerBackground(for: .widget) {
                DFWidgetBackground(family: family, theme: entry.theme)
            }
    }
}

@MainActor
private func configuration(_ kind: DFWidgetKind) -> some WidgetConfiguration {
    AppIntentConfiguration(kind: kind.rawValue, intent: DFStyleIntent.self, provider: DFProvider()) { entry in
        DFWidgetContainer(kind: kind, entry: entry)
    }
    .configurationDisplayName(kind.displayName)
    .description(kind.summary)
    .supportedFamilies(kind.families)
    .contentMarginsDisabled()
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration { configuration(.upNext) }
}

struct ProgressRingWidget: Widget {
    var body: some WidgetConfiguration { configuration(.progressRing) }
}

struct DoneRingWidget: Widget {
    var body: some WidgetConfiguration { configuration(.doneRing) }
}

struct WaveWidget: Widget {
    var body: some WidgetConfiguration { configuration(.wave) }
}

struct DayDialWidget: Widget {
    var body: some WidgetConfiguration { configuration(.dayDial) }
}

struct TodayLineWidget: Widget {
    var body: some WidgetConfiguration { configuration(.todayLine) }
}
