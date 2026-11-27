import CoreText
import OSLog
import SwiftUI
import UIKit

/// Registers the bundled Syne and Inter variable fonts with CoreText at launch (no Info.plist entry
/// needed) and reports whether each family is usable. If registration fails the text styles fall back
/// to the system font, so the app is never blank.
enum FontRegistry {
    private static let logger = Logger(subsystem: "com.example.dailyflow", category: "fonts")
    private static let files = ["Syne-Variable", "Inter-Variable"]

    /// Registered the first time it is read; `DailyFlowApp` reads it at launch.
    static let availability: (syne: Bool, inter: Bool) = {
        for name in files {
            register(name)
        }
        return (
            syne: !UIFont.fontNames(forFamilyName: "Syne").isEmpty,
            inter: !UIFont.fontNames(forFamilyName: "Inter").isEmpty
        )
    }()

    private static func register(_ name: String) {
        let url = Bundle.main.url(forResource: name, withExtension: "ttf")
            ?? Bundle.main.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
        guard let url else {
            logger.error("Font file not found in the bundle: \(name, privacy: .public)")
            return
        }
        var error: Unmanaged<CFError>?
        if !CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error) {
            let reason = error.map { String(describing: $0.takeRetainedValue()) } ?? "unknown"
            logger.error("Could not register \(name, privacy: .public): \(reason, privacy: .public)")
        }
    }
}

enum DFFamily: Sendable {
    /// Display face: wide, sharp, used for the wordmark, numerals and headings.
    case syne
    /// Working face: rows, labels and controls.
    case inter
}

/// The bespoke type hierarchy. Every size scales with Dynamic Type relative to a system text style.
struct DFTextStyle: @unchecked Sendable {
    let family: DFFamily
    let size: CGFloat
    let weight: Font.Weight
    let relativeTo: Font.TextStyle
    var tracking: CGFloat = 0

    var font: Font {
        let available = FontRegistry.availability
        switch family {
        case .syne where available.syne:
            return .custom("Syne", size: size, relativeTo: relativeTo).weight(weight)
        case .inter where available.inter:
            return .custom("Inter", size: size, relativeTo: relativeTo).weight(weight)
        case .syne:
            return .system(relativeTo, design: .default).weight(weight)
        case .inter:
            return .system(relativeTo, design: .default).weight(weight)
        }
    }

    /// A fixed-size version, for numerals scaled with `@ScaledMetric` so the layout can cap their growth.
    func font(fixedSize points: CGFloat) -> Font {
        let available = FontRegistry.availability
        switch family {
        case .syne where available.syne:
            return .custom("Syne", fixedSize: points).weight(weight)
        case .inter where available.inter:
            return .custom("Inter", fixedSize: points).weight(weight)
        default:
            return .system(size: points, weight: weight, design: .default)
        }
    }
}

extension DFTextStyle {
    // Display: Syne. Heavy (800) is very wide, so it is kept for short words and numerals.
    static let wordmark = DFTextStyle(family: .syne, size: 52, weight: .heavy, relativeTo: .largeTitle, tracking: -2)
    static let clock = DFTextStyle(family: .syne, size: 76, weight: .bold, relativeTo: .largeTitle)
    static let numeral = DFTextStyle(family: .syne, size: 72, weight: .heavy, relativeTo: .largeTitle, tracking: -3)
    static let sheetTitle = DFTextStyle(family: .syne, size: 30, weight: .bold, relativeTo: .title, tracking: -0.6)
    static let heading = DFTextStyle(family: .syne, size: 20, weight: .bold, relativeTo: .title3)
    static let cardTitle = DFTextStyle(family: .syne, size: 15, weight: .bold, relativeTo: .subheadline)
    static let ringValue = DFTextStyle(family: .syne, size: 20, weight: .bold, relativeTo: .title3)
    static let overline = DFTextStyle(family: .syne, size: 12, weight: .heavy, relativeTo: .caption, tracking: 1.3)

    // Working text: Inter.
    static let rowTitle = DFTextStyle(family: .inter, size: 17, weight: .semibold, relativeTo: .body)
    static let body = DFTextStyle(family: .inter, size: 15, weight: .medium, relativeTo: .subheadline)
    static let bodyStrong = DFTextStyle(family: .inter, size: 15, weight: .bold, relativeTo: .subheadline)
    static let control = DFTextStyle(family: .inter, size: 14, weight: .bold, relativeTo: .subheadline)
    static let label = DFTextStyle(family: .inter, size: 13, weight: .regular, relativeTo: .footnote)
    static let caption = DFTextStyle(family: .inter, size: 12, weight: .regular, relativeTo: .caption)
    static let captionStrong = DFTextStyle(family: .inter, size: 12, weight: .semibold, relativeTo: .caption)
    static let micro = DFTextStyle(family: .inter, size: 11, weight: .semibold, relativeTo: .caption2)
    static let badge = DFTextStyle(family: .inter, size: 10, weight: .heavy, relativeTo: .caption2, tracking: 0.6)
}

extension Text {
    func dfStyle(_ style: DFTextStyle) -> Text {
        font(style.font).tracking(style.tracking)
    }
}

extension View {
    /// For controls that are not `Text` (text fields, for example).
    func dfFont(_ style: DFTextStyle) -> some View {
        font(style.font)
    }
}
