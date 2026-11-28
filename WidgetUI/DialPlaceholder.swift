import DailyFlowCore
import SwiftUI

// PLACEHOLDER: THIS FLAT 24-HOUR DIAL IS A DELIBERATE STAND-IN. MILESTONE M5 MUST REPLACE IT WITH THE RICH
// SKELETON-WATCH RENDERING (gears, bezel, faceted hands). SEE docs/m5-watch-handoff.md.
//
// Kept deliberately simple: flat chrome, one Canvas pass, no gradients and no per-frame work, so it is safe
// in the widget's memory budget and recolours cleanly on the Lock Screen. Midnight is at the top; the hand
// and the arrow on the rim both read "now" on the 24-hour ring.

/// One timed task as an arc on the dial.
struct DialArc: Sendable {
    let start: Int
    let end: Int
    let isDone: Bool
}

/// Colours resolved up front so the drawing code holds no view state.
struct DialStyle: Sendable {
    let ink: Color
    let rim: Color
    let track: Color
    let open: Color
    let done: Color
}

struct DialPlaceholder: View {
    let tasks: [TaskSnapshot]
    let minute: Int
    let diameter: CGFloat
    let look: WidgetLook

    var body: some View {
        let arcs = tasks.compactMap { task -> DialArc? in
            guard let start = task.startMinute, let end = task.endMinute else { return nil }
            return DialArc(start: start, end: end, isDone: task.isDone)
        }
        let style = DialStyle(
            ink: look.ink,
            rim: look.hairline,
            track: look.track,
            open: look.steel,
            done: look.accent
        )
        let now = minute
        Canvas { context, size in
            DialPainter.draw(&context, size: size, arcs: arcs, minute: now, style: style)
        }
        .frame(width: diameter, height: diameter)
        .widgetAccentable()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Day dial, now \(WidgetText.clock(minute)). \(WidgetText.progressSpoken(DaySchedule.progress(tasks)))")
    }
}

/// Pure drawing, kept out of the view so it carries no actor isolation.
enum DialPainter {
    static func draw(_ context: inout GraphicsContext, size: CGSize, arcs: [DialArc], minute: Int, style: DialStyle) {
        let radius = min(size.width, size.height) / 2
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let band = radius * 0.17
        let ringRadius = radius - radius * 0.07 - band / 2

        func degrees(_ minute: Int) -> Double { Double(minute) / 1_440 * 360 }
        func point(_ degrees: Double, _ distance: CGFloat) -> CGPoint {
            let radians = (degrees - 90) * Double.pi / 180
            return CGPoint(
                x: center.x + distance * CGFloat(cos(radians)),
                y: center.y + distance * CGFloat(sin(radians))
            )
        }
        func circle(_ circleRadius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(
                x: center.x - circleRadius,
                y: center.y - circleRadius,
                width: circleRadius * 2,
                height: circleRadius * 2
            ))
        }

        // Rim and the empty 24-hour ring.
        context.stroke(circle(radius - 0.75), with: .color(style.rim), lineWidth: 1.5)
        context.stroke(circle(ringRadius), with: .color(style.track), lineWidth: band)

        // Task arcs: done ones full width, open ones slimmer, so the difference is not only colour.
        for arc in arcs {
            let start = degrees(arc.start)
            let end = min(degrees(max(arc.end, arc.start + 18)), 360)
            var path = Path()
            path.addArc(
                center: center,
                radius: ringRadius,
                startAngle: .degrees(start - 90),
                endAngle: .degrees(end - 90),
                clockwise: false
            )
            context.stroke(
                path,
                with: .color(arc.isDone ? style.done : style.open),
                style: StrokeStyle(lineWidth: arc.isDone ? band : band * 0.55, lineCap: .butt)
            )
        }

        // Hour ticks inside the ring: every hour on a big dial, every third on a small one.
        let stepHours = radius < 40 ? 3 : 1
        let outer = ringRadius - band / 2 - radius * 0.05
        for hour in stride(from: 0, to: 24, by: stepHours) {
            let major = hour % 6 == 0
            let angle = Double(hour) * 15
            var tick = Path()
            tick.move(to: point(angle, outer))
            tick.addLine(to: point(angle, outer - radius * (major ? 0.13 : 0.07)))
            context.stroke(
                tick,
                with: .color(style.ink.opacity(major ? 1 : 0.6)),
                lineWidth: major ? max(1.4, radius * 0.03) : max(0.8, radius * 0.018)
            )
        }

        // The hand, and the arrow on the rim, both at "now".
        let now = degrees(minute)
        var hand = Path()
        hand.move(to: point(now + 180, radius * 0.12))
        hand.addLine(to: point(now, radius * 0.56))
        context.stroke(hand, with: .color(style.ink), style: StrokeStyle(lineWidth: max(2, radius * 0.065), lineCap: .round))

        var arrow = Path()
        arrow.move(to: point(now - 6, radius * 0.97))
        arrow.addLine(to: point(now + 6, radius * 0.97))
        arrow.addLine(to: point(now, radius * 0.97 - band * 1.3))
        arrow.closeSubpath()
        context.fill(arrow, with: .color(style.ink))

        context.fill(circle(max(2.5, radius * 0.07)), with: .color(style.ink))
    }
}
