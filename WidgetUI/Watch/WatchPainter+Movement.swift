import DailyFlowCore
import SwiftUI

// The movement layers: barrel, wheels, balance and fork, bridges and jewels. These are the layers that
// move, so they are kept apart from the dial furniture: the app redraws only these every frame.

extension WatchPainter {
    private static let wheelOrder: [WatchWheel] = WatchMovement.wheels.sorted { lhs, rhs in
        lhs.layer == rhs.layer ? lhs.id < rhs.id : lhs.layer < rhs.layer
    }

    private static let bridgeOrder: [Int] = WatchMovement.bridges.indices.sorted { lhs, rhs in
        let left = WatchMovement.bridges[lhs].layer
        let right = WatchMovement.bridges[rhs].layer
        return left == right ? lhs < rhs : left < right
    }

    private static let wheelsByHub: [WatchPoint: WatchWheel] = Dictionary(
        WatchMovement.allWheels.map { ($0.center, $0) },
        uniquingKeysWith: { first, _ in first }
    )

    private enum JewelKind {
        case ruby
        case urgent(Double)
        case done
        case empty
    }

    // MARK: Wheels

    /// Every task wheel and train cog. Task wheels carry their task's state: live ones spin fast and glow,
    /// ticked ones turn bright and polished.
    static func wheels(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        var layer = ctx
        layer.clip(to: s.opening)
        let bySlot = Dictionary(f.gears.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        for wheel in wheelOrder {
            let gear = wheel.taskSlot.flatMap { bySlot[$0] }
            drawWheel(&layer, wheel, gear: gear, f, s)
        }
    }

    private static func drawWheel(
        _ ctx: inout GraphicsContext,
        _ wheel: WatchWheel,
        gear: WatchGear?,
        _ f: WatchFrame,
        _ s: WatchStage
    ) {
        guard let body = WatchShapes.wheelBodies[wheel.id] else { return }
        let p = f.palette
        let center = s.point(wheel.center)
        let tip = CGFloat(wheel.tipRadius) * s.unit
        let angle = wheel.angle(atSeconds: f.seconds, rateScale: gear?.spinRate ?? 1)
        let placed = s.place(body, at: center, degrees: angle)
        let even = FillStyle(eoFill: true)

        // Depth: a wide soft shadow and a tight dark one, falling down and to the right.
        ctx.fill(placed.offsetBy(dx: s.d(2.8), dy: s.d(3.8)), with: .color(p.depth.opacity(0.26)), style: even)
        ctx.fill(placed.offsetBy(dx: s.d(1.2), dy: s.d(1.7)), with: .color(p.depth.opacity(0.55)), style: even)

        if let gear, gear.state != .idle {
            let halo = gear.state == .live ? p.progress : p.doneGlow
            ctx.fill(
                s.circle(tip * 1.6, at: center),
                with: .radialGradient(
                    ramp([halo.opacity(gear.state == .live ? 0.34 : 0.26), halo.opacity(0)]),
                    center: center,
                    startRadius: tip * 0.72,
                    endRadius: tip * 1.6
                )
            )
        }

        let done = gear?.state == .done
        let colours = done
            ? [p.doneHighlight, p.doneMid, p.doneShade]
            : [p.gearHighlight, p.gearMid, p.gearShade]
        let light = CGPoint(x: center.x - tip * 0.36, y: center.y - tip * 0.42)
        ctx.fill(
            placed,
            with: .radialGradient(ramp(colours), center: light, startRadius: 0, endRadius: tip * 1.75),
            style: even
        )
        // Satin sheen: the light is fixed in the room, so it slides across a turning wheel.
        let sheen = done ? 0.46 : 0.32
        ctx.fill(
            placed,
            with: .conicGradient(
                Gradient(stops: [
                    .init(color: p.gearHighlight.opacity(0), location: 0),
                    .init(color: p.gearHighlight.opacity(sheen), location: 0.12),
                    .init(color: p.gearHighlight.opacity(0), location: 0.27),
                    .init(color: p.gearHighlight.opacity(0), location: 0.5),
                    .init(color: p.gearHighlight.opacity(sheen * 0.8), location: 0.62),
                    .init(color: p.gearHighlight.opacity(0), location: 0.78),
                    .init(color: p.gearHighlight.opacity(0), location: 1)
                ]),
                center: center,
                angle: .degrees(-35)
            ),
            style: even
        )
        // Crisp polished edge on teeth, rim and spokes.
        ctx.stroke(placed, with: .color(colours[0].opacity(done ? 0.7 : 0.45)), lineWidth: s.d(0.55))
        if let holes = WatchShapes.wheelHoles[wheel.id], !holes.isEmpty {
            let edge = s.place(holes, at: center, degrees: angle)
            ctx.stroke(edge, with: .color(p.depth.opacity(0.5)), lineWidth: s.d(0.9))
        }

        // The hub washer, ringed in the task's colour so a gear and its bezel arc read as a pair.
        let hub = tip * 0.25
        ctx.fill(
            s.circle(hub, at: center),
            with: .radialGradient(ramp([colours[0], colours[1], colours[2]]), center: light, startRadius: 0, endRadius: hub * 2.4)
        )
        ctx.stroke(s.circle(hub, at: center), with: .color(p.depth.opacity(0.5)), lineWidth: s.d(0.7))
        if let gear {
            let ring = done ? p.doneGlow : p.arc(gear.category)
            ctx.stroke(s.circle(hub * 1.34, at: center), with: .color(ring.opacity(0.9)), lineWidth: s.d(1.1))
        }
    }

    // MARK: Barrel

    /// The mainspring barrel, low on the plate: a toothed drum with its spring showing through an open side.
    static func barrel(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour,
              let outline = WatchShapes.wheelOutlines[WatchMovement.barrel.id]
        else { return }
        let p = f.palette
        let wheel = WatchMovement.barrel
        var layer = ctx
        layer.clip(to: s.opening)

        let center = s.point(wheel.center)
        let tip = CGFloat(wheel.tipRadius) * s.unit
        let root = CGFloat(wheel.rootRadius) * s.unit
        let angle = wheel.angle(atSeconds: f.seconds)
        let placed = s.place(outline, at: center, degrees: angle)

        layer.fill(placed.offsetBy(dx: s.d(3), dy: s.d(4.2)), with: .color(p.depth.opacity(0.3)))
        layer.fill(placed.offsetBy(dx: s.d(1.3), dy: s.d(1.9)), with: .color(p.depth.opacity(0.55)))
        let light = CGPoint(x: center.x - tip * 0.4, y: center.y - tip * 0.45)
        layer.fill(
            placed,
            with: .radialGradient(ramp([p.bridgeLight, p.bridgeMid, p.bridgeShade]), center: light, startRadius: 0, endRadius: tip * 1.8)
        )
        layer.stroke(placed, with: .color(p.bevel.opacity(0.4)), lineWidth: s.d(0.55))

        // The open drum: a dark recess with the spring coiled in it.
        let recess = s.circle(root * 0.86, at: center)
        layer.fill(recess, with: .color(p.depth.opacity(0.9)))
        layer.stroke(recess, with: .color(p.bevel.opacity(0.35)), lineWidth: s.d(0.8))
        layer.stroke(
            s.place(WatchShapes.mainspring, at: center, degrees: angle),
            with: .color(p.mainspring.opacity(0.95)),
            lineWidth: s.d(1.05)
        )

        // A fixed cover over one side, with a polished edge.
        var cover = Path()
        cover.move(to: center)
        cover.addArc(center: center, radius: root * 0.86, startAngle: .degrees(196), endAngle: .degrees(322), clockwise: false)
        cover.closeSubpath()
        layer.fill(cover.offsetBy(dx: s.d(1), dy: s.d(1.5)), with: .color(p.depth.opacity(0.5)))
        layer.fill(
            cover,
            with: linear(
                ramp([p.bridgeLight, p.bridgeMid, p.bridgeShade]),
                from: CGPoint(x: center.x - root, y: center.y - root),
                to: CGPoint(x: center.x + root * 0.4, y: center.y + root * 0.6)
            )
        )
        layer.stroke(cover, with: .color(p.bevel.opacity(0.7)), lineWidth: s.d(0.8))

        let arbor = tip * 0.17
        layer.fill(
            s.circle(arbor, at: center),
            with: .radialGradient(ramp([p.gearHighlight, p.gearMid, p.gearShade]), center: light, startRadius: 0, endRadius: arbor * 2.4)
        )
        layer.stroke(s.circle(arbor, at: center), with: .color(p.depth.opacity(0.6)), lineWidth: s.d(0.7))
    }

    // MARK: Balance, hairspring and pallet fork

    static func escapement(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        var layer = ctx
        layer.clip(to: s.opening)

        let balance = WatchMovement.balance
        let center = s.point(balance.center)
        let radius = CGFloat(balance.radius) * s.unit
        let swing = WatchMovement.balanceAngle(atSeconds: f.seconds)
        let rimRadius = radius * 0.88
        let rimWidth = radius * 0.2

        // Shadow of the whole assembly on the plate below.
        layer.stroke(
            s.circle(rimRadius, at: CGPoint(x: center.x + s.d(2.2), y: center.y + s.d(3))),
            with: .color(p.depth.opacity(0.5)),
            lineWidth: rimWidth
        )
        // The hairspring first, so the arms sit above it.
        layer.stroke(
            s.place(WatchShapes.hairspring, at: center, degrees: swing),
            with: .color(p.hairspring.opacity(0.92)),
            lineWidth: max(s.d(0.65), 0.5)
        )

        // Rim, polished.
        layer.stroke(
            s.circle(rimRadius, at: center),
            with: .conicGradient(
                Gradient(stops: [
                    .init(color: p.gearHighlight, location: 0),
                    .init(color: p.gearMid, location: 0.22),
                    .init(color: p.gearShade, location: 0.5),
                    .init(color: p.gearMid, location: 0.74),
                    .init(color: p.gearHighlight, location: 1)
                ]),
                center: center,
                angle: .degrees(-40)
            ),
            lineWidth: rimWidth
        )
        layer.stroke(s.circle(rimRadius + rimWidth / 2, at: center), with: .color(p.bevel.opacity(0.5)), lineWidth: s.d(0.6))
        layer.stroke(s.circle(rimRadius - rimWidth / 2, at: center), with: .color(p.depth.opacity(0.5)), lineWidth: s.d(0.7))

        // Three arms, which swing with the balance.
        for arm in 0..<3 {
            let direction = swing + 90 + Double(arm) * 120
            let inner = clockwisePoint(center, radius * 0.14, direction)
            let outer = clockwisePoint(center, rimRadius - rimWidth * 0.4, direction)
            var spoke = Path()
            spoke.move(to: inner)
            spoke.addLine(to: outer)
            layer.stroke(
                spoke.offsetBy(dx: s.d(0.9), dy: s.d(1.3)),
                with: .color(p.depth.opacity(0.5)),
                style: StrokeStyle(lineWidth: s.d(3), lineCap: .round)
            )
            layer.stroke(spoke, with: .color(p.gearMid), style: StrokeStyle(lineWidth: s.d(3), lineCap: .round))
            layer.stroke(spoke, with: .color(p.gearHighlight.opacity(0.7)), style: StrokeStyle(lineWidth: s.d(1), lineCap: .round))
        }

        // Poising screws round the rim.
        for index in 0..<16 {
            let spot = clockwisePoint(center, rimRadius, swing + Double(index) * 22.5)
            layer.fill(s.circle(s.d(1.35), at: spot), with: .color(p.chaton))
            layer.stroke(s.circle(s.d(1.35), at: spot), with: .color(p.depth.opacity(0.55)), lineWidth: s.d(0.4))
        }

        // The roller, with its ruby impulse jewel.
        layer.fill(
            s.circle(s.d(7.4), at: center),
            with: .radialGradient(
                ramp([p.gearHighlight, p.gearMid, p.gearShade]),
                center: CGPoint(x: center.x - s.d(2), y: center.y - s.d(2)),
                startRadius: 0,
                endRadius: s.d(10)
            )
        )
        layer.stroke(s.circle(s.d(7.4), at: center), with: .color(p.depth.opacity(0.6)), lineWidth: s.d(0.7))
        drawJewel(&layer, p, s, at: clockwisePoint(center, s.d(5.2), swing + 24), radius: s.d(1.7), kind: .ruby)

        drawFork(&layer, p, s, seconds: f.seconds)
    }

    private static func drawFork(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage, seconds: Double) {
        let fork = WatchMovement.fork
        let pivot = s.point(fork.pivot)
        let angle = fork.tailAngle + WatchMovement.forkAngle(atSeconds: seconds)

        /// A tapered rod from the pivot along `degrees`, in unit space around the origin.
        func rod(_ degrees: Double, length: Double, near: Double, far: Double) -> Path {
            let radians = degrees * .pi / 180
            let along = CGPoint(x: cos(radians), y: sin(radians))
            let across = CGPoint(x: -sin(radians), y: cos(radians))
            var path = Path()
            path.move(to: CGPoint(x: across.x * near, y: across.y * near))
            path.addLine(to: CGPoint(x: along.x * length + across.x * far, y: along.y * length + across.y * far))
            path.addLine(to: CGPoint(x: along.x * length - across.x * far, y: along.y * length - across.y * far))
            path.addLine(to: CGPoint(x: -across.x * near, y: -across.y * near))
            path.closeSubpath()
            return path
        }

        let tail = rod(0, length: fork.tailLength, near: 0.022, far: 0.011)
        let armA = rod(180 - fork.armSpread, length: fork.armLength, near: 0.017, far: 0.012)
        let armB = rod(180 + fork.armSpread, length: fork.armLength, near: 0.017, far: 0.012)
        var body = tail
        body.addPath(armA)
        body.addPath(armB)
        body.addEllipse(in: CGRect(x: -0.03, y: -0.03, width: 0.06, height: 0.06))
        let placed = s.place(body, at: pivot, degrees: angle)

        ctx.fill(placed.offsetBy(dx: s.d(1.6), dy: s.d(2.2)), with: .color(p.depth.opacity(0.55)))
        ctx.fill(
            placed,
            with: linear(
                ramp([p.gearHighlight, p.gearMid, p.gearShade]),
                from: CGPoint(x: pivot.x - s.d(14), y: pivot.y - s.d(14)),
                to: CGPoint(x: pivot.x + s.d(14), y: pivot.y + s.d(14))
            )
        )
        ctx.stroke(placed, with: .color(p.gearHighlight.opacity(0.55)), lineWidth: s.d(0.5))

        // Pallet stones at the arm tips.
        for sign in [-1.0, 1.0] {
            let radians = (180 + sign * fork.armSpread + angle) * .pi / 180
            let reach = CGFloat(fork.armLength) * s.unit
            let spot = CGPoint(x: pivot.x + reach * CGFloat(cos(radians)), y: pivot.y + reach * CGFloat(sin(radians)))
            drawJewel(&ctx, p, s, at: spot, radius: s.d(1.9), kind: .ruby)
        }
        let hub = s.circle(s.d(3.4), at: pivot)
        ctx.fill(hub, with: .color(p.chaton))
        ctx.stroke(hub, with: .color(p.depth.opacity(0.6)), lineWidth: s.d(0.6))
    }

    // MARK: Bridges, screws and jewels

    /// The bridge arms over the wheels, with bevelled and striped faces, then the jewels set in them.
    static func bridges(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour else { return }
        let p = f.palette
        var layer = ctx
        layer.clip(to: s.opening)

        for index in bridgeOrder {
            let bridge = WatchMovement.bridges[index]
            let path = s.place(WatchShapes.bridgeOutlines[index])
            let bounds = path.boundingRect

            layer.fill(path.offsetBy(dx: s.d(3.2), dy: s.d(4.4)), with: .color(p.depth.opacity(0.24)))
            layer.fill(path.offsetBy(dx: s.d(1.5), dy: s.d(2.2)), with: .color(p.depth.opacity(0.55)))
            layer.fill(
                path,
                with: linear(
                    ramp([p.bridgeLight, p.bridgeMid, p.bridgeShade]),
                    from: CGPoint(x: bounds.minX, y: bounds.minY),
                    to: CGPoint(x: bounds.maxX, y: bounds.maxY)
                )
            )
            // Côtes de Genève: fine diagonal stripes across the long arms.
            if bridge.hubs.count >= 2 {
                layer.drawLayer { inner in
                    inner.clip(to: path)
                    var stripes = Path()
                    let step = s.d(2.7)
                    var x = bounds.minX - bounds.height
                    while x < bounds.maxX {
                        stripes.move(to: CGPoint(x: x, y: bounds.maxY))
                        stripes.addLine(to: CGPoint(x: x + bounds.height, y: bounds.minY))
                        x += step
                    }
                    inner.stroke(stripes, with: .color(p.bevel.opacity(0.12)), lineWidth: s.d(1.1))
                }
            }
            // Bevelled edge: bright where it faces the light, dark where it falls away.
            layer.stroke(path, with: .color(p.depth.opacity(0.7)), lineWidth: s.d(1.4))
            layer.stroke(
                path,
                with: linear(
                    ramp([p.bevel.opacity(0.95), p.bevel.opacity(0.08), p.bevel.opacity(0.5)]),
                    from: CGPoint(x: bounds.minX, y: bounds.minY),
                    to: CGPoint(x: bounds.maxX, y: bounds.maxY)
                ),
                lineWidth: s.d(0.9)
            )

            for hub in bridge.hubs {
                let spot = s.point(hub)
                if let wheel = wheelsByHub[hub], wheel.taskSlot != nil { continue }
                drawScrew(&layer, p, s, at: spot, radius: s.d(2.7))
            }
        }

        // Jewels set at the pivot of every task wheel; slots with no task stay dim.
        let bySlot = Dictionary(f.gears.map { ($0.slot, $0) }, uniquingKeysWith: { first, _ in first })
        for wheel in WatchMovement.taskWheels {
            let spot = s.point(wheel.center)
            let kind: JewelKind
            if let gear = wheel.taskSlot.flatMap({ bySlot[$0] }) {
                if gear.state == .done {
                    kind = .done
                } else if gear.pulsesJewel {
                    kind = .urgent(f.pulse)
                } else {
                    kind = .ruby
                }
            } else {
                kind = .empty
            }
            drawJewel(&layer, p, s, at: spot, radius: s.d(3.6), kind: kind)
        }
        drawJewel(&layer, p, s, at: s.point(WatchMovement.balance.center), radius: s.d(2.6), kind: .ruby)
    }

    private static func drawScrew(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ s: WatchStage, at spot: CGPoint, radius: CGFloat) {
        ctx.fill(s.circle(radius, at: CGPoint(x: spot.x + s.d(0.8), y: spot.y + s.d(1.1))), with: .color(p.depth.opacity(0.6)))
        let head = s.circle(radius, at: spot)
        ctx.fill(head, with: .color(p.screw))
        ctx.fill(
            head,
            with: .radialGradient(
                ramp([p.gearHighlight.opacity(0.75), p.gearHighlight.opacity(0)]),
                center: CGPoint(x: spot.x - radius * 0.4, y: spot.y - radius * 0.45),
                startRadius: 0,
                endRadius: radius * 1.2
            )
        )
        ctx.stroke(head, with: .color(p.depth.opacity(0.55)), lineWidth: s.d(0.5))
        // The slot, at an angle that depends on where the screw sits so they do not all line up.
        let tilt = Double(Int(abs(spot.x * 7 + spot.y * 13)) % 180) * .pi / 180
        var slot = Path()
        slot.move(to: CGPoint(x: spot.x - radius * 0.78 * CGFloat(cos(tilt)), y: spot.y - radius * 0.78 * CGFloat(sin(tilt))))
        slot.addLine(to: CGPoint(x: spot.x + radius * 0.78 * CGFloat(cos(tilt)), y: spot.y + radius * 0.78 * CGFloat(sin(tilt))))
        ctx.stroke(slot, with: .color(p.depth.opacity(0.85)), lineWidth: max(radius * 0.26, 0.4))
    }

    private static func drawJewel(
        _ ctx: inout GraphicsContext,
        _ p: WatchPalette,
        _ s: WatchStage,
        at spot: CGPoint,
        radius: CGFloat,
        kind: JewelKind
    ) {
        var layer = ctx
        var urgentAmount = 0.0
        var isDone = false
        switch kind {
        case .ruby: break
        case .urgent(let pulse): urgentAmount = min(max(pulse, 0), 1)
        case .done: isDone = true
        case .empty: layer.opacity = 0.4
        }

        // A glow around a ticked or urgent jewel.
        if isDone || urgentAmount > 0 {
            let glow = isDone ? p.doneGlow : p.urgentArc
            let strength = isDone ? 0.62 : 0.62 * urgentAmount
            layer.fill(
                s.circle(radius * 3.6, at: spot),
                with: .radialGradient(
                    ramp([glow.opacity(strength), glow.opacity(0)]),
                    center: spot,
                    startRadius: radius * 0.5,
                    endRadius: radius * 3.6
                )
            )
        }

        // The gold or steel setting (chaton).
        layer.fill(s.circle(radius * 1.28, at: CGPoint(x: spot.x + s.d(0.7), y: spot.y + s.d(1))), with: .color(p.depth.opacity(0.55)))
        layer.fill(
            s.circle(radius * 1.28, at: spot),
            with: linear(
                ramp([p.bevel, p.chaton, p.depth.opacity(0.9)]),
                from: CGPoint(x: spot.x - radius, y: spot.y - radius),
                to: CGPoint(x: spot.x + radius, y: spot.y + radius)
            )
        )
        layer.stroke(s.circle(radius * 1.28, at: spot), with: .color(p.depth.opacity(0.5)), lineWidth: s.d(0.45))

        // The stone.
        let stone = s.circle(radius * 0.82, at: spot)
        let highlight = CGPoint(x: spot.x - radius * 0.3, y: spot.y - radius * 0.34)
        let stoneColours = isDone
            ? [p.gearHighlight, p.doneGlow, p.doneShade]
            : [p.rubyLight, p.rubyMid, p.rubyDark]
        layer.fill(stone, with: .radialGradient(ramp(stoneColours), center: highlight, startRadius: 0, endRadius: radius * 1.1))
        layer.fill(s.circle(radius * 0.2, at: highlight), with: .color(p.gearHighlight.opacity(0.85)))
    }

    // MARK: Selection

    /// A fine ring and four ticks around the selected task's wheel.
    static func selection(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        guard f.style == .fullColour,
              let id = f.selected,
              let gear = f.gears.first(where: { $0.taskID == id }),
              let wheel = WatchMovement.taskWheels.first(where: { $0.taskSlot == gear.slot })
        else { return }
        let p = f.palette
        var layer = ctx
        layer.clip(to: s.opening)
        let center = s.point(wheel.center)
        let radius = CGFloat(wheel.tipRadius) * s.unit + s.d(4.5)
        layer.stroke(s.circle(radius, at: center), with: .color(p.progress.opacity(0.28)), lineWidth: s.d(4.5))
        layer.stroke(s.circle(radius, at: center), with: .color(p.progress.opacity(0.95)), lineWidth: s.d(1.2))
        for quarter in 0..<4 {
            let direction = Double(quarter) * 90 + 45
            var tick = Path()
            tick.move(to: clockwisePoint(center, radius - s.d(2.6), direction))
            tick.addLine(to: clockwisePoint(center, radius + s.d(2.6), direction))
            layer.stroke(tick, with: .color(p.progress), style: StrokeStyle(lineWidth: s.d(1.5), lineCap: .round))
        }
    }

    // MARK: Helpers

    /// A point `radius` from `center` at `degrees` clockwise from 3 o'clock (the movement's own angles).
    private static func clockwisePoint(_ center: CGPoint, _ radius: CGFloat, _ degrees: Double) -> CGPoint {
        let radians = degrees * .pi / 180
        return CGPoint(x: center.x + radius * CGFloat(cos(radians)), y: center.y + radius * CGFloat(sin(radians)))
    }
}
