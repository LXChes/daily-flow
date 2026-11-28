import DailyFlowCore
import Foundation
import simd

// The 3D watch as a list of parts: which mesh, which material, where it sits and what moves it. Built once from
// `WatchMovement` and the mesh builders in `DailyFlowCore`; the renderer uploads the meshes and draws the list
// every frame, asking this file for each part's material (so a task gear's state decides how its wheel looks).
// Mesh space is the one in `WatchMesh`: dial opening radius 1, x right, y UP, z toward the viewer.

// MARK: Matrices

enum WatchMat {
    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
        return m
    }

    static func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        translation(SIMD3<Float>(x, y, z))
    }

    static func rotationX(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4<Float>(1, 0, 0, 0), SIMD4<Float>(0, c, s, 0), SIMD4<Float>(0, -s, c, 0), SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func rotationY(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4<Float>(c, 0, -s, 0), SIMD4<Float>(0, 1, 0, 0), SIMD4<Float>(s, 0, c, 0), SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func rotationZ(_ angle: Float) -> simd_float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return simd_float4x4(columns: (
            SIMD4<Float>(c, s, 0, 0), SIMD4<Float>(-s, c, 0, 0), SIMD4<Float>(0, 0, 1, 0), SIMD4<Float>(0, 0, 0, 1)
        ))
    }

    static func scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4<Float>(x, y, z, 1))
    }

    /// Right-handed perspective for Metal's 0...1 depth range, looking down -z.
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let f = 1 / tan(fovY / 2)
        return simd_float4x4(columns: (
            SIMD4<Float>(f / aspect, 0, 0, 0),
            SIMD4<Float>(0, f, 0, 0),
            SIMD4<Float>(0, 0, far / (near - far), -1),
            SIMD4<Float>(0, 0, near * far / (near - far), 0)
        ))
    }

    /// Orthographic box for Metal's 0...1 depth range, looking down -z.
    static func orthographic(half: Float, near: Float, far: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4<Float>(1 / half, 0, 0, 0),
            SIMD4<Float>(0, 1 / half, 0, 0),
            SIMD4<Float>(0, 0, 1 / (near - far), 0),
            SIMD4<Float>(0, 0, near / (near - far), 1)
        ))
    }

    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = simd_normalize(center - eye)
        let s = simd_normalize(simd_cross(f, up))
        let u = simd_cross(s, f)
        return simd_float4x4(columns: (
            SIMD4<Float>(s.x, u.x, -f.x, 0),
            SIMD4<Float>(s.y, u.y, -f.y, 0),
            SIMD4<Float>(s.z, u.z, -f.z, 0),
            SIMD4<Float>(-simd_dot(s, eye), -simd_dot(u, eye), simd_dot(f, eye), 1)
        ))
    }
}

// MARK: GPU material

/// Mirrors `Material` in WatchShaders.metal: four float4s.
struct WatchGPUMaterial {
    var baseColor: SIMD4<Float>
    var emissive: SIMD4<Float>
    var params: SIMD4<Float>
    var extra: SIMD4<Float>

    /// The shader's `kind`.
    enum Kind: Float {
        case standard = 0
        case plate = 1
        case bridge = 2
        case jewel = 3
        case crystal = 4
        case emissive = 5
        case printOpaque = 6
        case printOverlay = 7
        case leather = 8
    }

    static func make(
        _ surface: WatchMaterialTokens.Surface,
        kind: Kind = .standard,
        pattern: Float = 0,
        strength: Float = 0,
        bevel: Float = 0,
        emissive: SIMD3<Float> = .zero,
        glow: Float = 0
    ) -> WatchGPUMaterial {
        WatchGPUMaterial(
            baseColor: SIMD4<Float>(surface.color, 1),
            emissive: SIMD4<Float>(emissive, 1),
            params: SIMD4<Float>(surface.metallic, surface.roughness, surface.clearcoat, kind.rawValue),
            extra: SIMD4<Float>(pattern, strength, bevel, glow)
        )
    }

    static func glowing(_ color: SIMD3<Float>, glow: Float, kind: Kind = .emissive) -> WatchGPUMaterial {
        WatchGPUMaterial(
            baseColor: SIMD4<Float>(color, 1),
            emissive: SIMD4<Float>(color, 1),
            params: SIMD4<Float>(0, 0.5, 0, kind.rawValue),
            extra: SIMD4<Float>(0, 0, 0, glow)
        )
    }
}

// MARK: Parts

/// Which material a part is made of. The task-bound cases carry their gear slot, so the gear's state decides.
enum WatchSurface: Sendable {
    case plate
    case caseMetal
    case crown
    case bracelet
    case braceletPolished
    case bezelPrint
    case ringPrint
    case ringWall
    case progress
    case crystal
    case leather
    case wheelTask(slot: Int)
    case wheelPlain
    case barrel
    case mainspring
    case bridge
    case screw
    case screwSlot
    case chaton
    case jewelTask(slot: Int)
    case jewelPlain
    case hubRing(slot: Int)
    case hairspring
    case balance
    case fork
    case forkStone
    case hand
    case lume
    case dayArrow
    case seconds
    case secondsTip
    case cap
    case capDot
    case selection
}

/// Extra texture a part samples (beside the shared printed texture).
enum WatchAux: Sendable {
    case none
    case progress
    case leatherUpper
    case leatherLower
}

struct WatchDrawable: Sendable {
    enum Layer: Sendable {
        case opaque
        case overlay
        case glass
    }

    /// What moves the part each frame.
    enum Motion: Sendable {
        case fixed
        case wheel(id: Int)
        case balance
        case hairspring
        case fork
        case hour
        case minute
        case day
        case seconds
        case selection
    }

    let mesh: Int
    let surface: WatchSurface
    let layer: Layer
    let motion: Motion
    /// The placement before any motion: for a wheel the translation to its centre and layer.
    let base: simd_float4x4
    let castsShadow: Bool
    /// Only drawn in this theme; nil is both.
    let theme: ThemeMode?
    let aux: WatchAux
}

/// Everything the material of a part can depend on this frame.
struct WatchMaterialContext {
    let tokens: WatchMaterialTokens
    let gears: [Int: WatchGear]
    /// Linear category colour of each gear slot.
    let slotColors: [Int: SIMD3<Float>]
    /// Brightness of an urgent jewel, 0...1.
    let pulse: Float
}

extension WatchSurface {
    func material(_ context: WatchMaterialContext) -> WatchGPUMaterial {
        let t = context.tokens
        switch self {
        case .plate:
            return .make(t.plate, kind: .plate)
        case .caseMetal:
            return .make(t.caseMetal, bevel: 0)
        case .crown:
            return .make(t.caseMetal, pattern: 2, strength: 0.3)
        case .bracelet:
            return .make(t.braceletSatin, pattern: 1, strength: 0.16, bevel: 0.7)
        case .braceletPolished:
            return .make(t.braceletPolished, bevel: 0.4)
        case .bezelPrint:
            return .make(t.bezelBody, kind: .printOpaque)
        case .ringPrint:
            return .make(t.ringBody, kind: .printOpaque)
        case .ringWall:
            return .make(t.ringWall)
        case .progress:
            return .make(.init(color: SIMD3<Float>(1, 1, 1), metallic: 0, roughness: 0.5), kind: .printOverlay)
        case .crystal:
            return .make(
                .init(color: t.crystalTint, metallic: 0, roughness: 0.03), kind: .crystal, strength: 1.7
            )
        case .leather:
            return .make(t.leather, kind: .leather, strength: 0.2)
        case .wheelTask(let slot):
            guard let gear = context.gears[slot] else { return .make(t.wheelPlain, bevel: 0.8) }
            return gear.state == .done ? .make(t.wheelDone, bevel: 1) : .make(t.wheel, bevel: 1)
        case .wheelPlain:
            return .make(t.wheelPlain, bevel: 0.8)
        case .barrel:
            return .make(t.barrel, bevel: 0.8)
        case .mainspring:
            return .make(t.mainspring)
        case .bridge:
            return .make(t.bridge, kind: .bridge, strength: 0.32, bevel: 1, emissive: t.bridgeBevel)
        case .screw:
            return .make(t.screw, bevel: 0.6)
        case .screwSlot:
            return .make(t.screwSlot)
        case .chaton:
            return .make(t.chaton)
        case .jewelTask(let slot):
            return jewel(for: context.gears[slot], context)
        case .jewelPlain:
            return jewelMaterial(base: t.ruby, glowColor: t.rubyGlow, glow: 0.3)
        case .hubRing(let slot):
            let color = context.slotColors[slot] ?? t.chaton.color
            let done = context.gears[slot]?.state == .done
            return .glowing(done ? t.doneGlow : color, glow: context.gears[slot] == nil ? 0.25 : 1.3)
        case .hairspring:
            return .make(t.hairspring)
        case .balance:
            return .make(t.balance, bevel: 0.8)
        case .fork:
            return .make(t.fork, bevel: 0.6)
        case .forkStone:
            return jewelMaterial(base: t.ruby, glowColor: t.rubyGlow, glow: 0.25)
        case .hand:
            return .make(t.hand, bevel: 1)
        case .lume:
            return .glowing(t.lume, glow: t.lumeGain)
        case .dayArrow:
            return .make(t.dayArrow, bevel: 0.5, emissive: t.dayArrow.color, glow: t.dayArrowGlow)
        case .seconds:
            return .make(t.seconds, bevel: 1)
        case .secondsTip:
            return .glowing(t.secondsTip, glow: t.lumeGain > 0 ? 1.7 : 0.2)
        case .cap:
            return .make(t.cap, bevel: 0.5)
        case .capDot:
            return .make(t.capDot)
        case .selection:
            return .glowing(t.selection, glow: 1.6 + 1.2 * context.pulse)
        }
    }

    private func jewelMaterial(base: SIMD3<Float>, glowColor: SIMD3<Float>, glow: Float) -> WatchGPUMaterial {
        WatchGPUMaterial(
            baseColor: SIMD4<Float>(base, 1),
            emissive: SIMD4<Float>(glowColor, 1),
            params: SIMD4<Float>(0, 0.1, 0, WatchGPUMaterial.Kind.jewel.rawValue),
            extra: SIMD4<Float>(0, 0, 0, glow)
        )
    }

    /// A task gear's jewel: ruby, glowing red when the task is urgent, bright when it is done, dim with no task.
    private func jewel(for gear: WatchGear?, _ context: WatchMaterialContext) -> WatchGPUMaterial {
        let t = context.tokens
        guard let gear else { return jewelMaterial(base: t.ruby, glowColor: t.rubyGlow, glow: 0.08) }
        if gear.state == .done {
            return jewelMaterial(base: t.doneGlow, glowColor: t.doneGlow, glow: 1.5)
        }
        if gear.pulsesJewel {
            return jewelMaterial(base: t.ruby, glowColor: t.rubyGlow, glow: 0.4 + 2.6 * context.pulse)
        }
        return jewelMaterial(base: t.ruby, glowColor: t.rubyGlow, glow: 0.35)
    }
}

// MARK: Scene

struct WatchScene: Sendable {
    let meshes: [WatchMeshData]
    let drawables: [WatchDrawable]

    /// Built once, on first use.
    static let shared: WatchScene = {
        var builder = WatchSceneBuilder()
        builder.buildAll()
        return WatchScene(meshes: builder.meshes, drawables: builder.drawables)
    }()
}

/// Layer heights (the z of each part's top face), from the shared contract.
enum WatchLevel {
    static let plate: Float = 0
    static let wheelLow: Float = 0.06
    static let wheelHigh: Float = 0.10
    static let barrel: Float = 0.07
    static let fork: Float = 0.09
    static let balance: Float = 0.12
    static let bridge: Float = 0.14
    static let ring: Float = 0.17
    static let hourHand: Float = 0.20
    static let minuteHand: Float = 0.215
    static let dayHand: Float = 0.23
    static let secondsHand: Float = 0.245
    static let crystalApex: Float = 0.34
    static let bezel: Float = 0.2205
    static let bridgeThickness: Float = 0.032
}

private struct WatchSceneBuilder {
    var meshes: [WatchMeshData] = []
    var drawables: [WatchDrawable] = []

    private let wheelsByCenter: [WatchPoint: WatchWheel] = Dictionary(
        WatchMovement.allWheels.map { ($0.center, $0) }, uniquingKeysWith: { first, _ in first }
    )

    // MARK: Plumbing

    mutating func addMesh(_ data: WatchMeshData) -> Int? {
        guard data.triangleCount > 0 else { return nil }
        meshes.append(data)
        return meshes.count - 1
    }

    @discardableResult
    mutating func add(
        _ data: WatchMeshData,
        _ surface: WatchSurface,
        motion: WatchDrawable.Motion = .fixed,
        layer: WatchDrawable.Layer = .opaque,
        base: simd_float4x4 = matrix_identity_float4x4,
        shadow: Bool = false,
        theme: ThemeMode? = nil,
        aux: WatchAux = .none
    ) -> Int? {
        guard let index = addMesh(data) else { return nil }
        place(index, surface, motion: motion, layer: layer, base: base, shadow: shadow, theme: theme, aux: aux)
        return index
    }

    /// Another instance of a mesh that is already added.
    mutating func place(
        _ mesh: Int,
        _ surface: WatchSurface,
        motion: WatchDrawable.Motion = .fixed,
        layer: WatchDrawable.Layer = .opaque,
        base: simd_float4x4 = matrix_identity_float4x4,
        shadow: Bool = false,
        theme: ThemeMode? = nil,
        aux: WatchAux = .none
    ) {
        drawables.append(
            WatchDrawable(
                mesh: mesh, surface: surface, layer: layer, motion: motion, base: base,
                castsShadow: shadow, theme: theme, aux: aux
            )
        )
    }

    private func flipped(_ point: WatchPoint) -> SIMD2<Float> {
        SIMD2<Float>(Float(point.x), -Float(point.y))
    }

    // MARK: Shape helpers

    /// A centred rounded rectangle, counter-clockwise.
    private static func roundedRect(width: Float, height: Float, radius: Float, steps: Int = 4) -> [SIMD2<Float>] {
        let r = min(radius, width / 2, height / 2)
        let hx = width / 2 - r
        let hy = height / 2 - r
        let corners: [(center: SIMD2<Float>, start: Float)] = [
            (SIMD2<Float>(hx, -hy), -.pi / 2), (SIMD2<Float>(hx, hy), 0),
            (SIMD2<Float>(-hx, hy), .pi / 2), (SIMD2<Float>(-hx, -hy), .pi)
        ]
        var points: [SIMD2<Float>] = []
        for corner in corners {
            for step in 0...steps {
                let angle = corner.start + (.pi / 2) * Float(step) / Float(steps)
                points.append(corner.center + SIMD2<Float>(cos(angle), sin(angle)) * r)
            }
        }
        return points
    }

    /// A short flat-topped cylinder: top face at z = 0, going down by `height`.
    private static func disc(radius: Float, height: Float, chamfer: Float, segments: Int = 40) -> WatchMeshData {
        WatchMesh.lathe(
            [
                SIMD2<Float>(radius, -height), SIMD2<Float>(radius, -chamfer),
                SIMD2<Float>(radius - chamfer, 0), SIMD2<Float>(0, 0)
            ],
            segments: segments,
            creases: [1, 2]
        )
    }

    /// A shallow dome (a jewel): base at z = 0, apex at z = height.
    private static func dome(radius: Float, height: Float, segments: Int = 36) -> WatchMeshData {
        var profile: [SIMD2<Float>] = [SIMD2<Float>(radius, -0.002)]
        let steps = 7
        for step in 0...steps {
            let angle = (.pi / 2) * Float(step) / Float(steps)
            profile.append(SIMD2<Float>(radius * cos(angle), height * sin(angle)))
        }
        return WatchMesh.lathe(profile, segments: segments)
    }

    /// A thin ring with a bore, top face at z = 0.
    private static func chatonRing(outer: Float, inner: Float, height: Float) -> WatchMeshData {
        WatchMesh.lathe(
            [
                SIMD2<Float>(outer, -height), SIMD2<Float>(outer, -0.003), SIMD2<Float>(outer - 0.003, 0),
                SIMD2<Float>(inner, 0), SIMD2<Float>(inner, -height)
            ],
            segments: 40,
            creases: [1, 2, 3]
        )
    }

    /// A rod along local +z from 0 to `length`.
    private static func rod(radius: Float, length: Float) -> WatchMeshData {
        WatchMesh.lathe(
            [SIMD2<Float>(radius, 0), SIMD2<Float>(radius, length), SIMD2<Float>(0, length)],
            segments: 20,
            creases: [1]
        )
    }

    // MARK: Build

    mutating func buildAll() {
        buildCase()
        buildDial()
        buildMovement()
        buildBridges()
        buildEscapement()
        buildHands()
        buildHardware()
        buildBracelet()
        buildStrap()
        buildSelection()
    }

    // MARK: Case and crystal

    private mutating func buildCase() {
        let profile: [SIMD2<Float>] = [
            SIMD2<Float>(1.08, -0.25), SIMD2<Float>(1.195, -0.246), SIMD2<Float>(1.236, -0.222),
            SIMD2<Float>(1.2475, -0.17), SIMD2<Float>(1.2495, -0.02), SIMD2<Float>(1.2455, 0.10),
            SIMD2<Float>(1.234, 0.150), SIMD2<Float>(1.212, 0.182), SIMD2<Float>(1.182, 0.207),
            SIMD2<Float>(1.162, 0.22)
        ]
        add(WatchMesh.lathe(profile, segments: 192, creases: [8]), .caseMetal)

        // Domed sapphire: a spherical cap, apex 0.34, with a vertical rim for a bright edge.
        let baseRadius: Float = 1.15
        let rise: Float = 0.114
        let sphere = (baseRadius * baseRadius + rise * rise) / (2 * rise)
        var crystal: [SIMD2<Float>] = [SIMD2<Float>(baseRadius, WatchLevel.bezel)]
        let steps = 18
        for step in 0...steps {
            let r = baseRadius * (1 - Float(step) / Float(steps))
            let z = WatchLevel.crystalApex - (sphere - (sphere * sphere - r * r).squareRoot())
            crystal.append(SIMD2<Float>(r, z))
        }
        add(WatchMesh.lathe(crystal, segments: 160, creases: [1]), .crystal, layer: .glass)
    }

    // MARK: Dial: plate, hour ring, bezel, printed overlay

    private mutating func buildDial() {
        add(WatchMesh.ring(inner: 0, outer: 1.0, segments: 160), .plate, base: WatchMat.translation(0, 0, WatchLevel.plate))

        // The hour ring face (a printed texture), its inner wall, and the plate's edge under it.
        add(
            WatchMesh.ring(inner: 0.885, outer: 1.0, segments: 160), .ringPrint,
            base: WatchMat.translation(0, 0, WatchLevel.ring), shadow: true
        )
        add(
            WatchMesh.lathe([SIMD2<Float>(0.885, WatchLevel.ring), SIMD2<Float>(0.885, 0)], segments: 160),
            .ringWall, shadow: true
        )

        // The bezel face (printed) and its inner wall dropping to the hour ring.
        add(
            WatchMesh.ring(inner: 1.0, outer: 1.166, segments: 192), .bezelPrint,
            base: WatchMat.translation(0, 0, WatchLevel.bezel), shadow: true
        )
        add(
            WatchMesh.lathe(
                [SIMD2<Float>(1.0, WatchLevel.bezel), SIMD2<Float>(1.0, WatchLevel.ring)], segments: 192
            ),
            .ringWall, shadow: true
        )

        // Progress arc and label: printed on a see-through disc at the hour ring's height.
        add(
            WatchMesh.ring(inner: 0, outer: 0.905, segments: 128), .progress,
            layer: .overlay, base: WatchMat.translation(0, 0, WatchLevel.ring + 0.002), aux: .progress
        )
    }

    // MARK: Wheels and barrel

    private mutating func buildMovement() {
        let thickness: Float = 0.022
        let shaft = addMesh(Self.rod(radius: 0.011, length: 1))
        for wheel in WatchMovement.allWheels {
            let top: Float
            if wheel.role == .barrel {
                top = WatchLevel.barrel
            } else {
                top = wheel.layer == 0 ? WatchLevel.wheelLow : WatchLevel.wheelHigh
            }
            let tip = Float(wheel.tipRadius)
            let mesh = WatchMesh.wheel(
                wheel, thickness: thickness, spokes: WatchMesh.spokeCount(for: wheel), arbor: tip * 0.1, bevel: 0.0045
            )
            let center = SIMD3<Float>(Float(wheel.center.x), -Float(wheel.center.y), top)
            let surface: WatchSurface
            if let slot = wheel.taskSlot {
                surface = .wheelTask(slot: slot)
            } else {
                surface = wheel.role == .barrel ? .barrel : .wheelPlain
            }
            add(mesh, surface, motion: .wheel(id: wheel.id), base: WatchMat.translation(center), shadow: true)

            // The arbor: a thin steel shaft from the wheel up to the underside of its bridge.
            if let shaft {
                let bottom = top
                let length = WatchLevel.bridge - WatchLevel.bridgeThickness - bottom
                if length > 0 {
                    place(
                        shaft, .screw,
                        base: WatchMat.translation(center.x, center.y, bottom) * WatchMat.scale(1, 1, length)
                    )
                }
            }

            if wheel.role == .barrel {
                // The mainspring, coiled in the drum's recess, turning with it.
                add(
                    WatchMesh.hairspring(
                        inner: 0.02, outer: Float(wheel.rootRadius) * 0.8, turns: 5, width: 0.006, height: 0.008
                    ),
                    .mainspring, motion: .wheel(id: wheel.id),
                    base: WatchMat.translation(center.x, center.y, top - 0.006), shadow: true
                )
            }
        }
    }

    // MARK: Bridges, screws, jewels

    private mutating func buildBridges() {
        let postMesh = addMesh(Self.disc(radius: 0.028, height: 0.012, chamfer: 0.004))
        let slotMesh = addMesh(
            WatchMesh.extrude(
                [SIMD2<Float>(-0.019, -0.0035), SIMD2<Float>(0.019, -0.0035), SIMD2<Float>(0.019, 0.0035), SIMD2<Float>(-0.019, 0.0035)],
                depth: 0.002, bevel: 0
            )
        )
        let chaton = addMesh(Self.chatonRing(outer: 0.04, inner: 0.027, height: 0.012))
        let jewel = addMesh(Self.dome(radius: 0.0275, height: 0.013))
        let ring = addMesh(WatchMesh.ring(inner: 0.044, outer: 0.055, segments: 40))
        let top = WatchLevel.bridge

        func placeHub(_ builder: inout WatchSceneBuilder, _ point: WatchPoint, index: Int) {
            let x = Float(point.x)
            let y = -Float(point.y)
            let isBalance = point == WatchMovement.balance.center
            if let wheel = builder.wheelsByCenter[point] {
                if let chaton {
                    builder.place(chaton, .chaton, base: WatchMat.translation(x, y, top + 0.010), shadow: true)
                }
                if let jewel {
                    let surface: WatchSurface = wheel.taskSlot.map { .jewelTask(slot: $0) } ?? .jewelPlain
                    builder.place(jewel, surface, base: WatchMat.translation(x, y, top + 0.0085))
                }
                if let slot = wheel.taskSlot, let ring {
                    builder.place(ring, .hubRing(slot: slot), base: WatchMat.translation(x, y, top + 0.0012))
                }
            } else if !isBalance {
                // A screw: a domed head with a slot, turned a different way each time.
                let turn = Float(index) * 1.7
                if let postMesh {
                    builder.place(postMesh, .screw, base: WatchMat.translation(x, y, top + 0.012), shadow: true)
                }
                if let slotMesh {
                    builder.place(
                        slotMesh, .screwSlot,
                        base: WatchMat.translation(x, y, top + 0.0122) * WatchMat.rotationZ(turn)
                    )
                }
            }
        }

        var hubIndex = 0
        for (index, bridge) in WatchMovement.bridges.enumerated() {
            let outline = bridge.outline.map { flipped($0) }
            add(
                WatchMesh.extrude(outline, depth: WatchLevel.bridgeThickness, bevel: 0.007), .bridge,
                base: WatchMat.translation(0, 0, top), shadow: true
            )
            for hub in bridge.hubs {
                placeHub(&self, hub, index: hubIndex)
                hubIndex += 1
            }
            // The long arms get a screw between their pivots.
            if index < 2 {
                for pair in zip(bridge.hubs, bridge.hubs.dropFirst()) {
                    let mid = WatchPoint(x: (pair.0.x + pair.1.x) / 2, y: (pair.0.y + pair.1.y) / 2)
                    placeHub(&self, mid, index: hubIndex)
                    hubIndex += 1
                }
            }
        }
        // The balance's own pivot jewel, on its hub.
        let center = WatchMovement.balance.center
        if let chaton, let jewel {
            let x = Float(center.x)
            let y = -Float(center.y)
            place(chaton, .chaton, base: WatchMat.translation(x, y, WatchLevel.balance + 0.010), shadow: true)
            place(jewel, .jewelPlain, base: WatchMat.translation(x, y, WatchLevel.balance + 0.0085))
        }
    }

    // MARK: Balance, hairspring, pallet fork

    private mutating func buildEscapement() {
        let balance = WatchMovement.balance
        let center = SIMD3<Float>(Float(balance.center.x), -Float(balance.center.y), WatchLevel.balance)
        let radius = Float(balance.radius)
        add(
            WatchMesh.balance(radius: radius, thickness: 0.02), .balance, motion: .balance,
            base: WatchMat.translation(center), shadow: true
        )
        add(
            WatchMesh.hairspring(inner: 0.018, outer: radius * 0.62, turns: 9, width: 0.005, height: 0.006),
            .hairspring, motion: .hairspring,
            base: WatchMat.translation(center.x, center.y, WatchLevel.balance - 0.014)
        )

        // The fork, built along local +x (the tail toward the balance) and turned into place each frame.
        let fork = WatchMovement.fork
        let tail = Float(fork.tailLength)
        let arm = Float(fork.armLength)
        let spread = Float(fork.armSpread) * .pi / 180
        func bar(from start: SIMD2<Float>, to end: SIMD2<Float>, startWidth: Float, endWidth: Float) -> [SIMD2<Float>] {
            let d = simd_normalize(end - start)
            let n = SIMD2<Float>(-d.y, d.x)
            return [start - n * startWidth, end - n * endWidth, end + n * endWidth, start + n * startWidth]
        }
        let origin = SIMD2<Float>(0, 0)
        let tailBar = bar(from: origin, to: SIMD2<Float>(tail, 0), startWidth: 0.014, endWidth: 0.008)
        var parts = [WatchMesh.extrude(tailBar, depth: 0.014, bevel: 0.003)]
        var stones: [WatchMeshData] = []
        for side: Float in [-1, 1] {
            let tip = SIMD2<Float>(-cos(spread) * arm, side * sin(spread) * arm)
            parts.append(WatchMesh.extrude(bar(from: origin, to: tip, startWidth: 0.014, endWidth: 0.008), depth: 0.014, bevel: 0.003))
            let stone = WatchMesh.extrude(
                Self.roundedRect(width: 0.022, height: 0.012, radius: 0.003, steps: 1), depth: 0.014, bevel: 0.002
            )
            let heading = atan2(tip.y, tip.x)
            stones.append(stone.transformed(by: WatchMat.translation(tip.x, tip.y, 0) * WatchMat.rotationZ(heading)))
        }
        parts.append(Self.disc(radius: 0.03, height: 0.014, chamfer: 0.004))
        let pivot = WatchMovement.fork.pivot
        let base = WatchMat.translation(Float(pivot.x), -Float(pivot.y), WatchLevel.fork)
        add(WatchMeshData.merged(parts), .fork, motion: .fork, base: base, shadow: true)
        add(WatchMeshData.merged(stones), .forkStone, motion: .fork, base: base)
    }

    // MARK: Hands

    private mutating func buildHands() {
        let unit: Float = 1 / 122
        // Dark: faceted chrome batons with lume. Light: blued Breguet hands.
        let batonHour = WatchMesh.hand(.baton, length: 66 * unit, width: 4.75 * unit, tail: 14 * unit, height: 0.012)
        let batonMinute = WatchMesh.hand(.baton, length: 100 * unit, width: 3.2 * unit, tail: 16 * unit, height: 0.012)
        let breguetHour = WatchMesh.hand(.breguet, length: 66 * unit, width: 4.7 * unit, tail: 12 * unit, height: 0.011)
        let breguetMinute = WatchMesh.hand(.breguet, length: 100 * unit, width: 3.7 * unit, tail: 14 * unit, height: 0.011)

        add(batonHour.body, .hand, motion: .hour, shadow: true, theme: .dark)
        add(batonHour.lume, .lume, motion: .hour, theme: .dark)
        add(batonMinute.body, .hand, motion: .minute, shadow: true, theme: .dark)
        add(batonMinute.lume, .lume, motion: .minute, theme: .dark)
        add(breguetHour.body, .hand, motion: .hour, shadow: true, theme: .light)
        add(breguetMinute.body, .hand, motion: .minute, shadow: true, theme: .light)

        let arrow = WatchMesh.hand(.arrow, length: 123 * unit, width: 5.2 * unit, tail: 16 * unit, height: 0.01)
        add(arrow.body, .dayArrow, motion: .day, shadow: true)

        let seconds = WatchMesh.hand(.seconds, length: 108 * unit, width: 3.4 * unit, tail: 28 * unit, height: 0.008)
        add(seconds.body, .seconds, motion: .seconds, shadow: true)
        // The tip of the seconds hand, in its own colour.
        let tip = WatchMesh.extrude(
            [SIMD2<Float>(-0.0055, 0.70), SIMD2<Float>(0.0055, 0.70), SIMD2<Float>(0.002, 0.885), SIMD2<Float>(-0.002, 0.885)],
            depth: 0.003, bevel: 0
        )
        add(tip, .secondsTip, motion: .seconds, base: WatchMat.translation(0, 0, 0.0008))

        // The cap over every hand.
        let cap = WatchMesh.lathe(
            [
                SIMD2<Float>(0.05, 0), SIMD2<Float>(0.05, 0.010), SIMD2<Float>(0.036, 0.020),
                SIMD2<Float>(0.015, 0.024), SIMD2<Float>(0, 0.024)
            ],
            segments: 40,
            creases: [1]
        )
        add(cap, .cap, base: WatchMat.translation(0, 0, WatchLevel.secondsHand + 0.002), shadow: true)
        add(
            Self.disc(radius: 0.018, height: 0.004, chamfer: 0.001), .capDot,
            base: WatchMat.translation(0, 0, WatchLevel.secondsHand + 0.0265)
        )
    }

    // MARK: Lugs, crown, spring bars

    private mutating func buildHardware() {
        let lug = WatchMesh.extrude(Self.roundedRect(width: 0.213, height: 0.58, radius: 0.07, steps: 5), depth: 0.22, bevel: 0.02)
        if let index = addMesh(lug) {
            for side: Float in [-1, 1] {
                for end: Float in [-1, 1] {
                    place(index, .caseMetal, base: WatchMat.translation(side * 0.443, end * 1.235, 0.10))
                }
            }
        }

        let crown = WatchMovement.crown
        let crownLength: Float = Float(crown.width)
        let crownRadius = Float(crown.height) / 2
        let profile: [SIMD2<Float>] = [
            SIMD2<Float>(crownRadius - 0.012, 0), SIMD2<Float>(crownRadius, 0.012),
            SIMD2<Float>(crownRadius, crownLength - 0.014), SIMD2<Float>(crownRadius - 0.012, crownLength),
            SIMD2<Float>(0, crownLength)
        ]
        let crownStart = Float(crown.center.x) - crownLength / 2
        let toX = WatchMat.rotationY(.pi / 2)
        add(
            WatchMesh.lathe(profile, segments: 64, creases: [1, 3]), .crown,
            base: WatchMat.translation(crownStart, 0, -0.02) * toX
        )
        add(
            Self.rod(radius: 0.03, length: crownStart - 1.2), .caseMetal,
            base: WatchMat.translation(1.2, 0, -0.02) * toX
        )

        // Spring bars between the lugs.
        if let bar = addMesh(Self.rod(radius: 0.016, length: 0.8)) {
            for end: Float in [-1, 1] {
                place(bar, .screw, base: WatchMat.translation(-0.4, end * 1.46, -0.02) * toX)
            }
        }
    }

    // MARK: Bracelet (dark)

    private mutating func buildBracelet() {
        let pitch: Float = 23.0 / 122
        let satin = WatchMesh.extrude(Self.roundedRect(width: 23.0 / 122, height: 21.0 / 122, radius: 0.045), depth: 0.075, bevel: 0.012)
        let polished = WatchMesh.extrude(Self.roundedRect(width: 31.0 / 122, height: 21.0 / 122, radius: 0.045), depth: 0.075, bevel: 0.012)
        guard let satinIndex = addMesh(satin), let polishedIndex = addMesh(polished) else { return }
        for direction: Float in [-1, 1] {
            for row in 0..<6 {
                let along = 1.30 + Float(row) * pitch
                for link in 0..<3 {
                    let isCentre = link == 1
                    let x: Float = isCentre ? 0 : (link == 0 ? -28.5 : 28.5) / 122
                    let y = along + (isCentre ? pitch / 2 : 0)
                    // The bracelet drops away from the case, bending gently.
                    let bend = max(0, y - 1.4)
                    let z: Float = -0.02 - 0.09 * bend * bend
                    let slope = 0.18 * bend
                    let matrix = WatchMat.translation(x, direction * y, z) * WatchMat.rotationX(-direction * slope)
                    place(
                        isCentre ? polishedIndex : satinIndex, isCentre ? .braceletPolished : .bracelet,
                        base: matrix, theme: .dark
                    )
                }
            }
        }
    }

    // MARK: Leather strap (light)

    private mutating func buildStrap() {
        for direction: Float in [-1, 1] {
            let mesh = Self.strap(halfWidth: 40.0 / 122, start: 1.12, length: 1.5, direction: direction)
            add(mesh, .leather, theme: .light, aux: direction < 0 ? .leatherLower : .leatherUpper)
        }
    }

    /// A padded strap running away from the case, sagging gently, edges rolled, with a skirt down the sides.
    private static func strap(halfWidth hw: Float, start: Float, length: Float, direction: Float) -> WatchMeshData {
        let nx = 12
        let ny = 36
        func height(_ x: Float, _ s: Float) -> Float {
            let along = start + s
            let reach = max(0, along - 1.2)
            let sag = -0.02 - 0.09 * reach * reach
            let t = abs(x) / hw
            let u = max(0, (t - 0.8) / 0.2)
            return sag - 0.035 * u * u
        }
        var builder = LocalMesh()
        var grid: [[UInt32]] = []
        let h: Float = 0.002
        for j in 0...ny {
            let s = length * Float(j) / Float(ny)
            var row: [UInt32] = []
            for i in 0...nx {
                let x = -hw + 2 * hw * Float(i) / Float(nx)
                let z = height(x, s)
                let dzdx = (height(x + h, s) - height(x - h, s)) / (2 * h)
                let dzds = (height(x, s + h) - height(x, s - h)) / (2 * h)
                let normal = simd_normalize(SIMD3<Float>(-dzdx, -dzds * direction, 1))
                row.append(
                    builder.vertex(
                        SIMD3<Float>(x, direction * (start + s), z), normal,
                        SIMD2<Float>(x / (2 * hw) + 0.5, s / length)
                    )
                )
            }
            grid.append(row)
        }
        let up = SIMD3<Float>(0, 0, 1)
        for j in 0..<ny {
            for i in 0..<nx {
                builder.triangle(grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], facing: up)
                builder.triangle(grid[j][i], grid[j + 1][i + 1], grid[j + 1][i], facing: up)
            }
        }
        // The skirt: a wall down each long edge.
        let drop: Float = 0.075
        for side: Float in [-1, 1] {
            let outward = SIMD3<Float>(side, 0, 0)
            var topRow: [UInt32] = []
            var bottomRow: [UInt32] = []
            for j in 0...ny {
                let s = length * Float(j) / Float(ny)
                let x = side * hw
                let z = height(x, s)
                let y = direction * (start + s)
                topRow.append(builder.vertex(SIMD3<Float>(x, y, z), outward, SIMD2<Float>(side > 0 ? 1 : 0, s / length)))
                bottomRow.append(builder.vertex(SIMD3<Float>(x, y, z - drop), outward, SIMD2<Float>(side > 0 ? 1 : 0, s / length)))
            }
            for j in 0..<ny {
                builder.triangle(topRow[j], topRow[j + 1], bottomRow[j + 1], facing: outward)
                builder.triangle(topRow[j], bottomRow[j + 1], bottomRow[j], facing: outward)
            }
        }
        return builder.build()
    }

    // MARK: Selection ring

    private mutating func buildSelection() {
        // A flat glowing ring, scaled and moved onto the selected gear by the renderer.
        add(WatchMesh.ring(inner: 1.0, outer: 1.09, segments: 64), .selection, motion: .selection)
    }
}

/// A tiny mesh builder for the custom strap: it fixes triangle winding from the direction a face should look.
private struct LocalMesh {
    private var positions: [SIMD3<Float>] = []
    private var normals: [SIMD3<Float>] = []
    private var uvs: [SIMD2<Float>] = []
    private var indices: [UInt32] = []

    mutating func vertex(_ position: SIMD3<Float>, _ normal: SIMD3<Float>, _ uv: SIMD2<Float>) -> UInt32 {
        positions.append(position)
        normals.append(normal)
        uvs.append(uv)
        return UInt32(positions.count - 1)
    }

    mutating func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32, facing: SIMD3<Float>) {
        let pa = positions[Int(a)]
        let pb = positions[Int(b)]
        let pc = positions[Int(c)]
        let faceNormal = simd_cross(pb - pa, pc - pa)
        if simd_dot(faceNormal, facing) >= 0 {
            indices.append(contentsOf: [a, b, c])
        } else {
            indices.append(contentsOf: [a, c, b])
        }
    }

    func build() -> WatchMeshData {
        WatchMeshData(positions: positions, normals: normals, uvs: uvs, indices: indices)
    }
}
