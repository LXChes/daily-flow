import Foundation
import Observation

/// Where the belt and the clock are showing. Live follows the real time; dragging or scrubbing holds a
/// chosen minute; Play runs the day forward from a minute. Stored as the rule to compute from, not as a
/// value that has to be updated every frame, so playback costs the model nothing.
@MainActor
@Observable
final class Playhead {
    enum Mode: Equatable {
        case live
        case held(Double)
        case playing(from: Double, since: Date)

        var isPlaying: Bool {
            if case .playing = self { return true }
            return false
        }

        var isHeld: Bool {
            if case .held = self { return true }
            return false
        }
    }

    /// Minutes of the day that pass per real second while playing.
    static let playSpeed: Double = 66

    private(set) var mode: Mode = .live
    /// Changes at every Play press so the end-of-day timer restarts.
    private(set) var playToken = 0

    var isLive: Bool { mode == .live }
    var isPlaying: Bool { mode.isPlaying }

    func hold(at minute: Double) {
        mode = .held(minute)
    }

    func goLive() {
        mode = .live
    }

    func togglePlay(from minute: Double, range: ClosedRange<Double>) {
        if mode.isPlaying {
            mode = .held(minute)
            return
        }
        let start = minute >= range.upperBound - 1 ? range.lowerBound : minute
        mode = .playing(from: start, since: Date())
        playToken &+= 1
    }

    /// Called when playback reaches the end of the belt.
    func finishPlaying(at minute: Double) {
        if mode.isPlaying {
            mode = .held(minute)
        }
    }

    /// The minute to show at `date`. `live` is only evaluated in live mode.
    static func minute(mode: Mode, at date: Date, live: () -> Double, range: ClosedRange<Double>) -> Double {
        let raw: Double
        switch mode {
        case .live:
            raw = live()
        case .held(let minute):
            raw = minute
        case .playing(let from, let since):
            raw = from + date.timeIntervalSince(since) * playSpeed
        }
        return min(max(raw, range.lowerBound), range.upperBound)
    }
}
