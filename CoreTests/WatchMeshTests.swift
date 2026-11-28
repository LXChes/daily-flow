import Foundation
import simd
import Testing
@testable import DailyFlowCore

/// Welds vertices that sit in the same place (normals and UVs ignored), so edges can be matched across
/// split-normal seams.
private struct PointKey: Hashable, Comparable {
    let x: Int
    let y: Int
    let z: Int

    init(_ p: SIMD3<Float>) {
        x = Int((p.x * 10_000).rounded())
        y = Int((p.y * 10_000).rounded())
        z = Int((p.z * 10_000).rounded())
    }

    static func < (lhs: PointKey, rhs: PointKey) -> Bool {
        (lhs.x, lhs.y, lhs.z) < (rhs.x, rhs.y, rhs.z)
    }
}

private struct EdgeKey: Hashable {
    let low: PointKey
    let high: PointKey

    init(_ a: PointKey, _ b: PointKey) {
        if a < b {
            low = a
            high = b
        } else {
            low = b
            high = a
        }
    }
}

private struct NamedMesh {
    let name: String
    let mesh: WatchMeshData
}

private let wheelThickness: Float = 0.04
private let wheelArbor: Float = 0.012
private let wheelBevel: Float = 0.004

private func buildWheel(_ wheel: WatchWheel) -> WatchMeshData {
    WatchMesh.wheel(
        wheel, thickness: wheelThickness, spokes: WatchMesh.spokeCount(for: wheel), arbor: wheelArbor,
        bevel: wheelBevel
    )
}

private func buildBridge(_ bridge: WatchBridge) -> WatchMeshData {
    let outline = bridge.outline.map { SIMD2<Float>(Float($0.x), Float(-$0.y)) }
    return WatchMesh.extrude(outline, depth: 0.03, bevel: 0.004)
}

/// Every kind of part the watch is made of, built the way the renderer will build them.
private func everyPart() -> [NamedMesh] {
    var parts: [NamedMesh] = []
    for wheel in WatchMovement.allWheels {
        parts.append(NamedMesh(name: "wheel \(wheel.id)", mesh: buildWheel(wheel)))
    }
    for bridge in WatchMovement.bridges {
        parts.append(NamedMesh(name: "bridge \(bridge.id)", mesh: buildBridge(bridge)))
    }
    let styles: [(String, WatchMesh.HandStyle)] = [
        ("baton", .baton), ("breguet", .breguet), ("arrow", .arrow), ("seconds", .seconds)
    ]
    for (name, style) in styles {
        let hand = WatchMesh.hand(style, length: 0.9, width: 0.05, tail: 0.2, height: 0.02)
        parts.append(NamedMesh(name: "hand \(name)", mesh: hand.body))
        if !hand.lume.positions.isEmpty { parts.append(NamedMesh(name: "lume \(name)", mesh: hand.lume)) }
    }
    parts.append(NamedMesh(name: "balance", mesh: WatchMesh.balance(radius: 0.21, thickness: 0.04)))
    parts.append(NamedMesh(
        name: "hairspring", mesh: WatchMesh.hairspring(inner: 0.02, outer: 0.12, turns: 8, width: 0.004, height: 0.01)
    ))
    parts.append(NamedMesh(name: "ring", mesh: WatchMesh.ring(inner: 0.8, outer: 1.0, segments: 48)))
    parts.append(NamedMesh(
        name: "dome",
        mesh: WatchMesh.lathe(
            [SIMD2<Float>(1, 0), SIMD2<Float>(0.9, 0.1), SIMD2<Float>(0.6, 0.25), SIMD2<Float>(0, 0.3)],
            segments: 32
        )
    ))
    return parts
}

private func scaling(_ s: SIMD3<Float>) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.0.x = s.x
    m.columns.1.y = s.y
    m.columns.2.z = s.z
    return m
}

@Suite("Watch mesh")
struct WatchMeshTests {
    private static let parts = everyPart()

    private func corners(_ mesh: WatchMeshData, _ triangle: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        (
            mesh.positions[Int(mesh.indices[triangle * 3])],
            mesh.positions[Int(mesh.indices[triangle * 3 + 1])],
            mesh.positions[Int(mesh.indices[triangle * 3 + 2])]
        )
    }

    /// Twice the area, with the sign of the winding seen from +z.
    private func area2(_ points: [SIMD2<Float>], _ triangle: [UInt32]) -> Float {
        let a = points[Int(triangle[0])], b = points[Int(triangle[1])], c = points[Int(triangle[2])]
        return (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private func shoelace(_ points: [SIMD2<Float>]) -> Float {
        var sum: Float = 0
        for i in 0..<points.count {
            let p = points[i]
            let q = points[(i + 1) % points.count]
            sum += p.x * q.y - q.x * p.y
        }
        return sum / 2
    }

    // MARK: Structure

    @Test func everyPartHasConsistentArrays() {
        for part in Self.parts {
            let mesh = part.mesh
            #expect(!mesh.positions.isEmpty, "\(part.name) is empty")
            #expect(mesh.normals.count == mesh.positions.count, "\(part.name) normals")
            #expect(mesh.uvs.count == mesh.positions.count, "\(part.name) uvs")
            #expect(mesh.indices.count % 3 == 0, "\(part.name) index count")
            #expect(mesh.indices.allSatisfy { Int($0) < mesh.positions.count }, "\(part.name) index range")
            #expect(mesh.triangleCount == mesh.indices.count / 3)
        }
    }

    @Test func everyNormalIsUnitLengthAndFinite() {
        for part in Self.parts {
            for n in part.mesh.normals {
                #expect(abs(simd_length(n) - 1) < 1e-3, "\(part.name) normal \(n)")
            }
            for p in part.mesh.positions {
                #expect(p.x.isFinite && p.y.isFinite && p.z.isFinite, "\(part.name) position")
            }
        }
    }

    @Test func noTriangleIsDegenerate() {
        for part in Self.parts {
            for t in 0..<part.mesh.triangleCount {
                let (a, b, c) = corners(part.mesh, t)
                #expect(simd_length_squared(simd_cross(b - a, c - a)) > 1e-18, "\(part.name) triangle \(t)")
            }
        }
    }

    @Test func windingAgreesWithNormals() {
        for part in Self.parts {
            let mesh = part.mesh
            for t in 0..<mesh.triangleCount {
                let (a, b, c) = corners(mesh, t)
                let shading = mesh.normals[Int(mesh.indices[t * 3])]
                    + mesh.normals[Int(mesh.indices[t * 3 + 1])]
                    + mesh.normals[Int(mesh.indices[t * 3 + 2])]
                #expect(simd_dot(simd_cross(b - a, c - a), shading) > 0, "\(part.name) triangle \(t)")
            }
        }
    }

    // MARK: Triangulation

    @Test func convexPolygonTriangulatesToNMinusTwoCoveringTheArea() {
        let hexagon = (0..<6).map { i -> SIMD2<Float> in
            let angle = Float(i) * Float.pi / 3
            return SIMD2<Float>(2 * cos(angle), 2 * sin(angle))
        }
        let indices = WatchMesh.triangulate(hexagon)
        #expect(indices.count == 4 * 3)
        var total: Float = 0
        for chunk in stride(from: 0, to: indices.count, by: 3) {
            let area = area2(hexagon, Array(indices[chunk..<(chunk + 3)])) / 2
            #expect(area > 0)
            total += area
        }
        #expect(abs(total - shoelace(hexagon)) < 1e-4)
    }

    @Test func concavePolygonsTriangulateExactly() {
        let lShape: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(3, 0), SIMD2<Float>(3, 1),
            SIMD2<Float>(1, 1), SIMD2<Float>(1, 3), SIMD2<Float>(0, 3)
        ]
        var star: [SIMD2<Float>] = []
        for i in 0..<10 {
            let radius: Float = i % 2 == 0 ? 2 : 0.8
            let angle = Float(i) * Float.pi / 5
            star.append(SIMD2<Float>(radius * cos(angle), radius * sin(angle)))
        }
        for polygon in [lShape, star, lShape.reversed()] {
            let indices = WatchMesh.triangulate(polygon)
            #expect(indices.count == (polygon.count - 2) * 3)
            var total: Float = 0
            for chunk in stride(from: 0, to: indices.count, by: 3) {
                let area = area2(polygon, Array(indices[chunk..<(chunk + 3)])) / 2
                #expect(area > 0, "triangles are counter-clockwise")
                total += area
            }
            #expect(abs(total - abs(shoelace(polygon))) < 1e-4)
        }
        #expect(abs(shoelace(lShape) - 5) < 1e-5)
    }

    @Test func triangulateHandlesTooFewPoints() {
        #expect(WatchMesh.triangulate([]).isEmpty)
        #expect(WatchMesh.triangulate([SIMD2<Float>(0, 0), SIMD2<Float>(1, 0)]).isEmpty)
    }

    // MARK: Wheels

    @Test func wheelHasExactlyOneTipPerToothAtTheTipRadius() {
        for wheel in WatchMovement.allWheels {
            let mesh = buildWheel(wheel)
            let tip = Float(wheel.tipRadius)
            let pitch = 2 * Float.pi / Float(wheel.teeth)
            var teethSeen = Set<Int>()
            var farthest: Float = 0
            for p in mesh.positions {
                let radius = simd_length(SIMD2<Float>(p.x, p.y))
                farthest = max(farthest, radius)
                guard abs(radius - tip) < 1e-5 else { continue }
                var angle = atan2(p.y, p.x)
                if angle < 0 { angle += 2 * Float.pi }
                teethSeen.insert(Int((angle / pitch).rounded()) % wheel.teeth)
            }
            #expect(teethSeen.count == wheel.teeth, "wheel \(wheel.id) tips")
            #expect(farthest <= tip + 1e-5, "wheel \(wheel.id) stays inside its tip circle")
        }
    }

    @Test func wheelKeepsItsArborHoleAndLayerHeights() {
        for wheel in WatchMovement.allWheels {
            let mesh = buildWheel(wheel)
            let hole = max(0.002, min(wheelArbor, Float(wheel.rootRadius) * 0.25))
            var nearest = Float.infinity
            var top = -Float.infinity
            var bottom = Float.infinity
            for p in mesh.positions {
                nearest = min(nearest, simd_length(SIMD2<Float>(p.x, p.y)))
                top = max(top, p.z)
                bottom = min(bottom, p.z)
            }
            #expect(abs(nearest - hole) < 1e-3, "wheel \(wheel.id) arbor")
            #expect(abs(top) < 1e-6, "wheel \(wheel.id) top face at z = 0")
            #expect(abs(bottom + wheelThickness) < 1e-6, "wheel \(wheel.id) bottom at -thickness")
        }
    }

    @Test func wheelTopFaceLooksUp() {
        for wheel in WatchMovement.allWheels {
            let mesh = buildWheel(wheel)
            var flatTops = 0
            for t in 0..<mesh.triangleCount {
                let (a, b, c) = corners(mesh, t)
                guard abs(a.z) < 1e-6, abs(b.z) < 1e-6, abs(c.z) < 1e-6 else { continue }
                flatTops += 1
                #expect(simd_cross(b - a, c - a).z > 0, "wheel \(wheel.id) top triangle \(t)")
            }
            #expect(flatTops > wheel.teeth, "wheel \(wheel.id) has a top face")
        }
    }

    @Test func spokeCountsFollowThePainter() {
        for wheel in WatchMovement.allWheels {
            let spokes = WatchMesh.spokeCount(for: wheel)
            if wheel.role == .barrel {
                #expect(spokes == 0)
            } else if wheel.teeth >= 24 {
                #expect(spokes == 6)
            } else if wheel.teeth >= 18 {
                #expect(spokes == 5)
            } else if wheel.teeth >= 13 {
                #expect(spokes == 4)
            } else {
                #expect(spokes == 0)
            }
        }
        #expect(WatchMovement.taskWheels.first.map { WatchMesh.spokeCount(for: $0) } == 6)
    }

    @Test func spokedWheelsAreOpenAndSolidOnesAreNot() {
        guard let big = WatchMovement.taskWheels.first, let small = WatchMovement.taskWheels.last else {
            Issue.record("no task wheels")
            return
        }
        // The spokes remove material, so a spoked wheel has fewer top-face triangles reaching the middle
        // than the same wheel as a solid web has; here, check no top vertex lies mid-window.
        let spoked = WatchMesh.wheel(big, thickness: 0.04, spokes: 6, arbor: 0.012, bevel: 0.004)
        let rim = Float(big.rootRadius) * 0.80
        let hub = Float(big.tipRadius) * 0.27
        let midRadius = (rim + hub) / 2
        var windowCentreCovered = false
        for k in 0..<6 {
            // Half way between two spokes, at the middle radius: inside a window.
            let sweep: Float = 0.32 * 0.5
            let angle = Float.pi / 2 + (Float(k) + 0.5) * Float.pi / 3 + sweep
            let probe = SIMD2<Float>(midRadius * cos(angle), midRadius * sin(angle))
            for t in 0..<spoked.triangleCount {
                let (a, b, c) = corners(spoked, t)
                guard abs(a.z) < 1e-6, abs(b.z) < 1e-6, abs(c.z) < 1e-6 else { continue }
                if pointInTriangle(probe, SIMD2<Float>(a.x, a.y), SIMD2<Float>(b.x, b.y), SIMD2<Float>(c.x, c.y)) {
                    windowCentreCovered = true
                }
            }
        }
        #expect(!windowCentreCovered)
        let solid = WatchMesh.wheel(small, thickness: 0.04, spokes: 0, arbor: 0.012, bevel: 0.004)
        #expect(solid.triangleCount > 0)
    }

    private func pointInTriangle(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        func side(_ u: SIMD2<Float>, _ v: SIMD2<Float>, _ w: SIMD2<Float>) -> Float {
            (v.x - u.x) * (w.y - u.y) - (v.y - u.y) * (w.x - u.x)
        }
        let d1 = side(a, b, p), d2 = side(b, c, p), d3 = side(c, a, p)
        let hasNegative = d1 < 0 || d2 < 0 || d3 < 0
        let hasPositive = d1 > 0 || d2 > 0 || d3 > 0
        return !(hasNegative && hasPositive)
    }

    @Test func triangleBudgets() {
        var biggest = 0
        var total = 0
        for wheel in WatchMovement.allWheels {
            let count = buildWheel(wheel).triangleCount
            biggest = max(biggest, count)
            total += count
            #expect(count <= 6000, "wheel \(wheel.id) has \(count) triangles")
        }
        for bridge in WatchMovement.bridges { total += buildBridge(bridge).triangleCount }
        total += WatchMesh.balance(radius: 0.21, thickness: 0.04).triangleCount
        total += WatchMesh.hairspring(inner: 0.02, outer: 0.12, turns: 8, width: 0.004, height: 0.01).triangleCount
        print("WatchMesh: biggest wheel \(biggest) triangles, movement parts \(total) triangles")
        #expect(total < 120_000)
    }

    // MARK: Lathe, ring

    @Test func closedCylinderLatheSharesEveryEdgeTwice() {
        let profile: [SIMD2<Float>] = [
            SIMD2<Float>(0, -1), SIMD2<Float>(1, -1), SIMD2<Float>(1, 0), SIMD2<Float>(0, 0)
        ]
        let mesh = WatchMesh.lathe(profile, segments: 12, creases: [1, 2])
        var counts: [EdgeKey: Int] = [:]
        for t in 0..<mesh.triangleCount {
            let keys = (0..<3).map { PointKey(mesh.positions[Int(mesh.indices[t * 3 + $0])]) }
            for e in 0..<3 {
                let a = keys[e], b = keys[(e + 1) % 3]
                if a == b { continue }
                counts[EdgeKey(a, b), default: 0] += 1
            }
        }
        #expect(!counts.isEmpty)
        #expect(counts.values.allSatisfy { $0 == 2 })
    }

    @Test func creasedLatheSplitsNormalsAndSmoothLatheDoesNot() {
        let profile: [SIMD2<Float>] = [
            SIMD2<Float>(0, -1), SIMD2<Float>(1, -1), SIMD2<Float>(1, 0), SIMD2<Float>(0, 0)
        ]
        let hard = WatchMesh.lathe(profile, segments: 12, creases: [1, 2])
        let soft = WatchMesh.lathe(profile, segments: 12)
        #expect(hard.positions.count > soft.positions.count)
        // With creases the wall normal is exactly radial.
        for (p, n) in zip(hard.positions, hard.normals) where abs(simd_length(SIMD2<Float>(p.x, p.y)) - 1) < 1e-6 {
            if abs(p.z + 0.5) < 0.6 && abs(n.z) < 1e-6 {
                #expect(abs(simd_dot(SIMD2<Float>(n.x, n.y), SIMD2<Float>(p.x, p.y)) - 1) < 1e-5)
            }
        }
    }

    @Test func ringFacesUpAndHasPlanarUVs() {
        let mesh = WatchMesh.ring(inner: 0.3, outer: 1.25, segments: 16)
        #expect(mesh.triangleCount == 32)
        for t in 0..<mesh.triangleCount {
            let (a, b, c) = corners(mesh, t)
            #expect(simd_cross(b - a, c - a).z > 0)
        }
        for n in mesh.normals { #expect(n == SIMD3<Float>(0, 0, 1)) }
        // The first outer vertex is at (1.25, 0): the right edge, vertical middle.
        #expect(abs(mesh.uvs[0].x - 1) < 1e-6)
        #expect(abs(mesh.uvs[0].y - 0.5) < 1e-6)
        let disc = WatchMesh.ring(inner: 0, outer: 1, segments: 12)
        #expect(disc.triangleCount == 12)
        #expect(WatchMesh.ring(inner: 1, outer: 0.5, segments: 8).positions.isEmpty)
    }

    // MARK: Extrude

    @Test func extrudeTopFaceLooksUpWhateverTheInputWinding() {
        let outline: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(3, 0), SIMD2<Float>(3, 1),
            SIMD2<Float>(1, 1), SIMD2<Float>(1, 3), SIMD2<Float>(0, 3)
        ]
        for input in [outline, outline.reversed()] {
            let mesh = WatchMesh.extrude(input, depth: 0.2, bevel: 0.05)
            #expect(!mesh.positions.isEmpty)
            var top: Float = -Float.infinity
            var bottom = Float.infinity
            for p in mesh.positions {
                top = max(top, p.z)
                bottom = min(bottom, p.z)
            }
            #expect(abs(top) < 1e-6)
            #expect(abs(bottom + 0.2) < 1e-6)
            var tops = 0
            for t in 0..<mesh.triangleCount {
                let (a, b, c) = corners(mesh, t)
                if abs(a.z) < 1e-6 && abs(b.z) < 1e-6 && abs(c.z) < 1e-6 {
                    tops += 1
                    #expect(simd_cross(b - a, c - a).z > 0)
                }
            }
            // The chamfered top face of the L is its inset outline: 6 points, 4 triangles.
            #expect(tops == 4)
        }
    }

    @Test func extrudeRejectsBadInput() {
        #expect(WatchMesh.extrude([SIMD2<Float>(0, 0), SIMD2<Float>(1, 0)], depth: 1, bevel: 0).positions.isEmpty)
        let square: [SIMD2<Float>] = [
            SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1), SIMD2<Float>(0, 0)
        ]
        #expect(WatchMesh.extrude(square, depth: 0, bevel: 0).positions.isEmpty)
        // A closing point equal to the first is ignored: still a box (2 + 2 + 8 triangles).
        #expect(WatchMesh.extrude(square, depth: 1, bevel: 0).triangleCount == 12)
    }

    // MARK: Hands, balance, hairspring

    @Test func handsPointUpTheYAxisAndStayInTheirThickness() {
        let length: Float = 0.9, tail: Float = 0.2, height: Float = 0.02
        let styles: [WatchMesh.HandStyle] = [.baton, .breguet, .arrow, .seconds]
        for style in styles {
            let hand = WatchMesh.hand(style, length: length, width: 0.05, tail: tail, height: height)
            var top = -Float.infinity, bottom = Float.infinity
            var far = -Float.infinity, near = Float.infinity
            for p in hand.body.positions {
                top = max(top, p.z)
                bottom = min(bottom, p.z)
                far = max(far, p.y)
                near = min(near, p.y)
            }
            #expect(abs(far - length) < 1e-4, "\(style) tip")
            #expect(near >= -tail - 1e-4, "\(style) tail")
            #expect(top <= 1e-6 && bottom >= -height - 1e-6, "\(style) thickness")
            if style == .baton {
                #expect(!hand.lume.positions.isEmpty)
                #expect(hand.lume.positions.allSatisfy { $0.y > 0 && $0.y < length && $0.z <= 1e-6 })
            } else {
                #expect(hand.lume.positions.isEmpty)
            }
        }
    }

    @Test func handHasARidgeAboveItsEdges() {
        let hand = WatchMesh.hand(.arrow, length: 0.9, width: 0.05, tail: 0.2, height: 0.02)
        let ridge = hand.body.positions.filter { abs($0.x) < 1e-6 && $0.y > 0.1 && $0.y < 0.7 }
        #expect(!ridge.isEmpty)
        #expect(ridge.contains { abs($0.z) < 1e-6 })
        // On the shaft, the shoulders and edges are lower than the ridge (the underside is excluded).
        let edges = hand.body.positions.filter { $0.x > 0.004 && $0.y > 0.1 && $0.y < 0.7 && $0.z > -0.0199 }
        #expect(!edges.isEmpty)
        #expect(edges.allSatisfy { $0.z < 0 })
    }

    @Test func balanceFitsItsEnvelope() {
        let radius: Float = 0.21, thickness: Float = 0.04
        let mesh = WatchMesh.balance(radius: radius, thickness: thickness)
        var farthest: Float = 0
        var top = -Float.infinity, bottom = Float.infinity
        for p in mesh.positions {
            farthest = max(farthest, simd_length(SIMD2<Float>(p.x, p.y)))
            top = max(top, p.z)
            bottom = min(bottom, p.z)
        }
        #expect(abs(farthest - radius) < 1e-4)
        #expect(abs(top) < 1e-6)
        #expect(abs(bottom + thickness) < 1e-6)
        #expect(WatchMesh.balance(radius: 0, thickness: 0.04).positions.isEmpty)
    }

    @Test func hairspringSpiralsBetweenItsRadii() {
        let inner: Float = 0.02, outer: Float = 0.12, width: Float = 0.004
        let mesh = WatchMesh.hairspring(inner: inner, outer: outer, turns: 8, width: width, height: 0.01)
        var nearest = Float.infinity, farthest: Float = 0
        for p in mesh.positions {
            let r = simd_length(SIMD2<Float>(p.x, p.y))
            nearest = min(nearest, r)
            farthest = max(farthest, r)
            #expect(p.z <= 1e-6 && p.z >= -0.01 - 1e-6)
        }
        #expect(nearest >= inner - width)
        #expect(farthest <= outer + width)
        #expect(farthest > outer - width)
        #expect(WatchMesh.hairspring(inner: 0.1, outer: 0.05, turns: 4, width: 0.004, height: 0.01).positions.isEmpty)
    }

    // MARK: Transform and merge

    @Test func rotationTurnsNormalsAndKeepsThemUnit() {
        let mesh = WatchMesh.ring(inner: 0.2, outer: 1, segments: 12)
        var rotation = matrix_identity_float4x4
        rotation.columns.1 = SIMD4<Float>(0, 0, 1, 0)   // y -> z
        rotation.columns.2 = SIMD4<Float>(0, -1, 0, 0)  // z -> -y
        let turned = mesh.transformed(by: rotation)
        for n in turned.normals {
            #expect(abs(simd_length(n) - 1) < 1e-5)
            #expect(simd_length(n - SIMD3<Float>(0, -1, 0)) < 1e-5)
        }
        #expect(turned.indices == mesh.indices)
        #expect(turned.uvs == mesh.uvs)
    }

    @Test func nonUniformScaleUsesTheInverseTranspose() {
        // A 45 degree facing normal on a surface stretched 4x along x tilts toward z, not away from it.
        let mesh = WatchMeshData(
            positions: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, -1), SIMD3<Float>(0, 1, 0)],
            normals: Array(repeating: SIMD3<Float>(1, 0, 1) / Float(2).squareRoot(), count: 3),
            uvs: Array(repeating: SIMD2<Float>(0, 0), count: 3),
            indices: [0, 1, 2]
        )
        let stretched = mesh.transformed(by: scaling(SIMD3<Float>(4, 1, 1)))
        let n = stretched.normals[0]
        #expect(abs(simd_length(n) - 1) < 1e-5)
        #expect(n.z > n.x)
        #expect(stretched.positions[1].x == 4)
    }

    @Test func mirroringKeepsFacesCounterClockwise() {
        let mesh = WatchMesh.ring(inner: 0.2, outer: 1, segments: 12)
        let mirrored = mesh.transformed(by: scaling(SIMD3<Float>(-1, 1, 1)))
        for t in 0..<mirrored.triangleCount {
            let (a, b, c) = corners(mirrored, t)
            #expect(simd_cross(b - a, c - a).z > 0)
        }
    }

    @Test func mergedPartsKeepTheirTrianglesAndOffsetIndices() {
        let a = WatchMesh.ring(inner: 0, outer: 1, segments: 8)
        let b = WatchMesh.ring(inner: 0.5, outer: 1, segments: 6)
        let both = WatchMeshData.merged([a, .empty, b])
        #expect(both.positions.count == a.positions.count + b.positions.count)
        #expect(both.normals.count == both.positions.count)
        #expect(both.uvs.count == both.positions.count)
        #expect(both.triangleCount == a.triangleCount + b.triangleCount)
        #expect(both.indices.suffix(b.indices.count).allSatisfy { Int($0) >= a.positions.count })
        #expect(WatchMeshData.merged([]) == .empty)
        #expect(WatchMeshData.empty.triangleCount == 0)
    }
}
