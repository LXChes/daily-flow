import DailyFlowCore
import SwiftUI

@main
struct DailyFlowApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        // Registers the bundled Syne and Inter fonts before the first view draws.
        _ = FontRegistry.availability
        _model = State(initialValue: AppBootstrap.shared)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}
