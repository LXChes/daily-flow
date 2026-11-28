import DailyFlowCore
import SwiftUI
import simd

// The watch's one token file: every colour the skeleton watch draws comes from here, for both themes.
// Dark is a gunmetal case with a black ceramic bezel, faceted chrome hands and cyan lume. Light is a gold
// case with an ivory Roman ring, blued Breguet hands and a cream and tobacco bezel. No hex lives anywhere
// else in the watch code. Values come from the signed-off prototype.

private extension Color {
    /// sRGB colour from a 0xRRGGBB literal. Only this file may use it.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

struct WatchPalette: Sendable {
    let isDark: Bool

    // MARK: Case (polished metal ramp, bright to dark)

    let caseA: Color
    let caseB: Color
    let caseC: Color
    let caseD: Color
    let caseE: Color

    // MARK: Bezel (a two-tone 24 hour ring)

    let bezelDayTop: Color
    let bezelDayBottom: Color
    let bezelNightTop: Color
    let bezelNightBottom: Color
    let bezelNumeralDay: Color
    let bezelNumeralNight: Color
    /// The marker at midnight.
    let bezelTriangle: Color
    /// Strength of the crystal's glint.
    let gloss: Double

    // MARK: Plate and movement

    let plateTop: Color
    let plateBottom: Color
    let perlageBright: Color
    let perlageDim: Color
    /// Shadow colour under wheels, bridges and hands.
    let depth: Color
    let gearHighlight: Color
    let gearMid: Color
    let gearShade: Color
    let doneHighlight: Color
    let doneMid: Color
    let doneShade: Color
    let bridgeLight: Color
    let bridgeMid: Color
    let bridgeShade: Color
    /// The bright chamfer on bridge edges.
    let bevel: Color
    let screw: Color
    let chaton: Color
    let hairspring: Color
    let mainspring: Color
    /// Glow of a ticked task's jewel.
    let doneGlow: Color
    let rubyLight: Color
    let rubyMid: Color
    let rubyDark: Color

    // MARK: Hour ring

    let ringTop: Color
    let ringBottom: Color
    let ringNumeral: Color

    // MARK: Hands

    let handLight: Color
    let handDark: Color
    let lume: Color
    /// The day arrow: "now" on the 24 hour bezel.
    let dayArrow: Color
    let secondsShaft: Color
    let secondsTip: Color
    let capLight: Color
    let capDark: Color

    // MARK: Arcs and progress

    let track: Color
    let progress: Color
    let doneArc: Color
    let urgentArc: Color

    // MARK: Strap

    let leatherDark: Color
    let leatherLight: Color
    let stitch: Color

    // MARK: Lock Screen

    /// The flat mark colour for the Lock Screen look. The system recolours it.
    let accessoryInk: Color

    /// Bezel arc colour for a task category.
    func arc(_ category: TaskCategory) -> Color {
        switch category {
        case .uni: isDark ? Color(hex: 0x8FB8FF) : Color(hex: 0x1F3F86)
        case .health: isDark ? Color(hex: 0x6FF0D2) : Color(hex: 0x1F6B4A)
        case .errands: isDark ? Color(hex: 0xFFD27A) : Color(hex: 0xA8741A)
        case .home: isDark ? Color(hex: 0xC4A6FF) : Color(hex: 0x6B2F7A)
        case .career: isDark ? Color(hex: 0xFFAA7A) : Color(hex: 0xA8461A)
        case .social: isDark ? Color(hex: 0xFF9EC4) : Color(hex: 0x9A2A55)
        case .other: isDark ? Color(hex: 0xC9D0D8) : Color(hex: 0x5A4A3A)
        }
    }
}

extension WatchPalette {
    static func `for`(_ theme: ThemeMode) -> WatchPalette {
        switch theme {
        case .dark: .dark
        case .light: .light
        }
    }

    // MARK: Dark: gunmetal, black ceramic, chrome

    static let dark = WatchPalette(
        isDark: true,
        caseA: Color(hex: 0xF1F4F7),
        caseB: Color(hex: 0x6A717B),
        caseC: Color(hex: 0x16191D),
        caseD: Color(hex: 0xB6BDC6),
        caseE: Color(hex: 0x08090B),
        bezelDayTop: Color(hex: 0x23272E),
        bezelDayBottom: Color(hex: 0x0B0C0F),
        bezelNightTop: Color(hex: 0x121418),
        bezelNightBottom: Color(hex: 0x040506),
        bezelNumeralDay: Color(hex: 0xE3E8EE),
        bezelNumeralNight: Color(hex: 0x9AA3AE),
        bezelTriangle: Color(hex: 0xA78BFA),
        gloss: 0.07,
        plateTop: Color(hex: 0x30353D),
        plateBottom: Color(hex: 0x0B0D10),
        perlageBright: Color(hex: 0xFFFFFF, opacity: 0.16),
        perlageDim: Color(hex: 0xFFFFFF, opacity: 0.04),
        depth: Color(hex: 0x030405),
        gearHighlight: Color(hex: 0xFAFCFD),
        gearMid: Color(hex: 0x929BA6),
        gearShade: Color(hex: 0x2A3037),
        doneHighlight: Color(hex: 0xFFFFFF),
        doneMid: Color(hex: 0xB4F0FF),
        doneShade: Color(hex: 0x3A5A78),
        bridgeLight: Color(hex: 0x7A818B),
        bridgeMid: Color(hex: 0x3A4048),
        bridgeShade: Color(hex: 0x17191D),
        bevel: Color(hex: 0xE1E6EC),
        screw: Color(hex: 0xC9D0D8),
        chaton: Color(hex: 0xB8C0C9),
        hairspring: Color(hex: 0xEEF3F8),
        mainspring: Color(hex: 0x8C95A0),
        doneGlow: Color(hex: 0xA8F0FF),
        rubyLight: Color(hex: 0xFF9FB0),
        rubyMid: Color(hex: 0xC8102F),
        rubyDark: Color(hex: 0x3E040E),
        ringTop: Color(hex: 0x1B1E23),
        ringBottom: Color(hex: 0x07080A),
        ringNumeral: Color(hex: 0xFFFFFF),
        handLight: Color(hex: 0xFFFFFF),
        handDark: Color(hex: 0x8A94A0),
        lume: Color(hex: 0xA8F0FF),
        dayArrow: Color(hex: 0xA78BFA),
        secondsShaft: Color(hex: 0xE8EDF2),
        secondsTip: Color(hex: 0xFF4D5E),
        capLight: Color(hex: 0xD9DEE4),
        capDark: Color(hex: 0xA78BFA),
        track: Color(hex: 0xFFFFFF, opacity: 0.05),
        progress: Color(hex: 0xA8F0FF),
        doneArc: Color(hex: 0xFFFFFF),
        urgentArc: Color(hex: 0xFF4D6A),
        leatherDark: Color(hex: 0x16191D),
        leatherLight: Color(hex: 0x3A4048),
        stitch: Color(hex: 0x929BA6),
        accessoryInk: Color(hex: 0xFFFFFF)
    )

    // MARK: Light: gold, ivory, blued steel

    static let light = WatchPalette(
        isDark: false,
        caseA: Color(hex: 0xFFF6D6),
        caseB: Color(hex: 0xDDB766),
        caseC: Color(hex: 0x7A5719),
        caseD: Color(hex: 0xF5DC96),
        caseE: Color(hex: 0x4A340E),
        bezelDayTop: Color(hex: 0xF7EFDC),
        bezelDayBottom: Color(hex: 0xE6D5AE),
        bezelNightTop: Color(hex: 0x6B4A2A),
        bezelNightBottom: Color(hex: 0x3F2A16),
        bezelNumeralDay: Color(hex: 0x2B2218),
        bezelNumeralNight: Color(hex: 0xF3E6C8),
        bezelTriangle: Color(hex: 0x8E1B2A),
        gloss: 0.18,
        plateTop: Color(hex: 0xEDD38E),
        plateBottom: Color(hex: 0x9A7431),
        perlageBright: Color(hex: 0xFFFFFF, opacity: 0.34),
        perlageDim: Color(hex: 0xFFFFFF, opacity: 0.06),
        depth: Color(hex: 0x24190B),
        gearHighlight: Color(hex: 0xFFF7D6),
        gearMid: Color(hex: 0xD4A64C),
        gearShade: Color(hex: 0x6A4B15),
        doneHighlight: Color(hex: 0xFFFFFF),
        doneMid: Color(hex: 0xF6C6A2),
        doneShade: Color(hex: 0x8E4E2B),
        bridgeLight: Color(hex: 0xF4E0AA),
        bridgeMid: Color(hex: 0xCDA554),
        bridgeShade: Color(hex: 0x8E6A28),
        bevel: Color(hex: 0xFFF8DF),
        screw: Color(hex: 0x2B4E9E),
        chaton: Color(hex: 0xE8D196),
        hairspring: Color(hex: 0x2B4E9E),
        mainspring: Color(hex: 0x6A5530),
        doneGlow: Color(hex: 0xFFE08A),
        rubyLight: Color(hex: 0xFF9FB0),
        rubyMid: Color(hex: 0xC8102F),
        rubyDark: Color(hex: 0x3E040E),
        ringTop: Color(hex: 0xF6EEDB),
        ringBottom: Color(hex: 0xE4D3AC),
        ringNumeral: Color(hex: 0x2B2218),
        handLight: Color(hex: 0x3D6AD0),
        handDark: Color(hex: 0x10245A),
        lume: Color(hex: 0x3D6AD0),
        dayArrow: Color(hex: 0x8E1B2A),
        secondsShaft: Color(hex: 0x1E3A7A),
        secondsTip: Color(hex: 0x1E3A7A),
        capLight: Color(hex: 0xE9CF86),
        capDark: Color(hex: 0x1E3A7A),
        track: Color(hex: 0x3C280A, opacity: 0.08),
        progress: Color(hex: 0x8E1B2A),
        doneArc: Color(hex: 0x2B2218),
        urgentArc: Color(hex: 0xFF4D6A),
        leatherDark: Color(hex: 0x4A2814),
        leatherLight: Color(hex: 0x8A5530),
        stitch: Color(hex: 0xE9D5AC),
        accessoryInk: Color(hex: 0xFFFFFF)
    )
}

// MARK: - Material tokens for the 3D watch

private extension SIMD3 where Scalar == Float {
    /// Linear-light colour from a 0xRRGGBB sRGB literal, ready for a physically based shader.
    /// Only this file may use it.
    init(hex: UInt32) {
        func linear(_ shift: UInt32) -> Float {
            let c = Float((hex >> shift) & 0xFF) / 255
            return c <= 0.04045 ? c / 12.92 : Float(pow(Double((c + 0.055) / 1.055), 2.4))
        }
        self.init(linear(16), linear(8), linear(0))
    }
}

/// What the 3D watch's materials are made of, for both themes. Colours are linear light; `metallic` and
/// `roughness` are the usual PBR knobs. The printed layers (bezel numerals, hour ring, task arcs) are not here:
/// they are drawn by the 2D painter from `WatchPalette` and mapped on as a texture.
struct WatchMaterialTokens: Sendable {
    struct Surface: Sendable {
        var color: SIMD3<Float>
        var metallic: Float
        var roughness: Float
        var clearcoat: Float = 0
    }

    // Studio: the procedural room the metal reflects, and the key light with the shadow.
    let envTint: SIMD3<Float>
    let envGain: Float
    let keyColor: SIMD3<Float>
    let keyGain: Float
    /// How dark the "curtain" behind the viewer is: polished faces read as black mirrors with highlights.
    let curtain: Float
    let exposure: Float
    let bloom: Float

    // Case, bezel, crystal.
    let caseMetal: Surface
    let bezelBody: Surface
    let ringBody: Surface
    let ringWall: Surface
    let crystalTint: SIMD3<Float>

    // Movement.
    let plate: Surface
    let wheel: Surface
    let wheelPlain: Surface
    let wheelDone: Surface
    let barrel: Surface
    let mainspring: Surface
    let bridge: Surface
    let bridgeBevel: SIMD3<Float>
    let screw: Surface
    let screwSlot: Surface
    let chaton: Surface
    let hairspring: Surface
    let balance: Surface
    let fork: Surface

    // Jewels and glows.
    let ruby: SIMD3<Float>
    let rubyGlow: SIMD3<Float>
    let doneGlow: SIMD3<Float>
    let selection: SIMD3<Float>

    // Hands.
    let hand: Surface
    let lume: SIMD3<Float>
    let lumeGain: Float
    let dayArrow: Surface
    let dayArrowGlow: Float
    let seconds: Surface
    let secondsTip: SIMD3<Float>
    let cap: Surface
    let capDot: Surface

    // Strap and bracelet.
    let leather: Surface
    let braceletSatin: Surface
    let braceletPolished: Surface
}

extension WatchPalette {
    var materials: WatchMaterialTokens { isDark ? .dark : .light }
}

extension WatchMaterialTokens {
    private static func surface(
        _ hex: UInt32, _ metallic: Float, _ roughness: Float, coat: Float = 0
    ) -> Surface {
        Surface(color: SIMD3<Float>(hex: hex), metallic: metallic, roughness: roughness, clearcoat: coat)
    }

    /// Gunmetal case, black ceramic bezel, chrome hands with cyan lume.
    static let dark = WatchMaterialTokens(
        envTint: SIMD3<Float>(0.92, 0.97, 1.08),
        envGain: 1,
        keyColor: SIMD3<Float>(1.0, 0.97, 0.93),
        keyGain: 3.4,
        curtain: 0.4,
        exposure: 1.25,
        bloom: 0.55,
        caseMetal: surface(0x6A717B, 1, 0.17),
        bezelBody: surface(0x0B0C0F, 0, 0.34, coat: 1),
        ringBody: surface(0x07080A, 0, 0.42, coat: 0.7),
        ringWall: surface(0x8C95A0, 1, 0.2),
        crystalTint: SIMD3<Float>(hex: 0xC9D8FF),
        plate: surface(0x4A525C, 1, 0.45),
        wheel: surface(0x929BA6, 1, 0.24),
        wheelPlain: surface(0x6C747E, 1, 0.34),
        wheelDone: surface(0xE2ECF6, 1, 0.045),
        barrel: surface(0x555C66, 1, 0.3),
        mainspring: surface(0x8C95A0, 1, 0.22),
        bridge: surface(0x7A818B, 1, 0.3),
        bridgeBevel: SIMD3<Float>(hex: 0xE1E6EC),
        screw: surface(0xC9D0D8, 1, 0.12),
        screwSlot: surface(0x0A0B0D, 0, 0.6),
        chaton: surface(0xB8C0C9, 1, 0.1),
        hairspring: surface(0xEEF3F8, 1, 0.14),
        balance: surface(0xA8B0BA, 1, 0.16),
        fork: surface(0x9AA3AE, 1, 0.2),
        ruby: SIMD3<Float>(hex: 0xC8102F),
        rubyGlow: SIMD3<Float>(hex: 0xFF9FB0),
        doneGlow: SIMD3<Float>(hex: 0xA8F0FF),
        selection: SIMD3<Float>(hex: 0xA8F0FF),
        hand: surface(0xE4E9EF, 1, 0.07),
        lume: SIMD3<Float>(hex: 0xA8F0FF),
        lumeGain: 2.6,
        dayArrow: surface(0xA78BFA, 0.3, 0.34),
        dayArrowGlow: 0.55,
        seconds: surface(0xE8EDF2, 1, 0.1),
        secondsTip: SIMD3<Float>(hex: 0xFF4D5E),
        cap: surface(0xD9DEE4, 1, 0.08),
        capDot: surface(0xA78BFA, 0.4, 0.3),
        leather: surface(0x16191D, 0, 0.6),
        braceletSatin: surface(0x6A717B, 1, 0.4),
        braceletPolished: surface(0xB6BDC6, 1, 0.1)
    )

    /// Yellow gold case, ivory Roman ring, blued steel hands, leather strap.
    static let light = WatchMaterialTokens(
        envTint: SIMD3<Float>(1.08, 1.0, 0.86),
        envGain: 1,
        keyColor: SIMD3<Float>(1.0, 0.95, 0.86),
        keyGain: 3.0,
        curtain: 0.2,
        exposure: 1.05,
        bloom: 0.3,
        caseMetal: surface(0xE8BE58, 1, 0.16),
        bezelBody: surface(0xE6D5AE, 0, 0.4, coat: 0.55),
        ringBody: surface(0xE4D3AC, 0, 0.45, coat: 0.4),
        ringWall: surface(0xDDB766, 1, 0.2),
        crystalTint: SIMD3<Float>(hex: 0xFFF1D0),
        plate: surface(0xB98F3E, 1, 0.4),
        wheel: surface(0xE0B24C, 1, 0.24),
        wheelPlain: surface(0xB88B3A, 1, 0.34),
        wheelDone: surface(0xFFE7B0, 1, 0.045),
        barrel: surface(0x9A7431, 1, 0.3),
        mainspring: surface(0x6A5530, 1, 0.24),
        bridge: surface(0xCDA554, 1, 0.3),
        bridgeBevel: SIMD3<Float>(hex: 0xFFF8DF),
        screw: surface(0x2B4E9E, 1, 0.14),
        screwSlot: surface(0x10162A, 0, 0.6),
        chaton: surface(0xE8D196, 1, 0.1),
        hairspring: surface(0x2B4E9E, 1, 0.14),
        balance: surface(0xDDB766, 1, 0.16),
        fork: surface(0xCDA554, 1, 0.2),
        ruby: SIMD3<Float>(hex: 0xC8102F),
        rubyGlow: SIMD3<Float>(hex: 0xFF9FB0),
        doneGlow: SIMD3<Float>(hex: 0xFFE08A),
        selection: SIMD3<Float>(hex: 0xFF4D6A),
        hand: surface(0x2A4690, 1, 0.1),
        lume: SIMD3<Float>(hex: 0x3D6AD0),
        lumeGain: 0,
        dayArrow: surface(0x8E1B2A, 0.3, 0.34),
        dayArrowGlow: 0,
        seconds: surface(0x1E3A7A, 1, 0.12),
        secondsTip: SIMD3<Float>(hex: 0x1E3A7A),
        cap: surface(0xE9CF86, 1, 0.08),
        capDot: surface(0x1E3A7A, 0.6, 0.2),
        leather: surface(0x4A2814, 0, 0.55),
        braceletSatin: surface(0xDDB766, 1, 0.38),
        braceletPolished: surface(0xF5DC96, 1, 0.1)
    )
}
