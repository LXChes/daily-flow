import SwiftUI

/// The scrolling home screen.
struct MainScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    /// Scroll anchor of the watch, so the demo can bring it on screen.
    private static let watchID = "watch"

    var body: some View {
        ScrollViewReader { proxy in
            content
                .task {
                    #if DEBUG
                    // Demo scenes `watch` and `watch-light`: show the whole watch on launch.
                    if DemoSupport.revealsWatch {
                        try? await Task.sleep(for: .milliseconds(700))
                        proxy.scrollTo(MainScreen.watchID, anchor: .top)
                    }
                    #endif
                }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HeaderView()
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 6)

                if model.isTemporaryStore {
                    Text("Temporary storage \u{00B7} changes won\u{2019}t be kept")
                        .dfStyle(.captionStrong)
                        .foregroundStyle(palette.urgent)
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 10)
                }

                if model.showsBanner {
                    NoticeBanner()
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if model.showsLeftoversCard {
                    LeftoversCard()
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                if model.showsReminderPrompt {
                    ReminderCard()
                        .padding(.horizontal, Metrics.gutter)
                        .padding(.top, 14)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                ProgressSection()
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 14)

                if model.layout == .playTheDay {
                    PlayTheDaySection()
                        .padding(.top, 18)
                        .transition(.opacity)
                }

                if model.layout == .watch {
                    WatchSection()
                        .padding(.top, 18)
                        .id(MainScreen.watchID)
                        .transition(.opacity)
                }

                TodaySection()
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 22)
                    .padding(.bottom, 60)
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .animation(model.animated(Motion.settle), value: model.showsBanner)
        .animation(model.animated(Motion.settle), value: model.showsLeftoversCard)
        .animation(model.animated(Motion.settle), value: model.showsReminderPrompt)
        .animation(model.animated(Motion.theme), value: model.layout)
    }
}
