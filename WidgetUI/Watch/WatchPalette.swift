import DailyFlowCore
import SwiftUI

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
