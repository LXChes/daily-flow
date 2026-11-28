import SwiftUI
import WidgetKit

@main
struct DailyFlowWidgetBundle: WidgetBundle {
    init() {
        // The extension has its own bundle: register its copy of Syne and Inter before anything draws.
        _ = FontRegistry.availability
    }

    var body: some Widget {
        UpNextWidget()
        ProgressRingWidget()
        DoneRingWidget()
        WaveWidget()
        DayDialWidget()
        TodayLineWidget()
    }
}
