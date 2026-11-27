import DailyFlowCore
import SwiftUI

// The one colour-token file. Every colour in the app comes from here: views never write hex or
// reach for named system colours. Dark is "gothic liquid chrome", light is "vintage".

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

/// Immutable value type: every field is a `let`, so sharing it across threads is safe.
struct Palette: @unchecked Sendable {
    let isDark: Bool

    // Surfaces
    let background: Color
    let ambient: Color
    let card: Color
    let control: Color
    let sheet: Color
    let sheetCard: Color
    let chip: Color
    let scrim: Color

    // Ink and rules
    let ink: Color
    let inkSecondary: Color
    let line: Color
    let sheetLine: Color
    let tickLine: Color

    // Accent and alerts
    let accent: Color
    let accentSoft: Color
    let onAccent: Color
    let urgent: Color
    let urgentTint: Color

    // Belt and wave
    let waveLit: Color
    let waveDim: Color
    let block: Color
    let blockBorder: Color
    let blockDone: Color
    let nowGlow: Color

    // Toast and switches
    let toastBackground: Color
    let toastInk: Color
    let switchOff: Color
    let knob: Color

    // Metals
    /// Vertical polished-steel gradient for display type and numerals.
    let chrome: LinearGradient
    /// Face of the "now" block on the belt, and the scrub knob.
    let slab: LinearGradient
    let slabInk: Color
    /// One-point highlight edge on controls and cards.
    let bevel: LinearGradient

    func category(_ category: TaskCategory) -> Color {
        Palette.categoryColor(category)
    }
}

extension Palette {
    // MARK: Colours shared by both themes

    /// Per-category colours, used by the Sorted mode.
    static func categoryColor(_ category: TaskCategory) -> Color {
        switch category {
        case .uni: Color(hex: 0x5B8CFF)
        case .health: Color(hex: 0x1FC7A6)
        case .career: Color(hex: 0xFF8A4C)
        case .errands: Color(hex: 0xF2B33D)
        case .home: Color(hex: 0xA77BFF)
        case .social: Color(hex: 0xFF6FA8)
        case .other: Color(hex: 0x8A94A6)
        }
    }

    /// Cyan, violet, pink: the iridescent sweep. First and last match so the loop is seamless.
    static let iridescentLoop: [Color] = [
        Color(hex: 0x7DF9FF), Color(hex: 0xA78BFA), Color(hex: 0xF0ABFC),
        Color(hex: 0x7DF9FF), Color(hex: 0xA78BFA), Color(hex: 0xF0ABFC), Color(hex: 0x7DF9FF)
    ]
    static let iridescentStatic: [Color] = [Color(hex: 0x7DF9FF), Color(hex: 0xA78BFA), Color(hex: 0xF0ABFC)]
    /// Text on the iridescent banner and bar.
    static let onIridescent = Color(hex: 0x0B0A18)

    static func `for`(_ theme: ThemeMode) -> Palette {
        switch theme {
        case .dark: .dark
        case .light: .light
        }
    }

    // MARK: Dark: gothic liquid chrome

    static let dark = Palette(
        isDark: true,
        background: Color(hex: 0x050608),
        ambient: Color(hex: 0xA78BFA, opacity: 0.10),
        card: Color(hex: 0x0E1014),
        control: Color(hex: 0x16191E),
        sheet: Color(hex: 0x13151A),
        sheetCard: Color(hex: 0x1A1D23),
        chip: Color(hex: 0x24272F),
        scrim: Color(hex: 0x05080E, opacity: 0.55),
        ink: Color(hex: 0xF2F4F7),
        inkSecondary: Color(hex: 0x8D96A2),
        line: Color(hex: 0x1C2027),
        sheetLine: Color(hex: 0x262A32),
        tickLine: Color(hex: 0x3A414B),
        accent: Color(hex: 0xA78BFA),
        accentSoft: Color(hex: 0xA78BFA, opacity: 0.14),
        onAccent: Color(hex: 0x140A2E),
        urgent: Color(hex: 0xFF5A8A),
        urgentTint: Color(hex: 0xFF5A8A, opacity: 0.08),
        waveLit: Color(hex: 0x4A4F5E),
        waveDim: Color(hex: 0x1E2229),
        block: Color(hex: 0x14171C),
        blockBorder: Color(hex: 0x262B33),
        blockDone: Color(hex: 0x1A1530),
        nowGlow: Color(hex: 0xA78BFA, opacity: 0.5),
        toastBackground: Color(hex: 0xF2F4F7),
        toastInk: Color(hex: 0x050608),
        switchOff: Color(hex: 0x3A3E48),
        knob: Color(hex: 0xFFFFFF),
        chrome: LinearGradient(
            stops: [
                .init(color: Color(hex: 0xFFFFFF), location: 0),
                .init(color: Color(hex: 0xC9D1DA), location: 0.35),
                .init(color: Color(hex: 0x5E6773), location: 0.50),
                .init(color: Color(hex: 0xE6EBF0), location: 0.62),
                .init(color: Color(hex: 0x9AA4AF), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        ),
        slab: LinearGradient(
            stops: [
                .init(color: Color(hex: 0xF7F9FB), location: 0),
                .init(color: Color(hex: 0xDCE2E9), location: 0.48),
                .init(color: Color(hex: 0xB4BDC8), location: 0.52),
                .init(color: Color(hex: 0xEEF1F5), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        ),
        slabInk: Color(hex: 0x050608),
        bevel: LinearGradient(
            colors: [Color(hex: 0xFFFFFF, opacity: 0.22), Color(hex: 0xFFFFFF, opacity: 0.02)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )

    // MARK: Light: vintage

    static let light = Palette(
        isDark: false,
        background: Color(hex: 0xEEF0F3),
        ambient: Color(hex: 0x7C5CF0, opacity: 0.07),
        card: Color(hex: 0xFFFFFF),
        control: Color(hex: 0xDDE1E6),
        sheet: Color(hex: 0xF4F5F8),
        sheetCard: Color(hex: 0xFFFFFF),
        chip: Color(hex: 0xE9ECF1),
        scrim: Color(hex: 0x05080E, opacity: 0.40),
        ink: Color(hex: 0x0C0F14),
        inkSecondary: Color(hex: 0x59626E),
        line: Color(hex: 0xD7DCE2),
        sheetLine: Color(hex: 0xE1E5EB),
        tickLine: Color(hex: 0xADB5BF),
        accent: Color(hex: 0x7C5CF0),
        accentSoft: Color(hex: 0x7C5CF0, opacity: 0.10),
        onAccent: Color(hex: 0xFFFFFF),
        urgent: Color(hex: 0xE0306A),
        urgentTint: Color(hex: 0xE0306A, opacity: 0.06),
        waveLit: Color(hex: 0xA9B0BB),
        waveDim: Color(hex: 0xD5DAE0),
        block: Color(hex: 0xFFFFFF),
        blockBorder: Color(hex: 0xD7DCE2),
        blockDone: Color(hex: 0xEDE8FF),
        nowGlow: Color(hex: 0x7C5CF0, opacity: 0.35),
        toastBackground: Color(hex: 0x0C0F14),
        toastInk: Color(hex: 0xFFFFFF),
        switchOff: Color(hex: 0xC9D0DA),
        knob: Color(hex: 0xFFFFFF),
        chrome: LinearGradient(
            stops: [
                .init(color: Color(hex: 0x5E6773), location: 0),
                .init(color: Color(hex: 0x1A1F26), location: 0.45),
                .init(color: Color(hex: 0x8A94A0), location: 0.55),
                .init(color: Color(hex: 0x2A3038), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        ),
        slab: LinearGradient(
            stops: [
                .init(color: Color(hex: 0x3A424D), location: 0),
                .init(color: Color(hex: 0x161A20), location: 0.48),
                .init(color: Color(hex: 0x0C0F14), location: 0.52),
                .init(color: Color(hex: 0x262C34), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        ),
        slabInk: Color(hex: 0xF4F6F8),
        bevel: LinearGradient(
            colors: [Color(hex: 0xFFFFFF, opacity: 0.95), Color(hex: 0x0C0F14, opacity: 0.06)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )
}

extension EnvironmentValues {
    @Entry var palette: Palette = .dark
}

extension ThemeMode {
    var colorScheme: ColorScheme {
        switch self {
        case .dark: .dark
        case .light: .light
        }
    }
}
