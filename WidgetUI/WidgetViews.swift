import DailyFlowCore
import SwiftUI
import WidgetKit

// The widget faces. `DFWidgetView` picks the face for a widget kind and family; the faces themselves are in
// `WidgetFaces.swift`, the shared marks in `WidgetParts.swift`, and the 24-hour dial in `DialPlaceholder.swift`.

/// The face of one widget, for one family. Pure: everything comes in as parameters, so the app's demo
/// gallery can draw it too (`widgetFamily` cannot be set from outside WidgetKit).
struct DFWidgetView: View {
    let kind: DFWidgetKind
    let family: WidgetFamily
    let renderingMode: WidgetRenderingMode
    let entry: DFWidgetEntry

    var body: some View {
        let look = WidgetLook(palette: entry.palette, family: family, renderingMode: renderingMode)
        switch (kind, family) {
        case (.upNext, .accessoryRectangular):
            UpNextRectangularFace(entry: entry, look: look)
        case (.progressRing, .accessoryCircular):
            ProgressRingCircularFace(entry: entry, look: look)
        case (.progressRing, .systemSmall):
            ProgressRingSmallFace(entry: entry, look: look)
        case (.doneRing, .systemSmall):
            DoneRingSmallFace(entry: entry, look: look)
        case (.wave, .systemMedium):
            WaveMediumFace(entry: entry, look: look)
        case (.dayDial, .accessoryCircular):
            DayDialCircularFace(entry: entry, look: look)
        case (.dayDial, .systemMedium):
            DayDialMediumFace(entry: entry, look: look)
        case (.todayLine, .accessoryInline):
            TodayLineFace(entry: entry, look: look)
        default:
            // A family this widget does not offer. Never reached from the widget picker; kept so a
            // mismatch draws something calm instead of nothing.
            Text(kind.displayName)
                .widgetFont(.cardTitle, 14)
                .foregroundStyle(look.ink)
                .padding(16)
        }
    }
}

/// The widget's background for its theme: the app's near-black (or paper) with a faint cool glow and a
/// diagonal sheen. The Lock Screen families use the system's own translucent plate.
struct DFWidgetBackground: View {
    let family: WidgetFamily
    let theme: ThemeMode

    var body: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            AccessoryWidgetBackground()
        case .accessoryInline:
            Color.clear
        default:
            let palette = Palette.for(theme)
            ZStack {
                palette.background
                LinearGradient(colors: [palette.ambient, .clear], startPoint: .top, endPoint: .center)
                Rectangle()
                    .fill(palette.bevel)
                    .opacity(palette.isDark ? 0.4 : 0.55)
            }
        }
    }
}
