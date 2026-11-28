import Foundation

// The skeleton watch's movement layout, as pure data. Everything is in unit space: the dial opening has a
// radius of 1, the centre is the origin, x grows to the right and y grows DOWN (screen space). Angles are
// degrees, clockwise-positive (so a rotation of +90 turns a point at 3 o'clock to 6 o'clock). No SwiftUI or
// CoreGraphics types, so the painter, the tests and the later 3D version can all read the same layout.
//
// It is a real gear train: every driven wheel sits at exactly the sum of its pitch radius and its driver's,
// turns the opposite way, and turns in inverse proportion to its teeth. Tooth phases are chosen so that the
// teeth interleave at every moment. Each wheel records which wheel drives it (`meshesWith`).

/// A point in the movement's unit space.
public struct WatchPoint: Hashable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public func distance(to other: WatchPoint) -> Double {
        hypot(x - other.x, y - other.y)
    }

    /// Distance from the dial centre.
    public var radius: Double { hypot(x, y) }
}

/// What a wheel is for.
public enum WatchWheelRole: Equatable, Sendable {
    /// One of the eight wheels that stand for tasks. Slot 0 is the largest.
    case task(slot: Int)
    /// A plain train cog.
    case train
    /// A winding (keyless works) cog, on its own raised layer.
    case keyless
    /// The mainspring barrel.
    case barrel
}

/// One toothed wheel.
public struct WatchWheel: Equatable, Sendable, Identifiable {
    public let id: Int
    public let role: WatchWheelRole
    public let center: WatchPoint
    /// Radius of the pitch circle, where meshing wheels touch.
    public let pitchRadius: Double
    /// Radius to the tooth tips.
    public let tipRadius: Double
    /// Radius to the tooth roots.
    public let rootRadius: Double
    public let teeth: Int
    /// Wheels on different layers may overlap; wheels on the same layer never do.
    public let layer: Int
    /// Signed turning rate in degrees per second at rest (positive is clockwise).
    public let baseRate: Double
    /// Angle in degrees at time zero, chosen so meshing neighbours interleave.
    public let phase: Double
    /// The id of the wheel that drives this one, or nil for the root of a train.
    public let meshesWith: Int?

    public var taskSlot: Int? {
        if case .task(let slot) = role { return slot }
        return nil
    }

    /// Angle in degrees, `seconds` into the motion, with the rate scaled by `rateScale` (live task
    /// gears spin faster). Always in 0..<360.
    public func angle(atSeconds seconds: Double, rateScale: Double = 1) -> Double {
        WatchGeometry.wrap(
            phase + WatchGeometry.rotation(degreesPerSecond: baseRate * rateScale, seconds: seconds),
            360
        )
    }
}

/// The balance wheel.
public struct WatchBalance: Equatable, Sendable {
    public let center: WatchPoint
    /// Outer radius of the rim.
    public let radius: Double
    /// Swing either side of rest, in degrees.
    public let swingDegrees: Double
    /// Beats per second.
    public let frequency: Double
}

/// The pallet fork. The tail holds the balance's roller jewel; the two arms end in pallet stones that
/// release the escape wheel.
public struct WatchFork: Equatable, Sendable {
    public let pivot: WatchPoint
    /// Direction of the tail at rest, in degrees.
    public let tailAngle: Double
    public let tailLength: Double
    /// Length of each arm, which point away from the tail.
    public let armLength: Double
    /// Half the angle between the two arms, in degrees.
    public let armSpread: Double
    public let swingDegrees: Double
    /// The wheel the pallets release.
    public let escapeWheel: Int
}

/// The crown and the stem that runs in to the keyless works.
public struct WatchCrown: Equatable, Sendable {
    /// Centre of the crown, outside the case at 3 o'clock.
    public let center: WatchPoint
    public let width: Double
    public let height: Double
    /// Where the stem meets the keyless works (the centre of the first winding wheel).
    public let stemEnd: WatchPoint
    /// The wheel the stem drives.
    public let windingWheel: Int
}

/// A thin bridge arm that carries the pivots of the wheels under it.
public struct WatchBridge: Equatable, Sendable, Identifiable {
    public let id: Int
    /// Pivot positions the arm passes over: screws and jewels go here.
    public let hubs: [WatchPoint]
    /// Closed outline, clockwise on screen.
    public let outline: [WatchPoint]
    /// The arm stands above the wheels on this layer or below.
    public let layer: Int
}

public enum WatchMovement {
    /// The dial opening.
    public static let openingRadius = 1.0
    /// Gear slots for tasks: the same number the geometry rules bind tasks to.
    public static let taskSlots = WatchGeometry.taskGearSlots
    /// Swing frequency of the balance, in beats per second.
    public static let beatFrequency = 1.25

    /// Design pixels of the prototype (opening radius 122) to unit space.
    private static let pixel = 1.0 / 122.0
    /// Gear module in unit space: the tooth pitch is the same for every wheel, so they can all mesh.
    private static let module = 2.6 * pixel

    // MARK: Wheels

    /// The 20 wheels: ids 0...7 are the task slots (0 the largest), 8...16 train cogs, 17...19 keyless.
    public static let wheels: [WatchWheel] = buildWheels()

    /// The task wheels in slot order.
    public static let taskWheels: [WatchWheel] = wheels.filter { $0.taskSlot != nil }.sorted {
        ($0.taskSlot ?? 0) < ($1.taskSlot ?? 0)
    }

    /// The mainspring barrel. It meshes the wheel at slot 2.
    public static let barrel: WatchWheel = buildBarrel()

    /// Every wheel including the barrel.
    public static let allWheels: [WatchWheel] = wheels + [barrel]

    public static func wheel(id: Int) -> WatchWheel? {
        allWheels.first { $0.id == id }
    }

    // MARK: Escapement

    public static let balance = WatchBalance(
        center: point(180, 298),
        radius: 26 * pixel,
        swingDegrees: 210,
        frequency: beatFrequency
    )

    public static let fork: WatchFork = {
        let pivot = point(205, 270)
        let tail = atan2(balance.center.y - pivot.y, balance.center.x - pivot.x) * 180 / .pi
        return WatchFork(
            pivot: pivot,
            tailAngle: tail,
            tailLength: 30 * pixel,
            armLength: 12 * pixel,
            armSpread: 22,
            swingDegrees: 9,
            escapeWheel: 4
        )
    }()

    /// Balance angle, in degrees, `seconds` into the motion.
    public static func balanceAngle(atSeconds seconds: Double) -> Double {
        balance.swingDegrees * sin(2 * .pi * beatPhase(seconds))
    }

    /// Fork angle, in degrees, a little out of step with the balance, as the roller jewel drives it.
    public static func forkAngle(atSeconds seconds: Double) -> Double {
        fork.swingDegrees * sin(2 * .pi * beatPhase(seconds) + 0.6)
    }

    /// Beats elapsed, reduced to one period so long sessions keep their precision.
    private static func beatPhase(_ seconds: Double) -> Double {
        let beats = seconds * beatFrequency
        return beats - beats.rounded(.down)
    }

    // MARK: Crown

    public static let crown: WatchCrown = {
        let winding = wheels.first { $0.role == .keyless }
        return WatchCrown(
            center: point(338, 220),
            width: 14 * pixel,
            height: 30 * pixel,
            stemEnd: winding?.center ?? point(268, 220),
            windingWheel: winding?.id ?? 17
        )
    }()

    // MARK: Bridges

    public static let bridges: [WatchBridge] = buildBridges()

    // MARK: Construction

    private static func point(_ pixelX: Double, _ pixelY: Double) -> WatchPoint {
        WatchPoint(x: (pixelX - 180) * pixel, y: (pixelY - 220) * pixel)
    }

    private struct Spec: Sendable {
        let id: Int
        let teeth: Int
        let parent: Int?
        /// Direction from the driver to this wheel, degrees.
        let angle: Double
        let layer: Int
        let role: WatchWheelRole
        /// Centre in prototype pixels, for the root of a train.
        let root: (x: Double, y: Double)?
        /// Rate of a root wheel; driven wheels derive theirs.
        let rate: Double
    }

    private static let specs: [Spec] = [
        // The task train, driven from the centre wheel (slot 1) under the hands.
        Spec(id: 1, teeth: 20, parent: nil, angle: 0, layer: 0, role: .task(slot: 1), root: (180, 220), rate: 5),
        Spec(id: 0, teeth: 26, parent: 1, angle: -142, layer: 0, role: .task(slot: 0), root: nil, rate: 0),
        Spec(id: 2, teeth: 16, parent: 1, angle: -38, layer: 0, role: .task(slot: 2), root: nil, rate: 0),
        Spec(id: 3, teeth: 13, parent: 2, angle: 62, layer: 0, role: .task(slot: 3), root: nil, rate: 0),
        Spec(id: 4, teeth: 11, parent: 3, angle: 112, layer: 0, role: .task(slot: 4), root: nil, rate: 0),
        Spec(id: 5, teeth: 10, parent: 0, angle: 108, layer: 0, role: .task(slot: 5), root: nil, rate: 0),
        Spec(id: 6, teeth: 9, parent: 0, angle: -72, layer: 0, role: .task(slot: 6), root: nil, rate: 0),
        Spec(id: 7, teeth: 8, parent: 5, angle: 78, layer: 0, role: .task(slot: 7), root: nil, rate: 0),
        // Train cogs.
        Spec(id: 8, teeth: 8, parent: 6, angle: -30, layer: 0, role: .train, root: nil, rate: 0),
        Spec(id: 9, teeth: 6, parent: 8, angle: -20, layer: 0, role: .train, root: nil, rate: 0),
        Spec(id: 10, teeth: 9, parent: 0, angle: 178, layer: 0, role: .train, root: nil, rate: 0),
        Spec(id: 11, teeth: 6, parent: 15, angle: 150, layer: 0, role: .train, root: nil, rate: 0),
        Spec(id: 12, teeth: 9, parent: 4, angle: 30, layer: 0, role: .train, root: nil, rate: 0),
        Spec(id: 13, teeth: 7, parent: 12, angle: 60, layer: 0, role: .train, root: nil, rate: 0),
        Spec(id: 14, teeth: 6, parent: 13, angle: 150, layer: 0, role: .train, root: nil, rate: 0),
        Spec(id: 15, teeth: 8, parent: 7, angle: 170, layer: 0, role: .train, root: nil, rate: 0),
        Spec(id: 16, teeth: 7, parent: 10, angle: 100, layer: 0, role: .train, root: nil, rate: 0),
        // The keyless works: crown wheel and its train, on a raised layer of their own.
        Spec(id: 17, teeth: 12, parent: nil, angle: 0, layer: 1, role: .keyless, root: (268, 220), rate: 8),
        Spec(id: 18, teeth: 7, parent: 17, angle: 90, layer: 1, role: .keyless, root: nil, rate: 0),
        Spec(id: 19, teeth: 6, parent: 18, angle: 120, layer: 1, role: .keyless, root: nil, rate: 0)
    ]

    private static let barrelSpec = Spec(
        id: 20, teeth: 18, parent: 2, angle: -75, layer: 0, role: .barrel, root: nil, rate: 0
    )

    private static func buildWheels() -> [WatchWheel] {
        var placed: [Int: WatchWheel] = [:]
        var pending = specs
        while !pending.isEmpty {
            let before = pending.count
            pending.removeAll { spec in
                guard let wheel = make(spec, placed: placed) else { return false }
                placed[spec.id] = wheel
                return true
            }
            if pending.count == before { break }
        }
        return placed.values.sorted { $0.id < $1.id }
    }

    private static func buildBarrel() -> WatchWheel {
        var placed: [Int: WatchWheel] = [:]
        for wheel in wheels { placed[wheel.id] = wheel }
        // `barrelSpec` only names wheels that exist, so this cannot fail; the fallback keeps it total.
        return make(barrelSpec, placed: placed)
            ?? WatchWheel(
                id: 20, role: .barrel, center: point(228, 148), pitchRadius: 0.2, tipRadius: 0.21, rootRadius: 0.18,
                teeth: 18, layer: 0, baseRate: 0, phase: 0, meshesWith: nil
            )
    }

    /// Places one wheel against its driver, or returns nil while the driver is not placed yet.
    private static func make(_ spec: Spec, placed: [Int: WatchWheel]) -> WatchWheel? {
        let pitch = Double(spec.teeth) * module / 2
        let tip = pitch + module
        let root = pitch - 1.25 * module

        guard let parentID = spec.parent else {
            guard let rootPoint = spec.root else { return nil }
            return WatchWheel(
                id: spec.id, role: spec.role, center: point(rootPoint.x, rootPoint.y),
                pitchRadius: pitch, tipRadius: tip, rootRadius: root, teeth: spec.teeth,
                layer: spec.layer, baseRate: spec.rate, phase: 0, meshesWith: nil
            )
        }
        guard let driver = placed[parentID] else { return nil }

        let direction = spec.angle * .pi / 180
        let distance = driver.pitchRadius + pitch
        let center = WatchPoint(
            x: driver.center.x + distance * cos(direction),
            y: driver.center.y + distance * sin(direction)
        )
        // Opposite direction, inversely proportional to the teeth.
        let rate = -driver.baseRate * Double(driver.teeth) / Double(spec.teeth)
        // Tooth phase so the teeth interleave: with f = (contact angle - wheel angle) in tooth pitches,
        // f(driver) + f(driven) stays at one half for as long as both turn at their base rates.
        let toward = spec.angle
        let driverTeeth = Double(driver.teeth)
        let drivenTeeth = Double(spec.teeth)
        let raw = toward + 180 - (180 - (toward - driver.phase) * driverTeeth) / drivenTeeth
        let phase = WatchGeometry.wrap(raw, 360)
        return WatchWheel(
            id: spec.id, role: spec.role, center: center, pitchRadius: pitch, tipRadius: tip, rootRadius: root,
            teeth: spec.teeth, layer: spec.layer, baseRate: rate, phase: phase, meshesWith: parentID
        )
    }

    // MARK: Bridge construction

    private static func buildBridges() -> [WatchBridge] {
        let centers = Dictionary(uniqueKeysWithValues: allWheels.map { ($0.id, $0.center) })
        func hubs(_ ids: [Int]) -> [WatchPoint] { ids.compactMap { centers[$0] } }

        // Two long arms, laid only between wheels that do not mesh, so no arm ever covers a tooth contact.
        let arms: [(ids: [Int], layer: Int)] = [
            ([5, 1, 4], 0),
            ([0, 2, 17], 1)
        ]
        var result: [WatchBridge] = arms.enumerated().map { index, arm in
            let points = hubs(arm.ids)
            return WatchBridge(
                id: index,
                hubs: points,
                outline: armOutline(points, startHalfWidth: 6.4 * pixel, endHalfWidth: 4.8 * pixel),
                layer: arm.layer
            )
        }

        // Every other pivot sits under its own small cap, screwed down.
        let armed = Set(arms.flatMap { $0.ids })
        for wheel in allWheels where !armed.contains(wheel.id) {
            let radius = min(6.2 * pixel, wheel.rootRadius * 0.82)
            result.append(
                WatchBridge(
                    id: result.count,
                    hubs: [wheel.center],
                    outline: capOutline(wheel.center, radius: radius),
                    layer: wheel.layer
                )
            )
        }

        // The balance cock: a curved arm over the top of the balance, ending in two feet.
        let cockCenter = balance.center
        let cockRadius = balance.radius + 7 * pixel
        let sweep = stride(from: 212.0, through: 328.0, by: 29.0).map { degrees -> WatchPoint in
            let radians = degrees * .pi / 180
            return WatchPoint(x: cockCenter.x + cockRadius * cos(radians), y: cockCenter.y + cockRadius * sin(radians))
        }
        result.append(
            WatchBridge(
                id: result.count,
                hubs: [sweep[0], cockCenter, sweep[sweep.count - 1]],
                outline: armOutline(sweep, startHalfWidth: 4.6 * pixel, endHalfWidth: 4.6 * pixel),
                layer: 2
            )
        )
        return result
    }

    /// A round cap plate as a 20-sided outline.
    static func capOutline(_ center: WatchPoint, radius: Double) -> [WatchPoint] {
        (0..<20).map { step in
            let angle = Double(step) * 2 * .pi / 20
            return WatchPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
        }
    }

    /// The outline of a tapered arm along `path`, with round ends and mitred bends.
    static func armOutline(_ path: [WatchPoint], startHalfWidth: Double, endHalfWidth: Double) -> [WatchPoint] {
        let count = path.count
        guard count >= 2 else { return path }
        func halfWidth(_ index: Int) -> Double {
            startHalfWidth + (endHalfWidth - startHalfWidth) * Double(index) / Double(count - 1)
        }
        func unit(from: WatchPoint, to: WatchPoint) -> (x: Double, y: Double) {
            let length = max(from.distance(to: to), 1e-12)
            return ((to.x - from.x) / length, (to.y - from.y) / length)
        }

        var left: [WatchPoint] = []
        var right: [WatchPoint] = []
        for index in 0..<count {
            let here = path[index]
            let incoming = index > 0 ? unit(from: path[index - 1], to: here) : unit(from: here, to: path[1])
            let outgoing = index < count - 1 ? unit(from: here, to: path[index + 1]) : incoming
            var tangent = (x: incoming.x + outgoing.x, y: incoming.y + outgoing.y)
            let tangentLength = max(hypot(tangent.x, tangent.y), 1e-12)
            tangent = (tangent.x / tangentLength, tangent.y / tangentLength)
            let normal = (x: -tangent.y, y: tangent.x)
            // Widen the inside of a bend so the arm keeps its thickness, within a limit.
            let across = max(normal.x * -incoming.y + normal.y * incoming.x, 0.55)
            let reach = halfWidth(index) / across
            left.append(WatchPoint(x: here.x + normal.x * reach, y: here.y + normal.y * reach))
            right.append(WatchPoint(x: here.x - normal.x * reach, y: here.y - normal.y * reach))
        }

        let capSteps = 8
        var outline = left
        let tip = path[count - 1]
        let tipStart = atan2(left[count - 1].y - tip.y, left[count - 1].x - tip.x)
        for step in 1..<capSteps {
            let angle = tipStart - Double.pi * Double(step) / Double(capSteps)
            outline.append(WatchPoint(
                x: tip.x + halfWidth(count - 1) * cos(angle),
                y: tip.y + halfWidth(count - 1) * sin(angle)
            ))
        }
        outline.append(contentsOf: right.reversed())
        let tail = path[0]
        let tailStart = atan2(right[0].y - tail.y, right[0].x - tail.x)
        for step in 1..<capSteps {
            let angle = tailStart - Double.pi * Double(step) / Double(capSteps)
            outline.append(WatchPoint(
                x: tail.x + halfWidth(0) * cos(angle),
                y: tail.y + halfWidth(0) * sin(angle)
            ))
        }
        return outline
    }
}
