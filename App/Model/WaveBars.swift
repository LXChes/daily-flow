import DailyFlowCore
import Foundation

/// One bar of the Wave progress view.
struct WaveBar: Equatable, Identifiable {
    let id: Int
    /// 0...1 of the tallest bar.
    let height: Double
    /// Middle of the slice of day this bar stands for, in minutes after midnight.
    let midMinute: Double
    /// Inside a task that is ticked off.
    let isInsideDoneTask: Bool
    /// Category of the task the bar sits in, if any.
    let category: TaskCategory?
}

/// Builds the Wave: a gentle ripple that rises where timed tasks sit. Pure and computed once per change,
/// never per frame; the view only decides each bar's colour from the playhead.
enum WaveModel {
    static let barCount = 48
    private static let tallest = 44.0
    private static let reachMinutes = 36.0

    static func bars(items: [TaskItem], range: ClosedRange<Double>) -> [WaveBar] {
        let step = (range.upperBound - range.lowerBound) / Double(barCount)
        return (0..<barCount).map { index in
            let mid = range.lowerBound + (Double(index) + 0.5) * step
            var height = 7 + 5 * abs(sin(Double(index) * 1.7)) + 3 * abs(sin(Double(index) * 0.41))
            var inside: TaskItem?
            for item in items {
                guard let startMinute = item.startMinute, let endMinute = item.endMinute, endMinute > startMinute else {
                    continue
                }
                let start = Double(startMinute)
                let end = Double(endMinute)
                if mid >= start && mid < end {
                    inside = item
                    height += 24 + 8 * sin((mid - start) / (end - start) * Double.pi)
                } else {
                    let distance = min(abs(mid - start), abs(mid - end))
                    if distance < reachMinutes {
                        height += (reachMinutes - distance) / 60 * 16
                    }
                }
            }
            return WaveBar(
                id: index,
                height: min(tallest, height) / tallest,
                midMinute: mid,
                isInsideDoneTask: inside?.isDone ?? false,
                category: inside?.category
            )
        }
    }
}
