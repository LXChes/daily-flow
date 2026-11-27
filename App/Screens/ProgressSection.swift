import DailyFlowCore
import SwiftUI

/// Today's progress in the owner's chosen style: Wave, Ring, Bar or Number.
struct ProgressSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette

    var body: some View {
        let progress = model.progress
        Group {
            switch model.settings.progressStyle {
            case .wave:
                WaveProgress(progress: progress)
            case .ring:
                RingProgress(progress: progress)
            case .bar:
                BarProgress(progress: progress)
            case .number:
                NumberProgress(progress: progress)
            }
        }
        .id(model.settings.progressStyle)
        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
        .animation(model.animated(Motion.settle), value: model.settings.progressStyle)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            progress.total == 0
                ? "Nothing planned today"
                : "\(progress.done) of \(progress.total) done, \(progress.percent) percent"
        )
    }
}

/// "3 of 9 done" and the percentage, shared by the Wave and the Bar.
private struct CountLine: View {
    @Environment(\.palette) private var palette
    let progress: DayProgress

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("\(progress.done) of \(progress.total)")
                .dfStyle(.bodyStrong)
                .foregroundStyle(palette.ink)
                .contentTransition(.numericText())
            Text("done")
                .dfStyle(.label)
                .foregroundStyle(palette.inkSecondary)
            Spacer()
            Text("\(progress.percent)%")
                .dfStyle(.label)
                .foregroundStyle(palette.inkSecondary)
                .contentTransition(.numericText())
        }
    }
}

// MARK: Wave

struct WaveProgress: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let progress: DayProgress

    private let height: CGFloat = 44

    var body: some View {
        VStack(spacing: 6) {
            CountLine(progress: progress)
            PlayheadReader { minute in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(model.waveBars) { bar in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(color(for: bar, minute: minute))
                            .frame(height: max(3, height * bar.height))
                    }
                }
                .frame(height: height, alignment: .bottom)
                .animation(model.animated(Motion.settle), value: model.waveBars)
            }
        }
    }

    /// Done tasks light up in the accent (or their category). Time already passed is mid-grey, time to
    /// come is dim, and the bar under the playhead glows.
    private func color(for bar: WaveBar, minute: Double) -> Color {
        let step = (model.beltRange.upperBound - model.beltRange.lowerBound) / Double(WaveModel.barCount)
        if abs(bar.midMinute - minute) <= step / 2 {
            return palette.ink
        }
        if bar.isInsideDoneTask {
            if model.isSorted, let category = bar.category {
                return palette.category(category)
            }
            return palette.accent
        }
        return bar.midMinute <= minute ? palette.waveLit : palette.waveDim
    }
}

// MARK: Ring

struct RingProgress: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let progress: DayProgress

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().stroke(palette.line, lineWidth: 9)
                Circle()
                    .trim(from: 0, to: progress.fraction)
                    .stroke(palette.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(model.animated(Motion.tick), value: progress.fraction)
                Text("\(progress.done)/\(progress.total)")
                    .dfStyle(.ringValue)
                    .foregroundStyle(palette.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .contentTransition(.numericText())
            }
            .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(progress.percent)% of today done")
                    .dfStyle(.body)
                    .foregroundStyle(palette.inkSecondary)
                Text("Next: \(model.nextOpenLine)")
                    .dfStyle(.bodyStrong)
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Bar

struct BarProgress: View {
    @Environment(AppModel.self) private var model
    @Environment(\.palette) private var palette
    let progress: DayProgress

    var body: some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(palette.line)
                .frame(height: 10)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        IridescentFill()
                            .frame(width: max(0, proxy.size.width * progress.fraction))
                            .clipShape(Capsule())
                            .animation(model.animated(Motion.tick), value: progress.fraction)
                    }
                }
            CountLine(progress: progress)
        }
    }
}

// MARK: Number

struct NumberProgress: View {
    @Environment(\.palette) private var palette
    let progress: DayProgress

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ChromeText(text: "\(progress.total - progress.done)", style: .numeral)
                .contentTransition(.numericText())
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            Text("left today \u{00B7} \(progress.done) done")
                .dfStyle(.body)
                .foregroundStyle(palette.inkSecondary)
        }
    }
}
