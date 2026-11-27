import SwiftUI

/// The scrolling home screen.
struct MainScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
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

                ProgressSection()
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.top, 14)

                if model.layout == .playTheDay {
                    PlayTheDaySection()
                        .padding(.top, 18)
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
        .animation(model.animated(Motion.theme), value: model.layout)
    }
}
