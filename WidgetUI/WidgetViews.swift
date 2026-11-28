import DailyFlowCore
import SwiftUI
import WidgetKit

// TEMPORARY plumbing stub. ui-craft-builder replaces this file with the crafted widget views.

/// The face of one widget, for one family. Pure: everything comes in as parameters, so the app's demo
/// gallery can draw it too (`widgetFamily` cannot be set from outside WidgetKit).
struct DFWidgetView: View {
    let kind: DFWidgetKind
    let family: WidgetFamily
    let renderingMode: WidgetRenderingMode
    let entry: DFWidgetEntry

    var body: some View {
        let progress = entry.snapshot.progress
        VStack(spacing: 2) {
            Text(kind.displayName)
            Text("\(progress.done)/\(progress.total)")
        }
        .font(.caption)
        .foregroundStyle(entry.palette.ink)
    }
}

/// The widget's background for its theme.
struct DFWidgetBackground: View {
    let family: WidgetFamily
    let theme: ThemeMode

    var body: some View {
        Palette.for(theme).background
    }
}
