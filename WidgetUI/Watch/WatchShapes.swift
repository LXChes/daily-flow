import DailyFlowCore
import SwiftUI

/// Paths the watch painter reuses on every draw, built once in the movement's unit space (the dial
/// opening has a radius of 1). Wheels are centred on the origin and unrotated: the painter moves, turns
/// and scales them with one transform, so a spinning wheel costs a matrix, not a rebuild.
enum WatchShapes {
    /// Toothed outline of every wheel, with its spoke cut-outs as inner sub-paths (fill with even-odd).
    static let wheelBodies: [Int: Path] = {
        var result: [Int: Path] = [:]
        for wheel in WatchMovement.allWheels {
            var path = toothOutline(wheel)
            path.addPath(spokeHoles(wheel))
            result[wheel.id] = path
        }
        return result
    }()

    /// Only the cut-outs, for the polished inner edges.
    static let wheelHoles: [Int: Path] = {
        var result: [Int: Path] = [:]
        for wheel in WatchMovement.allWheels {
            result[wheel.id] = spokeHoles(wheel)
        }
        return result
    }()

    /// The bare toothed outline, no cut-outs: for the Lock Screen silhouettes and the shadows.
    static let wheelOutlines: [Int: Path] = {
        var result: [Int: Path] = [:]
        for wheel in WatchMovement.allWheels {
            result[wheel.id] = toothOutline(wheel)
        }
        return result
    }()

    /// Bridge arms in absolute unit space, in the same order as `WatchMovement.bridges`.
    static let bridgeOutlines: [Path] = WatchMovement.bridges.map { bridge in
        var path = Path()
        for (index, point) in bridge.outline.enumerated() {
            let cg = CGPoint(x: point.x, y: point.y)
            if index == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
        }
        path.closeSubpath()
        return path
    }

    /// The hairspring, centred on the origin: eight turns out to just inside the balance rim.
    static let hairspring: Path = spiral(inner: 0.022, outer: WatchMovement.balance.radius * 0.6, turns: 8, steps: 260)

    /// The mainspring as seen through the barrel's open side, centred on the origin.
    static let mainspring: Path = {
        let barrel = WatchMovement.barrel
        return spiral(inner: barrel.rootRadius * 0.2, outer: barrel.rootRadius * 0.82, turns: 6, steps: 220)
    }()

    // MARK: Builders

    /// An Archimedean spiral.
    private static func spiral(inner: Double, outer: Double, turns: Double, steps: Int) -> Path {
        var path = Path()
        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let angle = t * turns * 2 * .pi
            let radius = inner + (outer - inner) * t
            let point = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }

    /// Involute-ish teeth: a flank that widens from the tip to the root, with a shouldered tip.
    private static func toothOutline(_ wheel: WatchWheel) -> Path {
        var path = Path()
        let teeth = wheel.teeth
        let pitchAngle = 2 * Double.pi / Double(teeth)
        let root = wheel.rootRadius
        let pitch = wheel.pitchRadius
        let tip = wheel.tipRadius
        let flank = (root + pitch) / 2
        let shoulder = pitch + (tip - pitch) * 0.72
        var started = false

        func add(_ radius: Double, _ angle: Double) {
            let point = CGPoint(x: radius * cos(angle), y: radius * sin(angle))
            if started {
                path.addLine(to: point)
            } else {
                path.move(to: point)
                started = true
            }
        }

        for tooth in 0..<teeth {
            let centre = Double(tooth) * pitchAngle
            add(root, centre - 0.46 * pitchAngle)
            add(flank, centre - 0.35 * pitchAngle)
            add(pitch, centre - 0.235 * pitchAngle)
            add(shoulder, centre - 0.16 * pitchAngle)
            add(tip, centre - 0.085 * pitchAngle)
            add(tip, centre + 0.085 * pitchAngle)
            add(shoulder, centre + 0.16 * pitchAngle)
            add(pitch, centre + 0.235 * pitchAngle)
            add(flank, centre + 0.35 * pitchAngle)
            add(root, centre + 0.46 * pitchAngle)
        }
        path.closeSubpath()
        return path
    }

    /// Cut-outs between spokes for big wheels, three round holes for middling ones, none for pinions.
    private static func spokeHoles(_ wheel: WatchWheel) -> Path {
        var path = Path()
        let teeth = wheel.teeth
        let root = wheel.rootRadius

        if teeth >= 13 {
            let spokes = teeth >= 24 ? 6 : (teeth >= 18 ? 5 : 4)
            let hub = wheel.tipRadius * 0.27
            let rim = root * 0.80
            let halfWidth = root * 0.085
            let sector = 2 * Double.pi / Double(spokes)
            let offset = -Double.pi / 2
            for index in 0..<spokes {
                let from = offset + Double(index) * sector
                let to = from + sector
                let outerGap = asin(min(halfWidth / rim, 0.99))
                let innerGap = asin(min(halfWidth / hub, 0.99))
                let steps = 7
                for step in 0...steps {
                    let t = Double(step) / Double(steps)
                    let angle = from + outerGap + (to - from - 2 * outerGap) * t
                    let point = CGPoint(x: rim * cos(angle), y: rim * sin(angle))
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                for step in 0...steps {
                    let t = Double(step) / Double(steps)
                    let angle = to - innerGap - (to - from - 2 * innerGap) * t
                    path.addLine(to: CGPoint(x: hub * cos(angle), y: hub * sin(angle)))
                }
                path.closeSubpath()
            }
        } else if teeth >= 10 {
            let radius = root * 0.2
            let ring = root * 0.56
            for index in 0..<3 {
                let angle = -Double.pi / 2 + Double(index) * 2 * Double.pi / 3
                let center = CGPoint(x: ring * cos(angle), y: ring * sin(angle))
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
        }
        return path
    }
}
