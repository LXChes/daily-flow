import DailyFlowCore
import SwiftUI

/// The static skeleton watch for widgets: the same watch as the app, frozen at one minute. Lock Screen
/// circular gets the simplified flat version (ring, arcs, wheel outlines, hands, "now" arrow) in two
/// passes so the system can accent the key marks; Home medium gets the full-colour round head, no strap.
///
/// No `TimelineView`, no images and no per-frame work: the hand moves because the widget timeline hands
/// us a new minute. With no task data (basic mode) the watch is still complete, just without arcs and
/// with every wheel dim.
struct WatchFaceView: View {
    let tasks: [TaskSnapshot]
    let minute: Int
    let diameter: CGFloat
    let look: WidgetLook

    var body: some View {
        let moment = Double(minute)
        let flat = !look.isFull
        let frame = WatchFrame(
            hands: WatchGeometry.hands(atMinute: moment),
            arcs: WatchGeometry.arcs(tasks, atMinute: moment),
            gears: WatchGeometry.gears(tasks, titles: { $0.title }, atMinute: moment),
            progress: DaySchedule.progress(tasks),
            // Time zero keeps every pair of wheels exactly meshed in the still frame.
            seconds: 0,
            pulse: 0.9,
            theme: look.palette.isDark || flat ? .dark : .light,
            style: flat ? .accessory : .fullColour,
            showsSeconds: false
        )

        ZStack {
            if flat {
                Canvas { context, size in
                    WatchPainter.accessoryStructure(&context, frame, WatchStage.ring(in: size))
                }
                Canvas { context, size in
                    WatchPainter.accessoryMarks(&context, frame, WatchStage.ring(in: size))
                }
                .widgetAccentable()
            } else {
                Canvas { context, size in
                    WatchPainter.drawHead(&context, frame, WatchStage.head(in: size))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WatchGeometry.spokenSummary(tasks, titles: { $0.title }, atMinute: moment))
    }
}
