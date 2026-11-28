import DailyFlowCore
import SwiftUI

// The dial furniture: edge shadow, hour ring, 24 hour bezel, task arcs, progress arc, hands and glass.
// Everything here is static between minutes, so the app draws it once per second at most. The Lock Screen
// look (flat marks only) is at the bottom.

extension WatchPainter {
    // MARK: Fonts

    /// Dark: a wide geometric face. Light: a built-in high-contrast serif for the Roman numerals.
    private static func numeralFont(_ p: WatchPalette, size: CGFloat) -> Font {
        p.isDark ? DFTextStyle.overline.font(fixedSize: size) : Font.custom("Didot", fixedSize: size)
    }

    private static let romanNumerals = ["XII", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI"]

    // MARK: Edge shadow

    /// A soft inner shadow where the movement dives under the ring.
    static func dialEdge(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        var layer = ctx
        layer.clip(to: s.opening)
        layer.fill(
            s.opening,
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: p.depth.opacity(0), location: 0),
                    .init(color: p.depth.opacity(0), location: 0.78),
                    .init(color: p.depth.opacity(0.62), location: 1)
                ]),
                center: s.center,
                startRadius: 0,
                endRadius: s.d(122)
            )
        )
    }

    // MARK: Hour ring

    /// The 12 hour chapter ring just inside the opening: black ceramic in dark, ivory with Roman
    /// numerals in light.
    static func hourRing(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        let top = CGPoint(x: s.center.x, y: s.center.y - s.d(122))
        let bottom = CGPoint(x: s.center.x, y: s.center.y + s.d(122))

        ctx.stroke(s.circle(s.d(115)), with: linear(ramp([p.ringTop, p.ringBottom]), from: top, to: bottom), lineWidth: s.d(14))
        // Lips: shadowed on the inside, catching light on the outside.
        ctx.stroke(s.circle(s.d(108.2)), with: .color(p.depth.opacity(0.85)), lineWidth: s.d(1))
        ctx.stroke(s.circle(s.d(109.1)), with: .color(p.bevel.opacity(0.3)), lineWidth: s.d(0.6))
        ctx.stroke(s.circle(s.d(121.6)), with: .color(p.bevel.opacity(0.45)), lineWidth: s.d(0.7))

        // Minute track.
        var minor = Path()
        var major = Path()
        for tick in 0..<60 {
            let degrees = Double(tick) * 6
            let isMajor = tick.isMultiple(of: 5)
            let target = isMajor ? s.d(117.4) : s.d(119.2)
            if isMajor {
                major.move(to: s.polar(s.d(120.9), degrees: degrees))
                major.addLine(to: s.polar(target, degrees: degrees))
            } else {
                minor.move(to: s.polar(s.d(120.9), degrees: degrees))
                minor.addLine(to: s.polar(target, degrees: degrees))
            }
        }
        ctx.stroke(minor, with: .color(p.ringNumeral.opacity(0.55)), lineWidth: max(s.d(0.5), 0.4))
        ctx.stroke(major, with: .color(p.ringNumeral.opacity(0.9)), lineWidth: max(s.d(1.1), 0.6))

        // Numerals, upright.
        let size = s.d(p.isDark ? 7.4 : 8.6)
        guard size >= 4.5 else { return }
        for hour in 0..<12 {
            let label = p.isDark ? (hour == 0 ? "12" : "\(hour)") : romanNumerals[hour]
            let text = Text(label)
                .font(numeralFont(p, size: size))
                .tracking(p.isDark ? s.d(0.5) : 0)
                .foregroundStyle(p.ringNumeral)
            ctx.draw(text, at: s.polar(s.d(112.6), degrees: Double(hour) * 30), anchor: .center)
        }
    }

    // MARK: Bezel

    /// The 24 hour bezel: day half and night half, numerals every two hours, a marker at midnight.
    static func bezel(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        let mid = s.d(132)
        let width = s.d(20)
        let topLeft = CGPoint(x: s.center.x - s.d(140), y: s.center.y - s.d(140))
        let bottomRight = CGPoint(x: s.center.x + s.d(140), y: s.center.y + s.d(140))

        // Day is the half through noon (bottom); night is the half through midnight (top).
        var day = Path()
        day.addArc(center: s.center, radius: mid, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        var night = Path()
        night.addArc(center: s.center, radius: mid, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        ctx.stroke(day, with: linear(ramp([p.bezelDayTop, p.bezelDayBottom]), from: topLeft, to: bottomRight), lineWidth: width)
        ctx.stroke(night, with: linear(ramp([p.bezelNightTop, p.bezelNightBottom]), from: topLeft, to: bottomRight), lineWidth: width)

        // Polished gloss sweeping round the ring.
        ctx.stroke(
            s.circle(mid),
            with: .conicGradient(
                Gradient(stops: [
                    .init(color: p.gearHighlight.opacity(0), location: 0),
                    .init(color: p.gearHighlight.opacity(p.gloss), location: 0.1),
                    .init(color: p.gearHighlight.opacity(0), location: 0.24),
                    .init(color: p.gearHighlight.opacity(0), location: 0.5),
                    .init(color: p.gearHighlight.opacity(p.gloss * 0.9), location: 0.62),
                    .init(color: p.gearHighlight.opacity(0), location: 0.76),
                    .init(color: p.gearHighlight.opacity(0), location: 1)
                ]),
                center: s.center,
                angle: .degrees(-30)
            ),
            lineWidth: width
        )
        ctx.stroke(s.circle(s.d(122.4)), with: .color(p.depth.opacity(0.8)), lineWidth: s.d(0.9))
        ctx.stroke(s.circle(s.d(141.4)), with: .color(p.bevel.opacity(0.4)), lineWidth: s.d(0.7))

        // Where day meets night.
        var seams = Path()
        for degrees in [90.0, 270.0] {
            seams.move(to: s.polar(s.d(122.6), degrees: degrees))
            seams.addLine(to: s.polar(s.d(141), degrees: degrees))
        }
        ctx.stroke(seams, with: .color(p.depth.opacity(0.6)), lineWidth: s.d(0.7))

        // Numerals every two hours; a dot at each odd hour.
        let size = s.d(p.isDark ? 6.0 : 6.8)
        for hour in 1..<24 {
            let degrees = Double(hour) * 15
            let isDay = hour >= 6 && hour <= 18
            if hour.isMultiple(of: 2) {
                guard size >= 3.8 else { continue }
                let text = Text("\(hour)")
                    .font(numeralFont(p, size: size))
                    .tracking(p.isDark ? s.d(0.3) : 0)
                    .foregroundStyle(isDay ? p.bezelNumeralDay : p.bezelNumeralNight)
                ctx.draw(text, at: s.polar(s.d(136.7), degrees: degrees), anchor: .center)
            } else {
                let dot = s.circle(max(s.d(0.8), 0.4), at: s.polar(s.d(136.7), degrees: degrees))
                ctx.fill(dot, with: .color((isDay ? p.bezelNumeralDay : p.bezelNumeralNight).opacity(0.75)))
            }
        }

        // Midnight marker.
        var marker = Path()
        marker.move(to: s.polar(s.d(130.5), degrees: 0))
        marker.addLine(to: s.polar(s.d(141), degrees: -2.6))
        marker.addLine(to: s.polar(s.d(141), degrees: 2.6))
        marker.closeSubpath()
        ctx.fill(marker, with: .color(p.bezelTriangle))
        ctx.stroke(marker, with: .color(p.depth.opacity(0.7)), lineWidth: s.d(0.5))
    }

    // MARK: Task arcs

    static func taskArcs(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        let radius = s.d(128)
        ctx.stroke(s.circle(radius), with: .color(p.depth.opacity(0.32)), lineWidth: s.d(7.4))
        ctx.stroke(s.circle(radius), with: .color(p.track), lineWidth: s.d(6.6))

        // Open arcs first, so ticked ones sit on top.
        for arc in f.arcs.sorted(by: { !$0.isDone && $1.isDone }) {
            let colour: Color = arc.isDone ? p.doneArc : (arc.isUrgent ? p.urgentArc : p.arc(arc.category))
            var path = Path()
            path.addArc(
                center: s.center,
                radius: radius,
                startAngle: .degrees(arc.startDegrees - 90),
                endAngle: .degrees(arc.endDegrees - 90),
                clockwise: false
            )
            if arc.id == f.selected {
                ctx.stroke(path, with: .color(colour.opacity(0.3)), style: StrokeStyle(lineWidth: s.d(11.5), lineCap: .round))
            }
            if arc.isLive {
                ctx.stroke(path, with: .color(colour.opacity(0.34)), style: StrokeStyle(lineWidth: s.d(12), lineCap: .round))
            }
            ctx.stroke(
                path,
                with: .color(colour.opacity(arc.isDone ? 0.92 : 1)),
                style: StrokeStyle(lineWidth: arc.isLive ? s.d(6.5) : s.d(4.5), lineCap: .round)
            )
        }
    }

    // MARK: Progress

    /// How many tasks are done: an arc up the left of the movement and a small curved label.
    static func progressArc(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        let radius = s.d(107.5)
        // The track runs 120 degrees, from the lower left (SwiftUI 100 degrees) up to 10 o'clock (220).
        var track = Path()
        track.addArc(center: s.center, radius: radius, startAngle: .degrees(100), endAngle: .degrees(220), clockwise: false)
        ctx.stroke(track, with: .color(p.depth.opacity(0.55)), style: StrokeStyle(lineWidth: s.d(3.8), lineCap: .round))
        ctx.stroke(track, with: .color(p.track), style: StrokeStyle(lineWidth: s.d(3.2), lineCap: .round))

        let sweep = WatchGeometry.progressSweep(f.progress, trackDegrees: 120)
        if sweep > 0.5 {
            var fill = Path()
            fill.addArc(center: s.center, radius: radius, startAngle: .degrees(220 - sweep), endAngle: .degrees(220), clockwise: false)
            ctx.stroke(fill, with: .color(p.progress.opacity(0.3)), style: StrokeStyle(lineWidth: s.d(7), lineCap: .round))
            ctx.stroke(fill, with: .color(p.progress), style: StrokeStyle(lineWidth: s.d(3.2), lineCap: .round))
        }

        // "3 / 9 DONE", along the arc and reading upward.
        let label = f.progress.total == 0 ? "NO TASKS" : "\(f.progress.done) / \(f.progress.total) DONE"
        let size = s.d(6.4)
        guard size >= 4 else { return }
        let advance = s.d(4.7)
        let labelRadius = s.d(99.5)
        let span = Double(label.count) * Double(advance / labelRadius) * 180 / .pi
        var angle = 250 - span / 2
        for character in label {
            let step = Double((character == " " ? advance * 0.55 : advance) / labelRadius) * 180 / .pi
            angle += step / 2
            let spot = s.polar(labelRadius, degrees: angle)
            let glyph = Text(String(character))
                .font(DFTextStyle.badge.font(fixedSize: size))
                .foregroundStyle(p.progress)
            let halo = Text(String(character))
                .font(DFTextStyle.badge.font(fixedSize: size))
                .foregroundStyle(p.depth.opacity(0.9))
            var rotated = ctx
            rotated.translateBy(x: spot.x, y: spot.y)
            rotated.rotate(by: .degrees(angle))
            rotated.draw(halo, at: CGPoint(x: s.d(0.7), y: s.d(0.7)), anchor: .center)
            rotated.draw(glyph, at: .zero, anchor: .center)
            angle += step / 2
        }
    }

    // MARK: Hands

    private struct HandShape {
        let whole: Path
        let left: Path
        let right: Path
        let lume: Path
    }

    private static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    /// A sword-shaped hand pointing up from the centre, split down the middle into two facets.
    private static func facetedHand(_ s: WatchStage, length: CGFloat, tail: CGFloat, width: CGFloat) -> HandShape {
        let l = s.d(length)
        let t = s.d(tail)
        let h = s.d(width) / 2
        let right: [CGPoint] = [
            CGPoint(x: 0.62 * h, y: -l * 0.84), CGPoint(x: h, y: -l * 0.55), CGPoint(x: 0.78 * h, y: 0), CGPoint(x: 0.46 * h, y: t)
        ]
        let left = right.map { CGPoint(x: -$0.x, y: $0.y) }
        let tip = CGPoint(x: 0, y: -l)
        let base = CGPoint(x: 0, y: t)
        let whole = polygon([tip] + right + [base] + Array(left.reversed()))
        let lume = polygon([
            CGPoint(x: 0, y: -l * 0.8), CGPoint(x: 0.4 * h, y: -l * 0.62), CGPoint(x: 0.4 * h, y: -l * 0.16),
            CGPoint(x: -0.4 * h, y: -l * 0.16), CGPoint(x: -0.4 * h, y: -l * 0.62)
        ])
        return HandShape(
            whole: whole,
            left: polygon([tip] + left + [base]),
            right: polygon([tip] + right + [base]),
            lume: lume
        )
    }

    private static func rotation(_ s: WatchStage, _ degrees: Double) -> CGAffineTransform {
        CGAffineTransform(translationX: s.center.x, y: s.center.y).rotated(by: CGFloat(degrees * .pi / 180))
    }

    /// The hour and minute hands and the day arrow (the "now" arrow on the bezel). No seconds hand and no
    /// centre cap: those move every frame and live in `secondsHand`.
    static func hands(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        drawDayArrow(&ctx, p, s, degrees: f.hands.day)
        if p.isDark {
            drawFacetedHand(&ctx, p, s, degrees: f.hands.hour, length: 66, tail: 14, width: 9.5, lume: true)
            drawFacetedHand(&ctx, p, s, degrees: f.hands.minute, length: 100, tail: 16, width: 6.4, lume: true)
        } else {
            drawBreguetHand(&ctx, p, s, degrees: f.hands.hour, length: 66, tail: 12, shaft: 2.8, moon: 4.7, moonAt: 0.7)
            drawBreguetHand(&ctx, p, s, degrees: f.hands.minute, length: 100, tail: 14, shaft: 2.2, moon: 3.7, moonAt: 0.82)
        }
    }

    private static func drawFacetedHand(
        _ ctx: inout GraphicsContext,
        _ p: WatchPalette,
        _ s: WatchStage,
        degrees: Double,
        length: CGFloat,
        tail: CGFloat,
        width: CGFloat,
        lume: Bool
    ) {
        let shape = facetedHand(s, length: length, tail: tail, width: width)
        let transform = rotation(s, degrees)
        let tip = s.polar(s.d(length), degrees: degrees)

        ctx.fill(shape.whole.applying(transform).offsetBy(dx: s.d(2.2), dy: s.d(3.2)), with: .color(p.depth.opacity(0.42)))
        ctx.fill(shape.left.applying(transform), with: linear(ramp([p.handLight, p.handDark]), from: s.center, to: tip))
        ctx.fill(shape.right.applying(transform), with: linear(ramp([p.handDark, p.caseC]), from: s.center, to: tip))
        ctx.stroke(shape.whole.applying(transform), with: .color(p.bevel.opacity(0.6)), lineWidth: s.d(0.55))
        if lume {
            let glow = shape.lume.applying(transform)
            ctx.fill(glow, with: .color(p.depth.opacity(0.55)))
            ctx.fill(glow, with: .color(p.lume.opacity(0.96)))
        }
    }

    /// A blued steel Breguet hand: a slender shaft, an open "moon" ring and a fine needle tip.
    private static func drawBreguetHand(
        _ ctx: inout GraphicsContext,
        _ p: WatchPalette,
        _ s: WatchStage,
        degrees: Double,
        length: CGFloat,
        tail: CGFloat,
        shaft: CGFloat,
        moon: CGFloat,
        moonAt: CGFloat
    ) {
        let transform = rotation(s, degrees)
        let l = s.d(length)
        let moonY = -l * moonAt
        let w = s.d(shaft) / 2
        let r = s.d(moon)

        var body = polygon([
            CGPoint(x: -w * 1.15, y: s.d(tail)), CGPoint(x: -w, y: moonY + r), CGPoint(x: w, y: moonY + r), CGPoint(x: w * 1.15, y: s.d(tail))
        ])
        let needle = polygon([
            CGPoint(x: -w * 0.8, y: moonY - r), CGPoint(x: 0, y: -l), CGPoint(x: w * 0.8, y: moonY - r)
        ])
        body.addPath(needle)
        let ring = Path(ellipseIn: CGRect(x: -r, y: moonY - r, width: r * 2, height: r * 2))
        let tip = s.polar(l, degrees: degrees)
        let blued = linear(ramp([p.handDark, p.handLight]), from: s.center, to: tip)

        ctx.fill(body.applying(transform).offsetBy(dx: s.d(2), dy: s.d(3)), with: .color(p.depth.opacity(0.38)))
        ctx.stroke(ring.applying(transform).offsetBy(dx: s.d(2), dy: s.d(3)), with: .color(p.depth.opacity(0.38)), lineWidth: s.d(1.5))
        ctx.fill(body.applying(transform), with: blued)
        ctx.stroke(ring.applying(transform), with: blued, lineWidth: max(s.d(1.6), 0.7))
    }

    private static func drawDayArrow(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage, degrees: Double) {
        let transform = rotation(s, degrees)
        var shaft = Path()
        shaft.move(to: CGPoint(x: 0, y: s.d(16)))
        shaft.addLine(to: CGPoint(x: 0, y: -s.d(112)))
        let head = polygon([
            CGPoint(x: 0, y: -s.d(125)), CGPoint(x: s.d(5.2), y: -s.d(112)), CGPoint(x: 0, y: -s.d(115.5)), CGPoint(x: -s.d(5.2), y: -s.d(112))
        ])

        ctx.stroke(shaft.applying(transform).offsetBy(dx: s.d(1.8), dy: s.d(2.6)), with: .color(p.depth.opacity(0.35)), lineWidth: s.d(1.6))
        ctx.fill(head.applying(transform).offsetBy(dx: s.d(1.8), dy: s.d(2.6)), with: .color(p.depth.opacity(0.35)))
        ctx.stroke(shaft.applying(transform), with: .color(p.dayArrow), style: StrokeStyle(lineWidth: max(s.d(1.6), 0.7), lineCap: .round))
        ctx.fill(head.applying(transform), with: .color(p.dayArrow))
        ctx.stroke(head.applying(transform), with: .color(p.bevel.opacity(0.55)), lineWidth: s.d(0.5))
    }

    /// The sweeping seconds hand (if the frame shows one) and the centre cap.
    static func secondsHand(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        if f.showsSeconds {
            let transform = rotation(s, f.hands.second)
            var long = Path()
            long.move(to: CGPoint(x: 0, y: s.d(26)))
            long.addLine(to: CGPoint(x: 0, y: -s.d(108)))
            var tipPart = Path()
            tipPart.move(to: CGPoint(x: 0, y: -s.d(86)))
            tipPart.addLine(to: CGPoint(x: 0, y: -s.d(108)))
            let weight = Path(ellipseIn: CGRect(x: -s.d(3.6), y: s.d(21), width: s.d(7.2), height: s.d(7.2)))

            ctx.stroke(long.applying(transform).offsetBy(dx: s.d(2.2), dy: s.d(3.2)), with: .color(p.depth.opacity(0.4)), lineWidth: s.d(1.2))
            ctx.stroke(long.applying(transform), with: .color(p.secondsShaft), style: StrokeStyle(lineWidth: max(s.d(1.2), 0.6), lineCap: .round))
            ctx.stroke(tipPart.applying(transform), with: .color(p.secondsTip), style: StrokeStyle(lineWidth: max(s.d(1.4), 0.7), lineCap: .round))
            ctx.fill(weight.applying(transform), with: .color(p.secondsShaft))
            ctx.stroke(weight.applying(transform), with: .color(p.depth.opacity(0.6)), lineWidth: s.d(0.5))
        }
        // Centre cap over all the hands.
        let cap = s.circle(s.d(5.6))
        ctx.fill(s.circle(s.d(5.6), at: CGPoint(x: s.center.x + s.d(1.4), y: s.center.y + s.d(2))), with: .color(p.depth.opacity(0.5)))
        ctx.fill(
            cap,
            with: .radialGradient(
                ramp([p.capLight, p.caseB]),
                center: CGPoint(x: s.center.x - s.d(1.6), y: s.center.y - s.d(1.8)),
                startRadius: 0,
                endRadius: s.d(7)
            )
        )
        ctx.stroke(cap, with: .color(p.depth.opacity(0.6)), lineWidth: s.d(0.5))
        ctx.fill(s.circle(s.d(2.3)), with: .color(p.capDark))
        ctx.fill(
            s.circle(s.d(0.8), at: CGPoint(x: s.center.x - s.d(0.7), y: s.center.y - s.d(0.8))),
            with: .color(p.gearHighlight.opacity(0.85))
        )
    }

    // MARK: Glass

    /// The sapphire crystal: a soft sheen across the upper left and a thin reflection round the rim.
    static func glint(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        var layer = ctx
        layer.clip(to: s.opening)

        // A large pale ellipse, tilted, fading towards the middle.
        var sheen = Path(ellipseIn: CGRect(x: -s.d(118), y: -s.d(132), width: s.d(236), height: s.d(120)))
        sheen = sheen.applying(
            CGAffineTransform(translationX: s.center.x - s.d(14), y: s.center.y - s.d(36)).rotated(by: -0.5)
        )
        layer.fill(
            sheen,
            with: linear(
                ramp([p.gearHighlight.opacity(min(p.gloss * 1.9, 0.6)), p.gearHighlight.opacity(0)]),
                from: CGPoint(x: s.center.x - s.d(90), y: s.center.y - s.d(100)),
                to: CGPoint(x: s.center.x + s.d(10), y: s.center.y - s.d(10))
            )
        )
        // A bright crescent just inside the opening, upper left.
        layer.stroke(
            s.circle(s.d(120.6)),
            with: linear(
                ramp([p.gearHighlight.opacity(min(p.gloss * 3, 0.7)), p.gearHighlight.opacity(0), p.gearHighlight.opacity(p.gloss * 1.2)]),
                from: CGPoint(x: s.center.x - s.d(100), y: s.center.y - s.d(100)),
                to: CGPoint(x: s.center.x + s.d(100), y: s.center.y + s.d(100))
            ),
            lineWidth: s.d(1.6)
        )
    }

    // MARK: Lock Screen look

    /// Structure for the Lock Screen: a two-tone ring, hour ticks and a few wheel silhouettes. Flat strokes
    /// only, so it still reads once the system recolours the widget.
    static func accessoryStructure(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .accessory else { return }
        let ink = f.palette.accessoryInk

        // Two-tone 24 hour ring: brighter through noon, dimmer through midnight.
        var day = Path()
        day.addArc(center: s.center, radius: s.d(131), startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
        var night = Path()
        night.addArc(center: s.center, radius: s.d(131), startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        ctx.stroke(day, with: .color(ink.opacity(0.34)), style: StrokeStyle(lineWidth: s.d(19)))
        ctx.stroke(night, with: .color(ink.opacity(0.14)), style: StrokeStyle(lineWidth: s.d(19)))
        ctx.stroke(s.circle(s.d(121.5)), with: .color(ink.opacity(0.55)), lineWidth: max(s.d(1.8), 0.8))

        // A tick every three hours across the ring.
        var ticks = Path()
        for hour in stride(from: 0, to: 24, by: 3) {
            let degrees = Double(hour) * 15
            ticks.move(to: s.polar(s.d(123), degrees: degrees))
            ticks.addLine(to: s.polar(s.d(hour % 6 == 0 ? 139 : 134), degrees: degrees))
        }
        ctx.stroke(ticks, with: .color(ink.opacity(0.85)), style: StrokeStyle(lineWidth: max(s.d(2), 0.8), lineCap: .butt))

        // The biggest wheels, as outlines only.
        var movement = ctx
        movement.clip(to: s.circle(s.d(118)))
        let silhouettes = Array(WatchMovement.taskWheels.prefix(4)) + [WatchMovement.barrel]
        for wheel in silhouettes {
            guard let outline = WatchShapes.wheelOutlines[wheel.id] else { continue }
            let placed = s.place(outline, at: s.point(wheel.center), degrees: wheel.angle(atSeconds: f.seconds))
            movement.fill(placed, with: .color(ink.opacity(0.08)))
            movement.stroke(placed, with: .color(ink.opacity(0.42)), lineWidth: max(s.d(1.5), 0.6))
            movement.fill(s.circle(max(CGFloat(wheel.tipRadius) * s.unit * 0.2, 0.8), at: s.point(wheel.center)), with: .color(ink.opacity(0.5)))
        }
    }

    /// Key marks for the Lock Screen, drawn as their own pass so the system can accent them: task arcs
    /// (ticked ones bold, open ones slim), the day arrow, both hands and the cap.
    static func accessoryMarks(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .accessory else { return }
        let ink = f.palette.accessoryInk
        let radius = s.d(131)

        for arc in f.arcs {
            var path = Path()
            path.addArc(
                center: s.center,
                radius: radius,
                startAngle: .degrees(arc.startDegrees - 90),
                endAngle: .degrees(arc.endDegrees - 90),
                clockwise: false
            )
            let width = arc.isDone || arc.isLive ? s.d(11) : s.d(5.5)
            ctx.stroke(
                path,
                with: .color(ink.opacity(arc.isDone || arc.isLive ? 1 : 0.7)),
                style: StrokeStyle(lineWidth: width, lineCap: .butt)
            )
        }

        // The day arrow: a head on the ring and a faint shaft.
        let day = f.hands.day
        var shaft = Path()
        shaft.move(to: s.polar(s.d(14), degrees: day))
        shaft.addLine(to: s.polar(s.d(100), degrees: day))
        ctx.stroke(shaft, with: .color(ink.opacity(0.55)), style: StrokeStyle(lineWidth: max(s.d(2.2), 0.8), lineCap: .round))
        var head = Path()
        head.move(to: s.polar(s.d(122), degrees: day))
        head.addLine(to: s.polar(s.d(101), degrees: day - 9))
        head.addLine(to: s.polar(s.d(101), degrees: day + 9))
        head.closeSubpath()
        ctx.fill(head, with: .color(ink))

        // Hour and minute hands.
        var hour = Path()
        hour.move(to: s.polar(s.d(10), degrees: f.hands.hour + 180))
        hour.addLine(to: s.polar(s.d(66), degrees: f.hands.hour))
        ctx.stroke(hour, with: .color(ink), style: StrokeStyle(lineWidth: max(s.d(10), 1.6), lineCap: .round))
        var minute = Path()
        minute.move(to: s.polar(s.d(10), degrees: f.hands.minute + 180))
        minute.addLine(to: s.polar(s.d(100), degrees: f.hands.minute))
        ctx.stroke(minute, with: .color(ink), style: StrokeStyle(lineWidth: max(s.d(6.4), 1.2), lineCap: .round))
        ctx.fill(s.circle(max(s.d(6.4), 1.6)), with: .color(ink))
    }
}
