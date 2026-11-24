import AppIntents
import SwiftUI
import WidgetKit

// M1 stub: proves the widget extension builds, embeds and renders.
// M4 adds the style parameter (Match app / Dark chrome / Light vintage) and the crash-proof
// data fallback: App Group container -> timeline snapshot / standard UserDefaults -> placeholder.

struct DailyFlowConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Daily Flow" }
}

struct DailyFlowEntry: TimelineEntry, Sendable {
    let date: Date
}

struct DailyFlowProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> DailyFlowEntry {
        DailyFlowEntry(date: .now)
    }

    func snapshot(for configuration: DailyFlowConfigurationIntent, in context: Context) async -> DailyFlowEntry {
        DailyFlowEntry(date: .now)
    }

    func timeline(for configuration: DailyFlowConfigurationIntent, in context: Context) async -> Timeline<DailyFlowEntry> {
        let now = Date.now
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        return Timeline(entries: [DailyFlowEntry(date: now)], policy: .after(next))
    }
}

struct DailyFlowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DailyFlowEntry

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Text("DAILY")
                        .font(.system(size: 9, weight: .semibold, design: .serif))
                        .tracking(1)
                    Text(entry.date, style: .time)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .minimumScaleFactor(0.6)
                }
            }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("DAILY")
                    .font(.system(.headline, design: .serif))
                    .tracking(2)
                Text(entry.date, style: .time)
                    .font(.caption.monospacedDigit())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryInline:
            Text("DAILY · \(entry.date, style: .time)")
        default:
            VStack(spacing: 6) {
                Text("DAILY")
                    .font(.system(size: 28, weight: .semibold, design: .serif))
                    .tracking(4)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(red: 0.93, green: 0.95, blue: 0.98),
                                Color(red: 0.50, green: 0.55, blue: 0.63)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                Text(entry.date, style: .time)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct DailyFlowWidget: Widget {
    let kind: String = "DailyFlowWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: DailyFlowConfigurationIntent.self,
            provider: DailyFlowProvider()
        ) { entry in
            DailyFlowWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color("WidgetBackground")
                }
        }
        .configurationDisplayName("Daily Flow")
        .description("Pipeline proof widget.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

#Preview(as: .systemSmall) {
    DailyFlowWidget()
} timeline: {
    DailyFlowEntry(date: .now)
}
