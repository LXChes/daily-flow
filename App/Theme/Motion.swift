import SwiftUI

/// Named springs. Everything animates transform and opacity with one of these, so the app moves as one
/// instrument. With Reduce Motion on, `resolve` swaps in a short ease instead of any spring.
enum Motion {
    /// Quick press feedback.
    static let press = Animation.snappy(duration: 0.22, extraBounce: 0)
    /// Rows moving, cards appearing, chips sliding.
    static let settle = Animation.snappy(duration: 0.42, extraBounce: 0.1)
    /// Ticks and switches: a little overshoot.
    static let tick = Animation.bouncy(duration: 0.42, extraBounce: 0.25)
    /// Sheets and drop-downs.
    static let sheet = Animation.snappy(duration: 0.5, extraBounce: 0.06)
    /// Theme and layout swaps.
    static let theme = Animation.smooth(duration: 0.45)
    /// The Reduce Motion alternative to all of the above.
    static let calm = Animation.easeInOut(duration: 0.2)

    static func resolve(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? calm : animation
    }
}

enum Metrics {
    /// Side margin of the main screen.
    static let gutter: CGFloat = 18
    /// Smallest comfortable touch target.
    static let hit: CGFloat = 44
}
