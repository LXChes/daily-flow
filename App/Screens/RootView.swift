import SwiftUI
import Combine
import UIKit

/// The whole app: backdrop, home screen, view switcher, toast and the sheets.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        let palette = model.palette

        ZStack {
            Backdrop()
            MainScreen()
            ViewSwitcherOverlay()
            ToastHost()
                .padding(.bottom, 8)
        }
        .environment(\.palette, palette)
        .preferredColorScheme(model.theme.colorScheme)
        .animation(model.animated(Motion.theme), value: model.theme)
        .sheet(item: $model.sheet) { sheet in
            SheetContent(sheet: sheet)
                .environment(\.palette, palette)
                .preferredColorScheme(model.theme.colorScheme)
        }
        .sensoryFeedback(trigger: model.tickPulse) { _, _ in
            model.settings.hapticTickEnabled ? .success : nil
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            if phase == .active {
                model.reload()
                Task { await model.refreshReminderAccess() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: DispatchQueue.main)) { _ in
            model.reload()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)
                .receive(on: DispatchQueue.main)
        ) { _ in
            model.reload()
        }
    }
}

/// Flat colour with a faint cool glow at the top edge.
private struct Backdrop: View {
    @Environment(\.palette) private var palette

    var body: some View {
        ZStack {
            palette.background
            LinearGradient(colors: [palette.ambient, .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

private struct SheetContent: View {
    let sheet: AppSheet

    var body: some View {
        switch sheet {
        case .add: AddTaskSheet()
        case .settings: SettingsSheet()
        case .triage: TriageSheet()
        }
    }
}
