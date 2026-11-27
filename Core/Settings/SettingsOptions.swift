import Foundation

/// Visual style for each widget (chosen per widget in M4, defaulted here).
public enum WidgetStyle: String, CaseIterable, Codable, Sendable {
    case matchApp, darkChrome, lightVintage

    public var title: String {
        switch self {
        case .matchApp: "Match app"
        case .darkChrome: "Dark chrome"
        case .lightVintage: "Light vintage"
        }
    }
}

public enum LayoutMode: String, CaseIterable, Codable, Sendable {
    case playTheDay, list, watch

    public var title: String {
        switch self {
        case .playTheDay: "Play the day"
        case .list: "List"
        case .watch: "Watch"
        }
    }
}

public enum CategoryMode: String, CaseIterable, Codable, Sendable {
    case simple, sorted

    public var title: String {
        switch self {
        case .simple: "Simple"
        case .sorted: "Sorted"
        }
    }
}

public enum ThemeMode: String, CaseIterable, Codable, Sendable {
    case dark, light

    public var title: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        }
    }
}

public enum ProgressStyle: String, CaseIterable, Codable, Sendable {
    case wave, ring, bar, number

    public var title: String {
        switch self {
        case .wave: "Wave"
        case .ring: "Ring"
        case .bar: "Bar"
        case .number: "Number"
        }
    }
}

/// Fixed choices and defaults for reminder timing.
public enum ReminderTiming {
    /// How long before a timed urgent task its reminder fires.
    public static let leadTimeChoices = [15, 30, 60]
    public static let defaultLeadMinutes = 30
    /// When an urgent task with no time is reminded, in minutes after midnight (09:00).
    public static let defaultUntimedMinute = 9 * 60
    /// Morning brief time, in minutes after midnight (08:00).
    public static let defaultMorningBriefMinute = 8 * 60
}
