import Foundation
import simd

// Pure geometry for the 3D skeleton watch: toothed wheels, bridges, hands, the balance and its hairspring,
// and the lathe-turned parts (case, bezel, crystal, jewels, screws, crown). Nothing here knows about Metal,
// SwiftUI or CoreGraphics, so it is unit-tested in CI and also safe in an app extension.
//
// Mesh space: the dial opening has radius 1, x is right, y is UP, z is toward the viewer. Parts are built
// centred on the origin with their top face at z = 0 (bodies run down to z = -thickness); the renderer
// places them. Front faces are counter-clockwise seen from outside. Every builder emits unit normals and
// planar UVs taken from the final x, y (see `WatchMesh.uvExtent`).

// MARK: - Mesh data

/// Interleaved-ready arrays for one mesh: one normal and one UV per position, a CCW triangle list.
public struct WatchMeshData: Sendable, Equatable {
    public var positions: [SIMD3<Float>]
    public var normals: [SIMD3<Float>]
    public var uvs: [SIMD2<Float>]
    public var indices: [UInt32]

    public init(positions: [SIMD3<Float>], normals: [SIMD3<Float>], uvs: [SIMD2<Float>], indices: [UInt32]) {
        self.positions = positions
        self.normals = normals
        self.uvs = uvs
        self.indices = indices
    }

    public static let empty = WatchMeshData(positions: [], normals: [], uvs: [], indices: [])

    public var triangleCount: Int { indices.count / 3 }

    /// Positions by `matrix`, normals by its inverse transpose (so non-uniform scale stays correct),
    /// renormalised. A mirroring matrix flips the triangle winding so faces stay counter-clockwise.
    /// UVs are left alone: they are defined on the untransformed mesh.
    public func transformed(by matrix: simd_float4x4) -> WatchMeshData {
        let c0 = matrix.columns.0
        let c1 = matrix.columns.1
        let c2 = matrix.columns.2
        let upper = simd_float3x3(columns: (
            SIMD3<Float>(c0.x, c0.y, c0.z),
            SIMD3<Float>(c1.x, c1.y, c1.z),
            SIMD3<Float>(c2.x, c2.y, c2.z)
        ))
        let determinant = simd_determinant(upper)
        let normalMatrix: simd_float3x3 = abs(determinant) > 1e-12 ? simd_transpose(simd_inverse(upper)) : upper

        var newPositions: [SIMD3<Float>] = []
        newPositions.reserveCapacity(positions.count)
        for p in positions {
            let moved = matrix * SIMD4<Float>(p.x, p.y, p.z, 1)
            newPositions.append(SIMD3<Float>(moved.x, moved.y, moved.z))
        }
        var newNormals: [SIMD3<Float>] = []
        newNormals.reserveCapacity(normals.count)
        for n in normals {
            newNormals.append(unitVector(normalMatrix * n))
        }
        var newIndices = indices
        if determinant < 0 {
            var i = 0
            while i + 2 < newIndices.count {
                newIndices.swapAt(i + 1, i + 2)
                i += 3
            }
        }
        return WatchMeshData(positions: newPositions, normals: newNormals, uvs: uvs, indices: newIndices)
    }

    /// One mesh from many, with the indices of each part offset past the vertices before it.
    public static func merged(_ parts: [WatchMeshData]) -> WatchMeshData {
        var result = WatchMeshData.empty
        for part in parts where !part.positions.isEmpty {
            let offset = UInt32(result.positions.count)
            result.positions.append(contentsOf: part.positions)
            result.normals.append(contentsOf: part.normals)
            result.uvs.append(contentsOf: part.uvs)
            result.indices.append(contentsOf: part.indices.map { $0 + offset })
        }
        return result
    }
}

// MARK: - Builders

public enum WatchMesh {
    /// Planar UV used by every builder unless stated: u = x / (2 * extent) + 0.5, v = 0.5 - y / (2 * extent),
    /// computed from the FINAL mesh-space x, y before any `transformed`. The default extent is the bezel's
    /// outer edge.
    public static let uvExtent: Float = 1.25

    // MARK: Wheel

    /// The spoke count the painter and the renderer agree on for a wheel. This mirrors the 2D painter
    /// (`WatchShapes.spokeHoles`): six on the biggest, five on large, four on medium, and a solid web with a
    /// recessed centre below 13 teeth. The mainspring barrel is a drum, so it is solid too.
    public static func spokeCount(for wheel: WatchWheel) -> Int {
        if wheel.role == .barrel { return 0 }
        if wheel.teeth >= 24 { return 6 }
        if wheel.teeth >= 18 { return 5 }
        if wheel.teeth >= 13 { return 4 }
        return 0
    }

    /// A toothed wheel centred on the origin, unrotated (tooth 0 centred on +x), top face at z = 0, bottom at
    /// z = -thickness. Teeth have rounded tips, straight flanks and root fillets. The body is a rim, `spokes`
    /// gently curved spokes and a hub with an arbor hole of radius `arbor`; `spokes == 0` (or a wheel too small
    /// for spokes) gives a solid web with a recessed centre. `bevel` chamfers every top edge so light catches it.
    public static func wheel(
        _ wheel: WatchWheel, thickness: Float, spokes: Int, arbor: Float, bevel: Float
    ) -> WatchMeshData {
        let teeth = max(3, wheel.teeth)
        let root = Float(wheel.rootRadius)
        let tip = Float(wheel.tipRadius)
        guard root > 0, tip > root, thickness > 0 else { return .empty }

        let depth = thickness
        let chamfer = max(0, min(bevel, depth * 0.4, (tip - root) * 0.3))
        let hole = max(0.002, min(arbor, root * 0.25))
        let circleCount = max(24, min(72, Int(root * 420)))

        let outline = toothOutline(teeth: teeth, root: root, tip: tip)
        let topOutline = chamfer > 0 ? insetLoop(outline, distance: chamfer) : outline
        var builder = MeshBuilder()

        // Outer wall (smooth round the tooth curves, hard at the corners) and the top chamfer.
        let outlineNormals = edgeNormals2D(outline, outwardIsRight: true, smoothCos: 0.8)
        let wallTop: Float = chamfer > 0 ? -chamfer : 0
        builder.band(
            lower: lift3(outline, z: -depth), upper: lift3(outline, z: wallTop),
            normals: liftNormals(outlineNormals, z: 0)
        )
        if chamfer > 0 {
            builder.band(
                lower: lift3(outline, z: -chamfer), upper: lift3(topOutline, z: 0),
                normals: liftNormals(outlineNormals, z: 1)
            )
        }

        let layout = spokes > 0
            ? SpokeLayout(count: spokes, root: root, tip: tip, arbor: hole, bevel: chamfer)
            : nil

        if let layout {
            // Top and bottom faces, with the windows between the spokes left open.
            addSpokedFace(
                &builder, layout: layout, outerLoop: topOutline, arbor: hole, offset: chamfer,
                z: 0, normalZ: 1, circleCount: circleCount
            )
            addSpokedFace(
                &builder, layout: layout, outerLoop: outline, arbor: hole, offset: 0,
                z: -depth, normalZ: -1, circleCount: circleCount
            )
            // The polished inside of every window: chamfer, then the wall down to the bottom.
            for j in 0..<layout.count {
                let wall = layout.windowLoop(j, offset: 0)
                let top = layout.windowLoop(j, offset: chamfer)
                let normals = edgeNormals2D(wall, outwardIsRight: signedArea(wall) < 0, smoothCos: 0.8)
                builder.band(
                    lower: lift3(wall, z: -depth), upper: lift3(wall, z: wallTop),
                    normals: liftNormals(normals, z: 0)
                )
                if chamfer > 0 {
                    builder.band(
                        lower: lift3(wall, z: -chamfer), upper: lift3(top, z: 0),
                        normals: liftNormals(normals, z: 1)
                    )
                }
            }
            addArborWall(&builder, radius: hole, chamfer: chamfer, depth: depth, segments: circleCount)
        } else {
            addSolidWeb(
                &builder, root: root, topOutline: topOutline, outline: outline, hole: hole,
                chamfer: chamfer, depth: depth, circleCount: circleCount
            )
        }
        return builder.build()
    }

    // MARK: Lathe, ring

    /// Revolves a profile about the z axis. `profile` points are (radius, z), listed from the outer bottom
    /// round to the inner/top so normals face outward (the normal of a segment is (dz, -dr)). A radius 0 point
    /// closes the centre. `creases` lists profile indices where normals are split (hard edges); every other
    /// interior point is smooth. A profile that returns to its first point makes a closed solid.
    public static func lathe(_ profile: [SIMD2<Float>], segments: Int, creases: Set<Int> = []) -> WatchMeshData {
        let count = profile.count
        guard count >= 2 else { return .empty }
        let segs = max(3, segments)

        var segmentNormals: [SIMD2<Float>] = []
        for i in 0..<(count - 1) {
            let d = profile[i + 1] - profile[i]
            let length = simd_length(d)
            segmentNormals.append(length > 1e-9 ? SIMD2<Float>(d.y / length, -d.x / length) : SIMD2<Float>(0, 0))
        }

        // The normal each profile point gives to the segment before it and the segment after it.
        var before: [SIMD2<Float>] = []
        var after: [SIMD2<Float>] = []
        for i in 0..<count {
            var inNormal: SIMD2<Float>
            var outNormal: SIMD2<Float>
            if i == 0 {
                inNormal = segmentNormals[0]
                outNormal = inNormal
            } else if i == count - 1 {
                inNormal = segmentNormals[count - 2]
                outNormal = inNormal
            } else if creases.contains(i) {
                inNormal = segmentNormals[i - 1]
                outNormal = segmentNormals[i]
            } else {
                let sum = segmentNormals[i - 1] + segmentNormals[i]
                let length = simd_length(sum)
                inNormal = length > 1e-6 ? sum / length : segmentNormals[i]
                outNormal = inNormal
            }
            // On the axis the normal can only point along z.
            if profile[i].x < 1e-6 {
                inNormal = SIMD2<Float>(0, inNormal.y >= 0 ? 1 : -1)
                outNormal = SIMD2<Float>(0, outNormal.y >= 0 ? 1 : -1)
            }
            before.append(inNormal)
            after.append(outNormal)
        }

        var builder = MeshBuilder()
        var inRings: [[UInt32]] = []
        var outRings: [[UInt32]] = []
        for i in 0..<count {
            let inRing = latheRing(&builder, profile[i], before[i], segs)
            inRings.append(inRing)
            outRings.append(before[i] == after[i] ? inRing : latheRing(&builder, profile[i], after[i], segs))
        }
        for i in 0..<(count - 1) {
            let a = outRings[i]
            let b = inRings[i + 1]
            for j in 0..<segs {
                // Triangles on the axis collapse to zero area and are dropped by the builder.
                builder.triangle(a[j], a[j + 1], b[j + 1])
                builder.triangle(a[j], b[j + 1], b[j])
            }
        }
        return builder.build()
    }

    /// A flat annulus (or disc if `inner` is 0) facing +z at z = 0, planar UVs.
    public static func ring(inner: Float, outer: Float, segments: Int) -> WatchMeshData {
        let segs = max(3, segments)
        guard outer > 0, outer > inner else { return .empty }
        let up = SIMD3<Float>(0, 0, 1)
        var builder = MeshBuilder()
        var outerRing: [UInt32] = []
        for j in 0..<segs {
            let p = polar(outer, twoPi * Float(j) / Float(segs))
            outerRing.append(builder.vertex(SIMD3<Float>(p.x, p.y, 0), up))
        }
        if inner < 1e-6 {
            let centre = builder.vertex(SIMD3<Float>(0, 0, 0), up)
            for j in 0..<segs {
                builder.triangle(centre, outerRing[j], outerRing[(j + 1) % segs])
            }
        } else {
            var innerRing: [UInt32] = []
            for j in 0..<segs {
                let p = polar(inner, twoPi * Float(j) / Float(segs))
                innerRing.append(builder.vertex(SIMD3<Float>(p.x, p.y, 0), up))
            }
            for j in 0..<segs {
                let k = (j + 1) % segs
                builder.triangle(outerRing[j], outerRing[k], innerRing[k])
                builder.triangle(outerRing[j], innerRing[k], innerRing[j])
            }
        }
        return builder.build()
    }

    // MARK: Triangulation and extrusion

    /// Ear-clipping triangulation: indices into `points`, counter-clockwise, `points.count - 2` triangles
    /// for any simple polygon (clockwise input is handled; degenerate input still terminates).
    public static func triangulate(_ points: [SIMD2<Float>]) -> [UInt32] {
        let n = points.count
        guard n >= 3 else { return [] }
        var order = Array(0..<n)
        if signedArea(points) < 0 { order.reverse() }

        var result: [UInt32] = []
        result.reserveCapacity((n - 2) * 3)
        while order.count > 3 {
            var ear = 0
            for pass in 0..<3 {
                if let found = findEar(order, points, pass: pass) {
                    ear = found
                    break
                }
            }
            let m = order.count
            result.append(UInt32(order[(ear + m - 1) % m]))
            result.append(UInt32(order[ear]))
            result.append(UInt32(order[(ear + 1) % m]))
            order.remove(at: ear)
        }
        result.append(UInt32(order[0]))
        result.append(UInt32(order[1]))
        result.append(UInt32(order[2]))
        return result
    }

    /// Extrudes a simple polygon (mesh-space points, y up, any winding, may be concave) from z = -depth to 0,
    /// with a 45 degree chamfer of size `bevel` on the top edge. The chamfer is inset along the vertex
    /// bisectors, never by more than 45% of an adjacent edge, so it cannot fold over on small features.
    /// Normals are smooth along gentle curves and split at corners. For bridges, the pallet fork, links.
    public static func extrude(_ outline: [SIMD2<Float>], depth: Float, bevel: Float) -> WatchMeshData {
        var points = cleanedLoop(outline)
        guard points.count >= 3, depth > 0 else { return .empty }
        if signedArea(points) < 0 { points.reverse() }

        let chamfer = max(0, min(bevel, depth * 0.5))
        let inset = chamfer > 0 ? insetLoop(points, distance: chamfer) : points
        let normals2D = edgeNormals2D(points, outwardIsRight: true, smoothCos: 0.8)
        var builder = MeshBuilder()

        let up = SIMD3<Float>(0, 0, 1)
        for tri in triangulate(inset).chunked(3) {
            let a = inset[Int(tri[0])], b = inset[Int(tri[1])], c = inset[Int(tri[2])]
            builder.triangleFace(
                SIMD3<Float>(a.x, a.y, 0), SIMD3<Float>(b.x, b.y, 0), SIMD3<Float>(c.x, c.y, 0), normal: up
            )
        }
        let down = SIMD3<Float>(0, 0, -1)
        for tri in triangulate(points).chunked(3) {
            let a = points[Int(tri[0])], b = points[Int(tri[1])], c = points[Int(tri[2])]
            builder.triangleFace(
                SIMD3<Float>(a.x, a.y, -depth), SIMD3<Float>(b.x, b.y, -depth), SIMD3<Float>(c.x, c.y, -depth),
                normal: down
            )
        }
        builder.band(
            lower: lift3(points, z: -depth), upper: lift3(points, z: chamfer > 0 ? -chamfer : 0),
            normals: liftNormals(normals2D, z: 0)
        )
        if chamfer > 0 {
            builder.band(
                lower: lift3(points, z: -chamfer), upper: lift3(inset, z: 0),
                normals: liftNormals(normals2D, z: 1)
            )
        }
        return builder.build()
    }

    // MARK: Hands

    public enum HandStyle: Sendable { case baton, breguet, arrow, seconds }

    /// A faceted watch hand pointing along +y from the origin, `length` to the tip, `tail` behind the
    /// pivot, at most `width` half-width, `height` thick, top at z = 0. A ridge runs down the middle so the
    /// two halves catch light differently. `.baton` is a sword with a V groove down the middle and the lume
    /// returned as a separate mesh sitting in it; `.breguet` is a needle with an open moon ring near the tip;
    /// `.arrow` is the day arrow (slim shaft, barbed head); `.seconds` is a needle with a counterweight disc.
    public static func hand(
        _ style: HandStyle, length: Float, width: Float, tail: Float, height: Float
    ) -> (body: WatchMeshData, lume: WatchMeshData) {
        let length = max(length, 1e-3)
        let width = max(width, 1e-4)
        let tail = max(tail, 0)
        let height = max(height, 1e-4)
        var builder = MeshBuilder()
        var extras: [WatchMeshData] = []
        var lume = WatchMeshData.empty

        switch style {
        case .baton:
            let stations = [
                HandStation(y: -tail, halfWidth: 0.55 * width),
                HandStation(y: 0, halfWidth: 0.95 * width),
                HandStation(y: 0.18 * length, halfWidth: width),
                HandStation(y: 0.22 * length, halfWidth: width, groove: true),
                HandStation(y: 0.80 * length, halfWidth: width, groove: true),
                HandStation(y: 0.84 * length, halfWidth: width),
                HandStation(y: length, halfWidth: 0)
            ]
            addHandSweep(&builder, stations: stations, height: height)
            let half = 0.28 * width
            let channel: [SIMD2<Float>] = [
                SIMD2<Float>(-half, 0.22 * length), SIMD2<Float>(half, 0.22 * length),
                SIMD2<Float>(half, 0.80 * length), SIMD2<Float>(-half, 0.80 * length)
            ]
            lume = extrude(channel, depth: 0.3 * height, bevel: 0.03 * height)
                .transformed(by: translation(SIMD3<Float>(0, 0, -0.14 * height)))
        case .breguet:
            let ringY = 0.72 * length
            let stations = [
                HandStation(y: -tail, halfWidth: 0.22 * width),
                HandStation(y: 0, halfWidth: 0.30 * width),
                HandStation(y: ringY, halfWidth: 0.22 * width),
                HandStation(y: length, halfWidth: 0)
            ]
            addHandSweep(&builder, stations: stations, height: height)
            let top = -0.12 * height
            let bottom = top - 0.55 * height
            let outer = width
            let inner = 0.58 * width
            let c = 0.12 * (outer - inner)
            let profile: [SIMD2<Float>] = [
                SIMD2<Float>(inner + c, bottom), SIMD2<Float>(outer - c, bottom),
                SIMD2<Float>(outer, bottom + c), SIMD2<Float>(outer, top - c),
                SIMD2<Float>(outer - c, top), SIMD2<Float>(inner + c, top),
                SIMD2<Float>(inner, top - c), SIMD2<Float>(inner, bottom + c),
                SIMD2<Float>(inner + c, bottom)
            ]
            extras.append(
                lathe(profile, segments: 48, creases: Set(1..<(profile.count - 1)))
                    .transformed(by: translation(SIMD3<Float>(0, ringY, 0)))
            )
        case .arrow:
            let stations = [
                HandStation(y: -tail, halfWidth: 0.2 * width),
                HandStation(y: 0.74 * length, halfWidth: 0.2 * width),
                HandStation(y: 0.80 * length, halfWidth: width),
                HandStation(y: length, halfWidth: 0)
            ]
            addHandSweep(&builder, stations: stations, height: height)
        case .seconds:
            let stations = [
                HandStation(y: -tail, halfWidth: 0.3 * width),
                HandStation(y: 0, halfWidth: 0.3 * width),
                HandStation(y: length, halfWidth: 0)
            ]
            addHandSweep(&builder, stations: stations, height: height)
            let top = -0.1 * height
            let bottom = -0.75 * height
            let radius = width
            let c = min(0.2 * radius, 0.3 * height)
            let profile: [SIMD2<Float>] = [
                SIMD2<Float>(0, bottom), SIMD2<Float>(radius - c, bottom),
                SIMD2<Float>(radius, bottom + c), SIMD2<Float>(radius, top - c),
                SIMD2<Float>(radius - c, top), SIMD2<Float>(0, top)
            ]
            extras.append(
                lathe(profile, segments: 36, creases: Set(1..<(profile.count - 1)))
                    .transformed(by: translation(SIMD3<Float>(0, -0.62 * tail, 0)))
            )
        }
        return (WatchMeshData.merged([builder.build()] + extras), lume)
    }

    // MARK: Balance and hairspring

    /// The balance wheel: a chamfered rim, three tapered arms, a hub and eight timing screws round the rim,
    /// centred, the screw heads and hub at z = 0, everything down to z = -thickness.
    public static func balance(radius: Float, thickness: Float) -> WatchMeshData {
        guard radius > 0, thickness > 0 else { return .empty }
        let outer = radius
        let rimWidth = 0.13 * radius
        let inner = outer - rimWidth
        let rimTop = -0.28 * thickness
        let rimBottom = -thickness
        let c = 0.2 * min(rimWidth, rimTop - rimBottom)

        let rimProfile: [SIMD2<Float>] = [
            SIMD2<Float>(inner + c, rimBottom), SIMD2<Float>(outer - c, rimBottom),
            SIMD2<Float>(outer, rimBottom + c), SIMD2<Float>(outer, rimTop - c),
            SIMD2<Float>(outer - c, rimTop), SIMD2<Float>(inner + c, rimTop),
            SIMD2<Float>(inner, rimTop - c), SIMD2<Float>(inner, rimBottom + c),
            SIMD2<Float>(inner + c, rimBottom)
        ]
        var parts: [WatchMeshData] = [
            lathe(rimProfile, segments: 64, creases: Set(1..<(rimProfile.count - 1)))
        ]

        // Three arms, tapering toward the rim, sunk a little below the rim top.
        let armOutline: [SIMD2<Float>] = [
            SIMD2<Float>(-0.075 * radius, 0.05 * radius), SIMD2<Float>(0.075 * radius, 0.05 * radius),
            SIMD2<Float>(0.045 * radius, inner + 0.01 * radius), SIMD2<Float>(-0.045 * radius, inner + 0.01 * radius)
        ]
        let arm = extrude(armOutline, depth: 0.36 * thickness, bevel: 0.04 * thickness)
        for k in 0..<3 {
            let angle = Float.pi / 2 + Float(k) * twoPi / 3
            parts.append(arm.transformed(by: translation(SIMD3<Float>(0, 0, -0.38 * thickness)) * rotationZ(angle)))
        }

        // The hub.
        let hubRadius = 0.17 * radius
        let hubChamfer = min(0.25 * hubRadius, 0.2 * thickness)
        let hubProfile: [SIMD2<Float>] = [
            SIMD2<Float>(0, -thickness), SIMD2<Float>(hubRadius - hubChamfer, -thickness),
            SIMD2<Float>(hubRadius, -thickness + hubChamfer), SIMD2<Float>(hubRadius, -hubChamfer),
            SIMD2<Float>(hubRadius - hubChamfer, 0), SIMD2<Float>(0, 0)
        ]
        parts.append(lathe(hubProfile, segments: 28, creases: Set(1..<(hubProfile.count - 1))))

        // Timing screws standing proud of the rim, spaced round it between the arms.
        let screwRadius = 0.05 * radius
        let screwChamfer = min(0.25 * screwRadius, 0.12 * thickness)
        let screwBottom = rimTop - 0.05 * thickness
        let screwProfile: [SIMD2<Float>] = [
            SIMD2<Float>(0, screwBottom), SIMD2<Float>(screwRadius, screwBottom),
            SIMD2<Float>(screwRadius, -screwChamfer), SIMD2<Float>(screwRadius - screwChamfer, 0),
            SIMD2<Float>(0, 0)
        ]
        let screw = lathe(screwProfile, segments: 12, creases: Set(1..<(screwProfile.count - 1)))
        let screwOrbit = (inner + outer) / 2
        for k in 0..<8 {
            let angle = Float.pi / 6 + Float(k) * twoPi / 8
            let spot = polar(screwOrbit, angle)
            parts.append(screw.transformed(by: translation(SIMD3<Float>(spot.x, spot.y, 0))))
        }
        return WatchMeshData.merged(parts)
    }

    /// The hairspring: a flat Archimedean spiral ribbon from radius `inner` to `outer`, `width` wide
    /// (radially) and `height` thick, centred, top at z = 0.
    public static func hairspring(inner: Float, outer: Float, turns: Float, width: Float, height: Float) -> WatchMeshData {
        guard turns > 0, outer > inner, inner >= 0, width > 0, height > 0 else { return .empty }
        let steps = max(24, min(720, Int((turns * 24).rounded(.up))))
        let total = twoPi * turns
        let growth = (outer - inner) / total

        var builder = MeshBuilder()
        var topIn: [UInt32] = [], topOut: [UInt32] = [], bottomIn: [UInt32] = [], bottomOut: [UInt32] = []
        var wallOutTop: [UInt32] = [], wallOutBottom: [UInt32] = [], wallInTop: [UInt32] = [], wallInBottom: [UInt32] = []
        var inside: [SIMD2<Float>] = [], outside: [SIMD2<Float>] = [], tangents: [SIMD2<Float>] = []
        let up = SIMD3<Float>(0, 0, 1)
        let down = SIMD3<Float>(0, 0, -1)

        for i in 0...steps {
            let angle = total * Float(i) / Float(steps)
            let radius = inner + growth * angle
            let c = cos(angle), s = sin(angle)
            let derivative = SIMD2<Float>(growth * c - radius * s, growth * s + radius * c)
            let length = simd_length(derivative)
            let tangent = length > 1e-9 ? derivative / length : SIMD2<Float>(0, 1)
            let normal = SIMD2<Float>(tangent.y, -tangent.x)
            let centre = SIMD2<Float>(radius * c, radius * s)
            let a = centre - normal * (width / 2)
            let b = centre + normal * (width / 2)
            inside.append(a)
            outside.append(b)
            tangents.append(tangent)

            topIn.append(builder.vertex(SIMD3<Float>(a.x, a.y, 0), up))
            topOut.append(builder.vertex(SIMD3<Float>(b.x, b.y, 0), up))
            bottomIn.append(builder.vertex(SIMD3<Float>(a.x, a.y, -height), down))
            bottomOut.append(builder.vertex(SIMD3<Float>(b.x, b.y, -height), down))
            let outward = SIMD3<Float>(normal.x, normal.y, 0)
            wallOutTop.append(builder.vertex(SIMD3<Float>(b.x, b.y, 0), outward))
            wallOutBottom.append(builder.vertex(SIMD3<Float>(b.x, b.y, -height), outward))
            wallInTop.append(builder.vertex(SIMD3<Float>(a.x, a.y, 0), -outward))
            wallInBottom.append(builder.vertex(SIMD3<Float>(a.x, a.y, -height), -outward))
        }
        for i in 0..<steps {
            let j = i + 1
            builder.triangle(topIn[i], topOut[i], topOut[j])
            builder.triangle(topIn[i], topOut[j], topIn[j])
            builder.triangle(bottomIn[i], bottomOut[i], bottomOut[j])
            builder.triangle(bottomIn[i], bottomOut[j], bottomIn[j])
            builder.triangle(wallOutBottom[i], wallOutBottom[j], wallOutTop[j])
            builder.triangle(wallOutBottom[i], wallOutTop[j], wallOutTop[i])
            builder.triangle(wallInBottom[i], wallInBottom[j], wallInTop[j])
            builder.triangle(wallInBottom[i], wallInTop[j], wallInTop[i])
        }
        // Square-cut ends.
        for end in [0, steps] {
            let a = inside[end], b = outside[end]
            let t = tangents[end]
            let hint = SIMD3<Float>(end == 0 ? -t.x : t.x, end == 0 ? -t.y : t.y, 0)
            builder.flat(
                SIMD3<Float>(a.x, a.y, 0), SIMD3<Float>(b.x, b.y, 0), SIMD3<Float>(b.x, b.y, -height), facing: hint
            )
            builder.flat(
                SIMD3<Float>(a.x, a.y, 0), SIMD3<Float>(b.x, b.y, -height), SIMD3<Float>(a.x, a.y, -height),
                facing: hint
            )
        }
        return builder.build()
    }
}

// MARK: - Shared helpers (file private)

private let twoPi: Float = 2 * Float.pi

private func unitVector(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let length = simd_length(v)
    return length > 1e-12 ? v / length : SIMD3<Float>(0, 0, 1)
}

private func polar(_ radius: Float, _ angle: Float) -> SIMD2<Float> {
    SIMD2<Float>(radius * cos(angle), radius * sin(angle))
}

private func cross2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    a.x * b.y - a.y * b.x
}

private func signedArea(_ points: [SIMD2<Float>]) -> Float {
    var sum: Double = 0
    let n = points.count
    for i in 0..<n {
        let p = points[i]
        let q = points[(i + 1) % n]
        sum += Double(p.x) * Double(q.y) - Double(q.x) * Double(p.y)
    }
    return Float(sum / 2)
}

private func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
    return m
}

private func rotationZ(_ angle: Float) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    let c = cos(angle), s = sin(angle)
    m.columns.0 = SIMD4<Float>(c, s, 0, 0)
    m.columns.1 = SIMD4<Float>(-s, c, 0, 0)
    return m
}

private func lift3(_ points: [SIMD2<Float>], z: Float) -> [SIMD3<Float>] {
    points.map { SIMD3<Float>($0.x, $0.y, z) }
}

private func circle(_ radius: Float, _ count: Int) -> [SIMD2<Float>] {
    (0..<count).map { polar(radius, twoPi * Float($0) / Float(count)) }
}

private extension Array {
    /// Consecutive groups of `size` elements (the last may be shorter).
    func chunked(_ size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}

/// Drops repeated points, including a closing point equal to the first.
private func cleanedLoop(_ points: [SIMD2<Float>]) -> [SIMD2<Float>] {
    var result: [SIMD2<Float>] = []
    for p in points {
        if let last = result.last, simd_distance(last, p) < 1e-7 { continue }
        result.append(p)
    }
    while result.count > 1, let first = result.first, let last = result.last, simd_distance(first, last) < 1e-7 {
        result.removeLast()
    }
    return result
}

/// A loop moved inward (to the left of a counter-clockwise loop) by `distance`, mitred at the vertices.
/// Each vertex moves no further than 45% of its shorter adjacent edge, so the result cannot fold over.
private func insetLoop(_ points: [SIMD2<Float>], distance: Float) -> [SIMD2<Float>] {
    let n = points.count
    var result = points
    for i in 0..<n {
        let previous = points[(i + n - 1) % n]
        let here = points[i]
        let next = points[(i + 1) % n]
        let d0 = here - previous
        let d1 = next - here
        let l0 = simd_length(d0)
        let l1 = simd_length(d1)
        guard l0 > 1e-9, l1 > 1e-9 else { continue }
        let t0 = d0 / l0
        let t1 = d1 / l1
        let n0 = SIMD2<Float>(-t0.y, t0.x)
        let n1 = SIMD2<Float>(-t1.y, t1.x)
        let sum = n0 + n1
        let sumLength = simd_length(sum)
        guard sumLength > 1e-6 else { continue }
        let bisector = sum / sumLength
        let cosHalf = max(simd_dot(bisector, n0), 0.35)
        let perpendicular = min(distance, 0.45 * min(l0, l1))
        result[i] = here + bisector * (perpendicular / cosHalf)
    }
    return result
}

private struct EdgeNormal2D {
    var start: SIMD2<Float>
    var end: SIMD2<Float>
}

/// Outward normals of each edge of a loop, shared between two edges (smooth) where the turn is gentler
/// than `smoothCos` and kept apart (hard) where it is sharper.
private func edgeNormals2D(_ points: [SIMD2<Float>], outwardIsRight: Bool, smoothCos: Float) -> [EdgeNormal2D] {
    let n = points.count
    var face: [SIMD2<Float>] = []
    for i in 0..<n {
        let d = points[(i + 1) % n] - points[i]
        let length = simd_length(d)
        if length < 1e-12 {
            face.append(SIMD2<Float>(0, 1))
        } else {
            let t = d / length
            face.append(outwardIsRight ? SIMD2<Float>(t.y, -t.x) : SIMD2<Float>(-t.y, t.x))
        }
    }
    var starts = face
    var ends = face
    for i in 0..<n {
        let previous = (i + n - 1) % n
        if simd_dot(face[previous], face[i]) >= smoothCos {
            let sum = face[previous] + face[i]
            let length = simd_length(sum)
            if length > 1e-9 {
                let shared = sum / length
                ends[previous] = shared
                starts[i] = shared
            }
        }
    }
    return (0..<n).map { EdgeNormal2D(start: starts[$0], end: ends[$0]) }
}

/// Edge normals lifted to 3D with a z component: 0 for a wall, 1 for a 45 degree chamfer.
private func liftNormals(_ normals: [EdgeNormal2D], z: Float) -> [EdgeNormal] {
    normals.map {
        EdgeNormal(
            start: unitVector(SIMD3<Float>($0.start.x, $0.start.y, z)),
            end: unitVector(SIMD3<Float>($0.end.x, $0.end.y, z))
        )
    }
}

private struct EdgeNormal {
    var start: SIMD3<Float>
    var end: SIMD3<Float>
}

private func planarUV(_ p: SIMD3<Float>) -> SIMD2<Float> {
    let extent = WatchMesh.uvExtent
    return SIMD2<Float>(p.x / (2 * extent) + 0.5, 0.5 - p.y / (2 * extent))
}

/// Collects vertices and triangles. Every triangle is oriented to agree with its vertex normals, so a
/// builder only has to get the normals right, and zero-area triangles are dropped.
private struct MeshBuilder {
    var positions: [SIMD3<Float>] = []
    var normals: [SIMD3<Float>] = []
    var uvs: [SIMD2<Float>] = []
    var indices: [UInt32] = []

    mutating func vertex(_ p: SIMD3<Float>, _ n: SIMD3<Float>) -> UInt32 {
        let index = UInt32(positions.count)
        positions.append(p)
        normals.append(unitVector(n))
        uvs.append(planarUV(p))
        return index
    }

    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
        let pa = positions[Int(a)]
        let pb = positions[Int(b)]
        let pc = positions[Int(c)]
        let geometric = simd_cross(pb - pa, pc - pa)
        guard simd_length_squared(geometric) > 1e-16 else { return }
        let shading = normals[Int(a)] + normals[Int(b)] + normals[Int(c)]
        if simd_dot(geometric, shading) < 0 {
            indices.append(contentsOf: [a, c, b])
        } else {
            indices.append(contentsOf: [a, b, c])
        }
    }

    /// A flat triangle with one shared normal.
    mutating func triangleFace(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, normal: SIMD3<Float>) {
        let i0 = vertex(a, normal)
        let i1 = vertex(b, normal)
        let i2 = vertex(c, normal)
        triangle(i0, i1, i2)
    }

    /// A flat-shaded triangle whose normal comes from its own corners, turned to face `hint`.
    mutating func flat(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, facing hint: SIMD3<Float>) {
        var normal = simd_cross(b - a, c - a)
        guard simd_length_squared(normal) > 1e-16 else { return }
        var second = b
        var third = c
        if simd_dot(normal, hint) < 0 {
            second = c
            third = b
            normal = -normal
        }
        triangleFace(a, second, third, normal: normal)
    }

    /// A band between two closed rows of points, one quad per edge (four vertices each, so normals can
    /// differ from edge to edge). `lower` is the row nearer the bottom or the outside.
    mutating func band(lower: [SIMD3<Float>], upper: [SIMD3<Float>], normals edgeNormals: [EdgeNormal]) {
        let n = lower.count
        guard n >= 3, upper.count == n, edgeNormals.count == n else { return }
        for k in 0..<n {
            let j = (k + 1) % n
            let l0 = vertex(lower[k], edgeNormals[k].start)
            let l1 = vertex(lower[j], edgeNormals[k].end)
            let u0 = vertex(upper[k], edgeNormals[k].start)
            let u1 = vertex(upper[j], edgeNormals[k].end)
            triangle(l0, l1, u1)
            triangle(l0, u1, u0)
        }
    }

    func build() -> WatchMeshData {
        WatchMeshData(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }
}

// MARK: - Ear clipping

private func findEar(_ order: [Int], _ points: [SIMD2<Float>], pass: Int) -> Int? {
    let m = order.count
    for i in 0..<m {
        let ia = order[(i + m - 1) % m]
        let ib = order[i]
        let ic = order[(i + 1) % m]
        let a = points[ia]
        let b = points[ib]
        let c = points[ic]
        let turn = cross2(b - a, c - b)
        // Pass 0: strictly convex corners. Pass 1: also straight ones. Pass 2: anything (always ends).
        if pass == 0 && turn <= 1e-12 { continue }
        if pass == 1 && turn < -1e-12 { continue }
        if pass < 2 {
            var blocked = false
            for k in order where k != ia && k != ib && k != ic {
                let p = points[k]
                if p == a || p == b || p == c { continue }
                if cross2(b - a, p - a) >= -1e-12 && cross2(c - b, p - b) >= -1e-12
                    && cross2(a - c, p - c) >= -1e-12 {
                    blocked = true
                    break
                }
            }
            if blocked { continue }
        }
        return i
    }
    return nil
}

// MARK: - Lathe

private func latheRing(_ builder: inout MeshBuilder, _ p: SIMD2<Float>, _ n: SIMD2<Float>, _ segments: Int) -> [UInt32] {
    var ring: [UInt32] = []
    ring.reserveCapacity(segments + 1)
    for j in 0...segments {
        let angle = twoPi * Float(j % segments) / Float(segments)
        let c = cos(angle), s = sin(angle)
        ring.append(builder.vertex(
            SIMD3<Float>(p.x * c, p.x * s, p.y),
            SIMD3<Float>(n.x * c, n.x * s, n.y)
        ))
    }
    return ring
}

// MARK: - Wheel

/// Tooth centre to gap centre: (angle as a fraction of the tooth pitch, radius as a fraction of tooth
/// height above the root). Tip arc, rounded corner, straight flank, root fillet.
private let toothHalfProfile: [SIMD2<Float>] = [
    SIMD2<Float>(0.06, 1.0), SIMD2<Float>(0.09, 0.94), SIMD2<Float>(0.125, 0.80),
    SIMD2<Float>(0.29, 0.12), SIMD2<Float>(0.35, 0.025), SIMD2<Float>(0.41, 0.0)
]

/// The toothed outline, counter-clockwise, in increasing angle, tooth 0 centred on +x: 14 points a tooth.
private func toothOutline(teeth: Int, root: Float, tip: Float) -> [SIMD2<Float>] {
    let pitch = twoPi / Float(teeth)
    let height = tip - root
    func radius(_ fraction: Float) -> Float { fraction >= 1 ? tip : root + height * fraction }
    var points: [SIMD2<Float>] = []
    points.reserveCapacity(teeth * 14)
    for k in 0..<teeth {
        let centre = Float(k) * pitch
        for p in toothHalfProfile.reversed() {
            points.append(polar(radius(p.y), centre - p.x * pitch))
        }
        points.append(polar(tip, centre))
        for p in toothHalfProfile {
            points.append(polar(radius(p.y), centre + p.x * pitch))
        }
        points.append(polar(root, centre + 0.5 * pitch))
    }
    return points
}

/// A loop's points and their angles in 0..<2pi, rotated to start at the smallest angle. The loop must go
/// round the origin once, counter-clockwise.
private func angularOrder(_ points: [SIMD2<Float>]) -> (points: [SIMD2<Float>], angles: [Float]) {
    let n = points.count
    var angles: [Float] = []
    angles.reserveCapacity(n)
    for p in points {
        var a = atan2(p.y, p.x)
        if a < 0 { a += twoPi }
        angles.append(a)
    }
    var start = 0
    for i in 0..<n where angles[i] < angles[start] { start = i }
    var rotatedPoints: [SIMD2<Float>] = []
    var rotatedAngles: [Float] = []
    for k in 0..<n {
        let i = (start + k) % n
        rotatedPoints.append(points[i])
        rotatedAngles.append(angles[i])
    }
    return (rotatedPoints, rotatedAngles)
}

/// Fills the ring between two loops that both go once round the origin (any vertex counts), as a strip
/// that advances whichever loop has the next smaller angle. Flat at `z`, facing `normalZ`.
private func zipper(
    _ builder: inout MeshBuilder, outer: [SIMD2<Float>], inner: [SIMD2<Float>], z: Float, normalZ: Float
) {
    guard outer.count >= 3, inner.count >= 3 else { return }
    let o = angularOrder(outer)
    let i = angularOrder(inner)
    let normal = SIMD3<Float>(0, 0, normalZ)
    var outerIndex: [UInt32] = []
    var innerIndex: [UInt32] = []
    for p in o.points { outerIndex.append(builder.vertex(SIMD3<Float>(p.x, p.y, z), normal)) }
    for p in i.points { innerIndex.append(builder.vertex(SIMD3<Float>(p.x, p.y, z), normal)) }

    let na = o.points.count
    let nb = i.points.count
    var ia = 0
    var ib = 0
    var doneA = 0
    var doneB = 0
    while doneA < na || doneB < nb {
        let nextA: Float = doneA < na ? (ia + 1 < na ? o.angles[ia + 1] : o.angles[0] + twoPi) : Float.infinity
        let nextB: Float = doneB < nb ? (ib + 1 < nb ? i.angles[ib + 1] : i.angles[0] + twoPi) : Float.infinity
        if doneA < na && (doneB >= nb || nextA <= nextB) {
            let next = (ia + 1) % na
            builder.triangle(outerIndex[ia], outerIndex[next], innerIndex[ib])
            ia = next
            doneA += 1
        } else {
            let next = (ib + 1) % nb
            builder.triangle(outerIndex[ia], innerIndex[next], innerIndex[ib])
            ib = next
            doneB += 1
        }
    }
}

/// A smooth ring wall about the axis, either facing the axis (a hole) or away from it. `tilt` is the z
/// component of the normal: 0 for a wall, 1 for a 45 degree chamfer.
private func radialBand(
    _ builder: inout MeshBuilder, upper: SIMD2<Float>, lower: SIMD2<Float>, segments: Int, inward: Bool, tilt: Float
) {
    let sign: Float = inward ? -1 : 1
    for j in 0..<segments {
        let a0 = twoPi * Float(j) / Float(segments)
        let a1 = twoPi * Float(j + 1) / Float(segments)
        let c0 = cos(a0), s0 = sin(a0), c1 = cos(a1), s1 = sin(a1)
        let n0 = SIMD3<Float>(sign * c0, sign * s0, tilt)
        let n1 = SIMD3<Float>(sign * c1, sign * s1, tilt)
        let l0 = builder.vertex(SIMD3<Float>(lower.x * c0, lower.x * s0, lower.y), n0)
        let l1 = builder.vertex(SIMD3<Float>(lower.x * c1, lower.x * s1, lower.y), n1)
        let u0 = builder.vertex(SIMD3<Float>(upper.x * c0, upper.x * s0, upper.y), n0)
        let u1 = builder.vertex(SIMD3<Float>(upper.x * c1, upper.x * s1, upper.y), n1)
        builder.triangle(l0, l1, u1)
        builder.triangle(l0, u1, u0)
    }
}

/// The arbor hole's chamfer and wall, facing the axis.
private func addArborWall(_ builder: inout MeshBuilder, radius: Float, chamfer: Float, depth: Float, segments: Int) {
    if chamfer > 0 {
        radialBand(
            &builder, upper: SIMD2<Float>(radius + chamfer, 0), lower: SIMD2<Float>(radius, -chamfer),
            segments: segments, inward: true, tilt: 1
        )
    }
    radialBand(
        &builder, upper: SIMD2<Float>(radius, chamfer > 0 ? -chamfer : 0), lower: SIMD2<Float>(radius, -depth),
        segments: segments, inward: true, tilt: 0
    )
}

/// The solid-web wheel: top rim, then a recessed web round a raised hub (revolved), and a flat underside.
/// Wheels too small for a recess get a flat top.
private func addSolidWeb(
    _ builder: inout MeshBuilder, root: Float, topOutline: [SIMD2<Float>], outline: [SIMD2<Float>], hole: Float,
    chamfer: Float, depth: Float, circleCount: Int
) {
    let rim = 0.78 * root
    let hub = hole + 0.42 * (rim - hole)
    let recessed = (hub - hole) > 2.5 * chamfer + 0.004 && (rim - hub) > 2.5 * chamfer + 0.004

    // Underside: flat, out to the toothed edge.
    zipper(&builder, outer: outline, inner: circle(hole, circleCount), z: -depth, normalZ: -1)

    if recessed {
        zipper(&builder, outer: topOutline, inner: circle(rim + chamfer, circleCount), z: 0, normalZ: 1)
        let web = -max(0.45 * depth, 2 * chamfer)
        var profile: [SIMD2<Float>] = [SIMD2<Float>(rim + chamfer, 0)]
        if chamfer > 0 { profile.append(SIMD2<Float>(rim, -chamfer)) }
        profile.append(SIMD2<Float>(rim, web))
        profile.append(SIMD2<Float>(hub, web))
        if chamfer > 0 {
            profile.append(SIMD2<Float>(hub, -chamfer))
            profile.append(SIMD2<Float>(hub - chamfer, 0))
            profile.append(SIMD2<Float>(hole + chamfer, 0))
            profile.append(SIMD2<Float>(hole, -chamfer))
        } else {
            profile.append(SIMD2<Float>(hub, 0))
            profile.append(SIMD2<Float>(hole, 0))
        }
        profile.append(SIMD2<Float>(hole, -depth))
        let revolved = WatchMesh.lathe(profile, segments: circleCount, creases: Set(1..<(profile.count - 1)))
        builder.append(revolved)
    } else {
        zipper(&builder, outer: topOutline, inner: circle(hole + chamfer, circleCount), z: 0, normalZ: 1)
        addArborWall(&builder, radius: hole, chamfer: chamfer, depth: depth, segments: circleCount)
    }
}

/// Curved spokes between a rim and a hub, laid out in polar coordinates so every end sits exactly on its
/// circle. "Wall" loops (offset 0) are the real edges; the top face is the same shape pulled back by the
/// chamfer (offset = bevel) so the chamfers meet it exactly.
private struct SpokeLayout {
    let count: Int
    /// Inner radius of the rim: where the windows end.
    let rim: Float
    /// Outer radius of the hub: where the windows start.
    let hub: Float
    let halfWidth: Float
    let sweep: Float = 0.32
    let base: Float = Float.pi / 2
    let samples = 10
    let arcSegments: Int

    /// nil when the wheel is too small to carry spokes of this size with its chamfer.
    init?(count: Int, root: Float, tip: Float, arbor: Float, bevel: Float) {
        guard count >= 3 else { return nil }
        let rim = 0.80 * root
        let hub = max(0.27 * tip, arbor * 1.7 + 2 * bevel)
        let halfWidth = 0.085 * root
        guard rim - hub > 6 * bevel + 0.02 * root,
              root - rim > 2.5 * bevel,
              halfWidth > 2.2 * bevel,
              hub - bevel > arbor + bevel + 0.001 else { return nil }
        let slot = twoPi / Float(count)
        let hubHalf = asin(min(halfWidth / hub, 0.999))
        let rimHalf = asin(min(halfWidth / rim, 0.999))
        guard 2 * hubHalf < 0.7 * slot else { return nil }
        self.count = count
        self.rim = rim
        self.hub = hub
        self.halfWidth = halfWidth
        let extent = slot - 2 * rimHalf
        self.arcSegments = max(3, min(14, Int((extent / 0.14).rounded(.up))))
    }

    /// Spoke `j`'s centreline angle at radius `r`.
    func centre(_ j: Int, _ r: Float) -> Float {
        base + Float(j) * twoPi / Float(count) + sweep * (r - hub) / (rim - hub)
    }

    /// Half the spoke's angular width at radius `r`, its sides pulled in by `inset`.
    func half(_ r: Float, _ inset: Float) -> Float {
        asin(min(max(halfWidth - inset, 0.0005) / r, 0.999))
    }

    /// Radii along a spoke edge, from just inside the hub radius to just outside the rim radius when offset.
    func radii(_ offset: Float) -> [Float] {
        let low = hub - offset
        let high = rim + offset
        return (0...samples).map { low + (high - low) * Float($0) / Float(samples) }
    }

    /// One side of spoke `j` (`side` +1 is the counter-clockwise side), hub to rim.
    func edge(_ j: Int, side: Float, offset: Float) -> [SIMD2<Float>] {
        radii(offset).map { r in polar(r, centre(j, r) + side * half(r, offset)) }
    }

    /// The rim's inner circle between spoke `j` and the next, counter-clockwise.
    func rimArc(_ j: Int, offset: Float) -> [SIMD2<Float>] {
        let r = rim + offset
        let a0 = centre(j, r) + half(r, offset)
        let a1 = centre(j + 1, r) - half(r, offset)
        return (0...arcSegments).map { polar(r, a0 + (a1 - a0) * Float($0) / Float(arcSegments)) }
    }

    /// The hub's outer circle between spoke `j` and the next, running clockwise (from the next spoke back).
    func hubArc(_ j: Int, offset: Float) -> [SIMD2<Float>] {
        let r = hub - offset
        let a0 = centre(j + 1, r) - half(r, offset)
        let a1 = centre(j, r) + half(r, offset)
        return (0...arcSegments).map { polar(r, a0 + (a1 - a0) * Float($0) / Float(arcSegments)) }
    }

    /// The window between spoke `j` and the next as one closed loop (counter-clockwise round the hole).
    func windowLoop(_ j: Int, offset: Float) -> [SIMD2<Float>] {
        var loop = edge(j, side: 1, offset: offset)
        loop.append(contentsOf: rimArc(j, offset: offset).dropFirst().dropLast())
        loop.append(contentsOf: edge(j + 1, side: -1, offset: offset).reversed())
        loop.append(contentsOf: hubArc(j, offset: offset).dropFirst().dropLast())
        return loop
    }
}

/// One flat face (top or bottom) of a spoked wheel: rim, hub and spokes, windows left open.
private func addSpokedFace(
    _ builder: inout MeshBuilder, layout: SpokeLayout, outerLoop: [SIMD2<Float>], arbor: Float, offset: Float,
    z: Float, normalZ: Float, circleCount: Int
) {
    var rimLoop: [SIMD2<Float>] = []
    var hubLoop: [SIMD2<Float>] = []
    for j in 0..<layout.count {
        rimLoop.append(contentsOf: layout.rimArc(j, offset: offset))
        hubLoop.append(contentsOf: layout.hubArc(j, offset: offset).reversed())
    }
    zipper(&builder, outer: outerLoop, inner: rimLoop, z: z, normalZ: normalZ)
    zipper(&builder, outer: hubLoop, inner: circle(arbor + offset, circleCount), z: z, normalZ: normalZ)

    let normal = SIMD3<Float>(0, 0, normalZ)
    for j in 0..<layout.count {
        let clockwise = layout.edge(j, side: -1, offset: offset)
        let counter = layout.edge(j, side: 1, offset: offset)
        for k in 0..<layout.samples {
            let a = clockwise[k], b = counter[k], c = counter[k + 1], d = clockwise[k + 1]
            builder.triangleFace(
                SIMD3<Float>(a.x, a.y, z), SIMD3<Float>(b.x, b.y, z), SIMD3<Float>(c.x, c.y, z), normal: normal
            )
            builder.triangleFace(
                SIMD3<Float>(a.x, a.y, z), SIMD3<Float>(c.x, c.y, z), SIMD3<Float>(d.x, d.y, z), normal: normal
            )
        }
    }
}

extension MeshBuilder {
    /// Appends a finished mesh.
    fileprivate mutating func append(_ mesh: WatchMeshData) {
        let offset = UInt32(positions.count)
        positions.append(contentsOf: mesh.positions)
        normals.append(contentsOf: mesh.normals)
        uvs.append(contentsOf: mesh.uvs)
        indices.append(contentsOf: mesh.indices.map { $0 + offset })
    }
}

// MARK: - Hands

private struct HandStation {
    var y: Float
    var halfWidth: Float
    var groove = false
}

/// Sweeps a faceted five-point cross-section along the stations (increasing y): left edge, left shoulder,
/// ridge, right shoulder, right edge, with flat-shaded facets, vertical sides, a flat underside and end caps.
/// Stations must go from the tail to the tip; a station of zero width closes the tip to a point.
private func addHandSweep(_ builder: inout MeshBuilder, stations rawStations: [HandStation], height: Float) {
    var stations: [HandStation] = []
    for s in rawStations {
        if let last = stations.last, s.y <= last.y + 1e-6 { continue }
        stations.append(s)
    }
    guard stations.count >= 2 else { return }

    let fractions: [Float] = [-1, -0.5, 0, 0.5, 1]
    let edgeZ = -0.5 * height
    let groove: [Float] = [edgeZ, -0.05 * height, -0.45 * height, -0.05 * height, edgeZ]
    func section(_ s: HandStation) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for (i, f) in fractions.enumerated() {
            let z: Float
            if s.halfWidth < 1e-6 {
                z = 0
            } else if s.groove {
                z = groove[i]
            } else {
                z = edgeZ * abs(f)
            }
            points.append(SIMD3<Float>(f * s.halfWidth, s.y, z))
        }
        return points
    }
    let sections = stations.map(section)
    let m = stations.count
    let up = SIMD3<Float>(0, 0, 1)

    for k in 0..<(m - 1) {
        let a = sections[k]
        let c = sections[k + 1]
        for i in 0..<4 {
            builder.flat(a[i], a[i + 1], c[i + 1], facing: up)
            builder.flat(a[i], c[i + 1], c[i], facing: up)
        }
        for (column, hint) in [(0, SIMD3<Float>(-1, 0, 0)), (4, SIMD3<Float>(1, 0, 0))] {
            let topA = a[column], topC = c[column]
            let bottomA = SIMD3<Float>(topA.x, topA.y, -height)
            let bottomC = SIMD3<Float>(topC.x, topC.y, -height)
            builder.flat(topA, topC, bottomC, facing: hint)
            builder.flat(topA, bottomC, bottomA, facing: hint)
        }
    }

    // Underside: the outline seen from above, flipped to face down.
    var outline: [SIMD2<Float>] = []
    for s in stations { outline.append(SIMD2<Float>(-s.halfWidth, s.y)) }
    for s in stations.reversed() where s.halfWidth > 1e-6 { outline.append(SIMD2<Float>(s.halfWidth, s.y)) }
    let cleaned = cleanedLoop(outline)
    for tri in WatchMesh.triangulate(cleaned).chunked(3) {
        let a = cleaned[Int(tri[0])], b = cleaned[Int(tri[1])], c = cleaned[Int(tri[2])]
        builder.flat(
            SIMD3<Float>(a.x, a.y, -height), SIMD3<Float>(b.x, b.y, -height), SIMD3<Float>(c.x, c.y, -height),
            facing: SIMD3<Float>(0, 0, -1)
        )
    }

    // End caps where the hand has width there.
    for (index, hint) in [(0, SIMD3<Float>(0, -1, 0)), (m - 1, SIMD3<Float>(0, 1, 0))] {
        let s = stations[index]
        guard s.halfWidth > 1e-6 else { continue }
        var polygon: [SIMD2<Float>] = [
            SIMD2<Float>(-s.halfWidth, -height), SIMD2<Float>(s.halfWidth, -height)
        ]
        for p in sections[index].reversed() { polygon.append(SIMD2<Float>(p.x, p.z)) }
        for tri in WatchMesh.triangulate(polygon).chunked(3) {
            let a = polygon[Int(tri[0])], b = polygon[Int(tri[1])], c = polygon[Int(tri[2])]
            builder.flat(
                SIMD3<Float>(a.x, s.y, a.y), SIMD3<Float>(b.x, s.y, b.y), SIMD3<Float>(c.x, s.y, c.y), facing: hint
            )
        }
    }
}
