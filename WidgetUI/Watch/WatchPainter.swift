import DailyFlowCore
import SwiftUI

// The skeleton watch, drawn with `GraphicsContext`. Pure drawing: no view state, no model, every input
// comes in through `WatchFrame` and `WatchStage`. It is split by layer, back to front, so the app can
// redraw only the moving layers and the later 3D version can render each layer to its own texture:
//
//   backdrop   shadow, strap or bracelet, lugs, crown, the case          (WatchPainter.swift)
//   plate      back plate with perlage                                    (WatchPainter.swift)
//   movement   barrel, wheels, balance and fork, bridges, jewels          (WatchPainter+Movement.swift)
//   dial       edge shadow, hour ring, 24 hour bezel, task arcs, progress (WatchPainter+Dial.swift)
//   hands      hour, minute and day arrow, then seconds                   (WatchPainter+Dial.swift)
//   glass      crystal glint                                              (WatchPainter+Dial.swift)
//
// All sizes below are in "design pixels" of the owner's prototype, where the dial opening has a radius of
// 122; `WatchStage.d(_:)` scales them to the real canvas.

/// How the watch is drawn.
enum WatchStyle: Sendable {
    /// Gradients, shadows and perlage: the in-app watch and the Home Screen widget.
    case fullColour
    /// Flat marks only, so the system can recolour them on the Lock Screen.
    case accessory
}

/// Everything one drawing of the watch needs.
struct WatchFrame: Sendable {
    var hands: WatchHands
    var arcs: [WatchArc]
    var gears: [WatchGear]
    var progress: DayProgress
    /// The movement's clock in seconds: turns the wheels and swings the balance.
    var seconds: Double
    /// Brightness of an urgent task's jewel, 0...1.
    var pulse: Double
    var theme: ThemeMode
    var style: WatchStyle
    /// The task the selection ring and highlighted arc belong to.
    var selected: UUID?
    /// Strap, lugs and crown: the in-app watch has them, the widget head does not.
    var showsHardware: Bool
    /// The sweeping seconds hand. A widget has no seconds, so it leaves the hand out.
    var showsSeconds: Bool
    let palette: WatchPalette

    init(
        hands: WatchHands,
        arcs: [WatchArc],
        gears: [WatchGear],
        progress: DayProgress,
        seconds: Double,
        pulse: Double,
        theme: ThemeMode,
        style: WatchStyle,
        selected: UUID? = nil,
        showsHardware: Bool = false,
        showsSeconds: Bool = true
    ) {
        self.hands = hands
        self.arcs = arcs
        self.gears = gears
        self.progress = progress
        self.seconds = seconds
        self.pulse = pulse
        self.theme = theme
        self.style = style
        self.selected = selected
        self.showsHardware = showsHardware
        self.showsSeconds = showsSeconds
        self.palette = WatchPalette.for(theme)
    }

    /// The same frame at another moment of the movement's motion.
    func moved(seconds: Double, pulse: Double) -> WatchFrame {
        var copy = self
        copy.seconds = seconds
        copy.pulse = pulse
        return copy
    }

    /// The same frame with other hand positions.
    func with(hands: WatchHands) -> WatchFrame {
        var copy = self
        copy.hands = hands
        return copy
    }
}

/// Maps the watch's design pixels (and its unit space) onto a canvas.
struct WatchStage: Sendable {
    /// Dial opening radius, in design pixels.
    static let design: CGFloat = 122

    let center: CGPoint
    /// Canvas points per unit of the movement's space: the radius of the dial opening, in points.
    let unit: CGFloat

    /// The whole 360 x 440 composition scaled to `size`'s width.
    static func composition(in size: CGSize) -> WatchStage {
        let scale = size.width / 360
        return WatchStage(center: CGPoint(x: size.width / 2, y: 220 * scale), unit: design * scale)
    }

    /// The round head alone, case edge to canvas edge.
    static func head(in size: CGSize) -> WatchStage {
        let radius = min(size.width, size.height) / 2
        return WatchStage(center: CGPoint(x: size.width / 2, y: size.height / 2), unit: radius * 0.97 * design / 153)
    }

    /// The Lock Screen ring: the bezel fills the canvas.
    static func ring(in size: CGSize) -> WatchStage {
        let radius = min(size.width, size.height) / 2
        return WatchStage(center: CGPoint(x: size.width / 2, y: size.height / 2), unit: radius * design / 143)
    }

    /// Design pixels to canvas points.
    func d(_ value: CGFloat) -> CGFloat { value * unit / Self.design }

    /// A point in the movement's unit space.
    func point(_ point: WatchPoint) -> CGPoint {
        CGPoint(x: center.x + CGFloat(point.x) * unit, y: center.y + CGFloat(point.y) * unit)
    }

    /// A point `radius` canvas points from the centre at `degrees` clockwise from 12 o'clock.
    func polar(_ radius: CGFloat, degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(sin(radians)), y: center.y - radius * CGFloat(cos(radians)))
    }

    func circle(_ radius: CGFloat, at origin: CGPoint? = nil) -> Path {
        let c = origin ?? center
        return Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2))
    }

    /// The dial opening, where the movement shows.
    var opening: Path { circle(d(122)) }

    /// Moves, turns and scales a path built in the unit space around the origin.
    func place(_ path: Path, at origin: CGPoint, degrees: Double) -> Path {
        path.applying(
            CGAffineTransform(translationX: origin.x, y: origin.y)
                .rotated(by: CGFloat(degrees * .pi / 180))
                .scaledBy(x: unit, y: unit)
        )
    }

    /// Scales a path built in absolute unit space.
    func place(_ path: Path) -> Path {
        place(path, at: center, degrees: 0)
    }
}

enum WatchPainter {
    // MARK: Whole watch

    /// Every layer, back to front, for a watch that does not move (the widget).
    static func drawHead(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        backdrop(&ctx, f, s)
        plate(&ctx, f, s)
        barrel(&ctx, f, s)
        wheels(&ctx, f, s)
        escapement(&ctx, f, s)
        bridges(&ctx, f, s)
        dialEdge(&ctx, f, s)
        hourRing(&ctx, f, s)
        bezel(&ctx, f, s)
        taskArcs(&ctx, f, s)
        progressArc(&ctx, f, s)
        hands(&ctx, f, s)
        secondsHand(&ctx, f, s)
        glint(&ctx, f, s)
    }

    // MARK: Shading helpers

    static func linear(_ gradient: Gradient, from start: CGPoint, to end: CGPoint) -> GraphicsContext.Shading {
        .linearGradient(gradient, startPoint: start, endPoint: end)
    }

    static func ramp(_ colors: [Color]) -> Gradient {
        Gradient(colors: colors)
    }

    // MARK: Backdrop: shadow, strap, lugs, crown, case

    static func backdrop(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette

        // Soft shadow the watch casts on whatever it sits on.
        // The bare head (widget) keeps it inside its square canvas.
        let reach: CGFloat = f.showsHardware ? 170 : 154
        let shadowCenter = CGPoint(x: s.center.x + s.d(f.showsHardware ? 5 : 2), y: s.center.y + s.d(f.showsHardware ? 9 : 3))
        ctx.fill(
            s.circle(s.d(reach), at: shadowCenter),
            with: .radialGradient(
                Gradient(stops: [
                    .init(color: p.depth.opacity(0.62), location: 0),
                    .init(color: p.depth.opacity(0.30), location: 0.6),
                    .init(color: p.depth.opacity(0), location: 1)
                ]),
                center: shadowCenter,
                startRadius: s.d(112),
                endRadius: s.d(reach)
            )
        )

        if f.showsHardware {
            if p.isDark {
                bracelet(&ctx, p, s)
            } else {
                leatherStrap(&ctx, p, s)
            }
            crown(&ctx, p, s)
            lugs(&ctx, p, s)
        }
        caseRing(&ctx, p, s)
    }

    /// The polished case disc: a lathe-turned conic sheen with chamfered edges.
    private static func caseRing(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage) {
        let disc = s.circle(s.d(152))
        ctx.fill(
            disc,
            with: .conicGradient(
                Gradient(stops: [
                    .init(color: p.caseC, location: 0),
                    .init(color: p.caseD, location: 0.12),
                    .init(color: p.caseB, location: 0.25),
                    .init(color: p.caseC, location: 0.375),
                    .init(color: p.caseB, location: 0.5),
                    .init(color: p.caseA, location: 0.625),
                    .init(color: p.caseB, location: 0.75),
                    .init(color: p.caseE, location: 0.875),
                    .init(color: p.caseC, location: 1)
                ]),
                center: s.center,
                angle: .degrees(0)
            )
        )
        let topLeft = CGPoint(x: s.center.x - s.d(110), y: s.center.y - s.d(110))
        let bottomRight = CGPoint(x: s.center.x + s.d(110), y: s.center.y + s.d(110))
        // Outer edge catches light top-left and falls away bottom-right.
        ctx.stroke(
            s.circle(s.d(151.3)),
            with: linear(ramp([p.caseA.opacity(0.95), p.caseE.opacity(0.9)]), from: topLeft, to: bottomRight),
            lineWidth: s.d(1.5)
        )
        // A fine lathe line on the flank.
        ctx.stroke(s.circle(s.d(147)), with: .color(p.caseA.opacity(0.28)), lineWidth: s.d(0.7))
        // The chamfer where the bezel sits down into the case.
        ctx.stroke(
            s.circle(s.d(143)),
            with: linear(ramp([p.caseE.opacity(0.9), p.caseA.opacity(0.9)]), from: topLeft, to: bottomRight),
            lineWidth: s.d(1.8)
        )
        ctx.stroke(s.circle(s.d(141.8)), with: .color(p.depth.opacity(0.85)), lineWidth: s.d(1))
    }

    private static func lugs(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage) {
        for side: CGFloat in [-1, 1] {
            for end: CGFloat in [-1, 1] {
                let x = s.center.x + side * s.d(54)
                let near = s.center.y + end * s.d(116)
                let far = s.center.y + end * s.d(184)
                let rect = CGRect(
                    x: x - s.d(13), y: min(near, far), width: s.d(26), height: abs(far - near)
                )
                let shape = Path(roundedRect: rect, cornerRadius: s.d(10))
                // A shadow where the lug lifts off the strap.
                ctx.fill(shape.offsetBy(dx: s.d(1.5), dy: s.d(3.2)), with: .color(p.depth.opacity(0.55)))
                ctx.fill(
                    shape,
                    with: linear(
                        ramp([p.caseB, p.caseA, p.caseD, p.caseC]),
                        from: CGPoint(x: rect.minX, y: rect.minY),
                        to: CGPoint(x: rect.maxX, y: rect.maxY)
                    )
                )
                ctx.stroke(shape, with: .color(p.caseA.opacity(0.55)), lineWidth: s.d(0.8))
                // Spring-bar hole.
                let hole = CGPoint(x: x, y: end > 0 ? rect.maxY - s.d(8) : rect.minY + s.d(8))
                ctx.fill(s.circle(s.d(2.6), at: hole), with: .color(p.depth.opacity(0.85)))
                ctx.stroke(s.circle(s.d(2.6), at: hole), with: .color(p.caseA.opacity(0.5)), lineWidth: s.d(0.6))
            }
        }
    }

    private static func crown(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage) {
        let crown = WatchMovement.crown
        let center = s.point(crown.center)
        let width = CGFloat(crown.width) * s.unit
        let height = CGFloat(crown.height) * s.unit
        let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        let shape = Path(roundedRect: rect, cornerRadius: s.d(4))
        ctx.fill(shape.offsetBy(dx: s.d(1.6), dy: s.d(2.6)), with: .color(p.depth.opacity(0.5)))
        // The stem between crown and case.
        let stem = CGRect(x: center.x - width, y: center.y - s.d(5), width: width, height: s.d(10))
        ctx.fill(Path(stem), with: .color(p.caseC))
        ctx.fill(
            shape,
            with: linear(
                ramp([p.caseD, p.caseA, p.caseB, p.caseC]),
                from: CGPoint(x: rect.midX, y: rect.minY),
                to: CGPoint(x: rect.midX, y: rect.maxY)
            )
        )
        // Knurling: ridges along the grip.
        var ridges = Path()
        var y = rect.minY + s.d(2.6)
        while y < rect.maxY - s.d(1) {
            ridges.move(to: CGPoint(x: rect.minX + s.d(1), y: y))
            ridges.addLine(to: CGPoint(x: rect.maxX - s.d(1), y: y))
            y += s.d(2.6)
        }
        ctx.stroke(ridges, with: .color(p.depth.opacity(0.5)), lineWidth: s.d(0.9))
        ctx.stroke(shape, with: .color(p.caseA.opacity(0.5)), lineWidth: s.d(0.7))
    }

    /// Three-piece link bracelet running off the top and bottom of the canvas.
    private static func bracelet(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage) {
        let pitch: CGFloat = 23
        for direction: CGFloat in [-1, 1] {
            for row in 0..<7 {
                let mid = s.center.y + direction * s.d(150 + 12 + pitch * CGFloat(row))
                let links: [(x: CGFloat, width: CGFloat, polished: Bool, stagger: CGFloat)] = [
                    (-28.5, 23, false, 0), (0, 31, true, pitch / 2), (28.5, 23, false, 0)
                ]
                for link in links {
                    let center = CGPoint(x: s.center.x + s.d(link.x), y: mid + direction * s.d(link.stagger))
                    let rect = CGRect(
                        x: center.x - s.d(link.width) / 2, y: center.y - s.d(10.5), width: s.d(link.width), height: s.d(21)
                    )
                    let shape = Path(roundedRect: rect, cornerRadius: s.d(5.5))
                    ctx.fill(shape.offsetBy(dx: 0, dy: s.d(1.6)), with: .color(p.depth.opacity(0.7)))
                    let colours = link.polished
                        ? [p.caseB, p.caseA, p.caseD, p.caseB]
                        : [p.caseE, p.caseB, p.caseC, p.caseE]
                    ctx.fill(
                        shape,
                        with: linear(
                            ramp(colours),
                            from: CGPoint(x: rect.minX, y: rect.minY),
                            to: CGPoint(x: rect.minX + s.d(8), y: rect.maxY)
                        )
                    )
                    ctx.stroke(shape, with: .color(p.caseA.opacity(link.polished ? 0.7 : 0.35)), lineWidth: s.d(0.7))
                    // A brushed top edge on the satin links.
                    if !link.polished {
                        var grain = Path()
                        for step in 1..<4 {
                            let y = rect.minY + CGFloat(step) * rect.height / 4
                            grain.move(to: CGPoint(x: rect.minX + s.d(3), y: y))
                            grain.addLine(to: CGPoint(x: rect.maxX - s.d(3), y: y))
                        }
                        ctx.stroke(grain, with: .color(p.caseA.opacity(0.1)), lineWidth: s.d(0.6))
                    }
                }
            }
            shadeStrapRoot(&ctx, p, s, direction: direction)
        }
    }

    /// A stitched leather strap with buckle holes at the lower end.
    private static func leatherStrap(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage) {
        let span = s.d(40)
        for direction: CGFloat in [-1, 1] {
            let near = s.center.y + direction * s.d(140)
            let far = s.center.y + direction * s.d(260)
            let rect = CGRect(x: s.center.x - span, y: min(near, far), width: span * 2, height: abs(far - near))
            let shape = Path(roundedRect: rect, cornerRadius: s.d(5))
            ctx.fill(shape.offsetBy(dx: s.d(1.5), dy: s.d(2)), with: .color(p.depth.opacity(0.5)))
            ctx.fill(
                shape,
                with: linear(
                    ramp([p.leatherDark, p.leatherLight, p.leatherDark]),
                    from: CGPoint(x: rect.minX, y: rect.midY),
                    to: CGPoint(x: rect.maxX, y: rect.midY)
                )
            )
            // The padded edge catching the light.
            ctx.stroke(shape, with: .color(p.leatherLight.opacity(0.9)), lineWidth: s.d(0.7))
            // Stitching on both sides.
            for side: CGFloat in [-1, 1] {
                var stitch = Path()
                let x = s.center.x + side * (span - s.d(7))
                stitch.move(to: CGPoint(x: x, y: rect.minY))
                stitch.addLine(to: CGPoint(x: x, y: rect.maxY))
                ctx.stroke(
                    stitch,
                    with: .color(p.stitch.opacity(0.85)),
                    style: StrokeStyle(lineWidth: s.d(1.3), lineCap: .round, dash: [s.d(4), s.d(3.2)])
                )
            }
            // Buckle holes on the lower strap.
            if direction > 0 {
                for index in 0..<5 {
                    let hole = CGPoint(x: s.center.x, y: s.center.y + s.d(210 + CGFloat(index) * 19))
                    ctx.fill(s.circle(s.d(3.4), at: hole), with: .color(p.depth.opacity(0.9)))
                    ctx.stroke(s.circle(s.d(3.4), at: hole), with: .color(p.leatherLight.opacity(0.8)), lineWidth: s.d(0.9))
                    ctx.stroke(s.circle(s.d(5.2), at: hole), with: .color(p.stitch.opacity(0.35)), lineWidth: s.d(0.6))
                }
            }
            shadeStrapRoot(&ctx, p, s, direction: direction)
        }
    }

    /// Darkens the strap where it tucks under the case.
    private static func shadeStrapRoot(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage, direction: CGFloat) {
        let rootY = s.center.y + direction * s.d(150)
        let farY = s.center.y + direction * s.d(196)
        let rect = CGRect(x: s.center.x - s.d(42), y: min(rootY, farY), width: s.d(84), height: abs(farY - rootY))
        ctx.fill(
            Path(rect),
            with: linear(
                ramp([p.depth.opacity(0.7), p.depth.opacity(0)]),
                from: CGPoint(x: rect.midX, y: rootY),
                to: CGPoint(x: rect.midX, y: farY)
            )
        )
    }

    // MARK: Plate

    /// The back plate: a graded disc with perlage, tiny overlapping circles in a hex grid.
    static func plate(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        let radius = s.d(122)
        var layer = ctx
        layer.clip(to: s.opening)

        let light = CGPoint(x: s.center.x - radius * 0.16, y: s.center.y - radius * 0.24)
        layer.fill(
            s.opening,
            with: .radialGradient(ramp([p.plateTop, p.plateBottom]), center: light, startRadius: 0, endRadius: radius * 1.5)
        )

        let pitch = s.d(6.4)
        guard pitch >= 1.2 else { return }
        let dot = pitch * 0.36
        var dots = Path()
        var y = s.center.y - radius
        var row = 0
        while y <= s.center.y + radius {
            var x = s.center.x - radius + (row.isMultiple(of: 2) ? 0 : pitch / 2)
            while x <= s.center.x + radius {
                let dx = x - s.center.x
                let dy = y - s.center.y
                if dx * dx + dy * dy <= radius * radius {
                    dots.addEllipse(in: CGRect(x: x - dot, y: y - dot, width: dot * 2, height: dot * 2))
                }
                x += pitch
            }
            y += pitch * 0.866
            row += 1
        }
        layer.fill(
            dots,
            with: .radialGradient(
                ramp([p.perlageBright, p.perlageDim]), center: light, startRadius: 0, endRadius: radius * 1.6
            )
        )
    }
}
