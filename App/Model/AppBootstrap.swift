import DailyFlowCore
import SwiftData

/// Builds the model the app runs on: the on-device store and the real clock. DEBUG builds can instead
/// start in a seeded, fixed-clock demo mode for screenshots (see `DemoSupport`).
@MainActor
enum AppBootstrap {
    /// The one model, shared by the scene and the notification delegate (which can run with no scene,
    /// when a Lock Screen button launches the app in the background).
    static let shared: AppModel = makeModel()

    private static func makeModel() -> AppModel {
        #if DEBUG
        if let demo = DemoSupport.makeModel() {
            return demo
        }
        #endif
        let store = DailyFlowStore.makeContainerWithFallback()
        return AppModel(container: store.container, isTemporaryStore: store.isTemporary, clock: .live, outputs: DeviceOutputs())
    }
}
