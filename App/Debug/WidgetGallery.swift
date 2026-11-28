#if DEBUG
import DailyFlowCore
import SwiftUI
import WidgetKit

/// Screenshot support, compiled out of Release builds.
///
/// Lays the real widget faces out at real point sizes on a wallpaper-like backdrop, with the same clipping
/// the system applies, so CI can photograph them. Scenes (`-DFScene <name>`):
/// widgets, widgets-light, widgets-lock, widgets-basic. Each fits one iPhone portrait screen.
struct WidgetGallery: View {
    let scene: String

    var body: some View {
        let data = GalleryData.load()
        switch scene {
        case "widgets-light":
            HomeScene(theme: .light, title: "Home Screen \u{00B7} Light", data: data)
        case "widgets-lock":
            LockScene(data: data)
        case "widgets-basic":
            BasicScene(data: data)
        default:
            HomeScene(theme: .dark, title: "Home Screen \u{00B7} Dark", data: data)
        }
    }
}

// MARK: Data

/// The seeded demo day exactly as the widgets receive it, or the neutral samples if the demo is not running.
private struct GalleryData {
    let snapshot: DaySnapshot
    let now: Date
    let calendar: Calendar

    @MainActor
    static func load() -> GalleryData {
        if let demo = AppBootstrap.shared.demoWidgetSnapshot() {
            return GalleryData(snapshot: demo.snapshot, now: demo.now, calendar: demo.calendar)
        }
        let calendar = Calendar.current
        let now = Date.now
        return GalleryData(snapshot: WidgetSamples.day(now: now, calendar: calendar), now: now, calendar: calendar)
    }

    var minute: Int { MinuteOfDay.of(now, calendar: calendar) }

    func entry(theme: ThemeMode, snapshot override: DaySnapshot? = nil) -> DFWidgetEntry {
        DFWidgetEntry(
            date: now,
            day: WidgetDay(snapshot: override ?? snapshot, source: .shared),
            theme: theme,
            minute: minute
        )
    }

    /// No shared folder and no cached copy: what a free-sideload install shows before the app has run.
    func basicEntry(theme: ThemeMode) -> DFWidgetEntry {
        DFWidgetEntry(
            date: now,
            day: WidgetDataResolver.resolve(shared: nil, cached: nil, now: now, calendar: calendar),
            theme: theme,
            minute: minute
        )
    }

    /// The same day, marked as a notice day.
    func noticeSnapshot(_ title: String) -> DaySnapshot {
        DaySnapshot(
            generatedAt: snapshot.generatedAt,
            day: snapshot.day,
            tasks: snapshot.tasks,
            noticeTitles: [title],
            widgetStyle: snapshot.widgetStyle,
            theme: snapshot.theme
        )
    }
}

// MARK: Scenes

private struct HomeScene: View {
    let theme: ThemeMode
    let title: String
    let data: GalleryData

    var body: some View {
        let palette = Palette.for(theme)
        let entry = data.entry(theme: theme)
        ZStack {
            GalleryWallpaper(palette: palette)
            VStack(spacing: 14) {
                Text(title.uppercased())
                    .dfStyle(.overline)
                    .foregroundStyle(palette.inkSecondary)
                HStack(spacing: 23) {
                    GalleryWidget(kind: .progressRing, family: .systemSmall, mode: .fullColor, entry: entry,
                                  caption: "systemSmall \u{00B7} progressRing", wallpaper: palette)
                    GalleryWidget(kind: .doneRing, family: .systemSmall, mode: .fullColor, entry: entry,
                                  caption: "systemSmall \u{00B7} doneRing", wallpaper: palette)
                }
                GalleryWidget(kind: .wave, family: .systemMedium, mode: .fullColor, entry: entry,
                              caption: "systemMedium \u{00B7} wave", wallpaper: palette)
                GalleryWidget(kind: .dayDial, family: .systemMedium, mode: .fullColor, entry: entry,
                              caption: "systemMedium \u{00B7} dayDial (placeholder dial)", wallpaper: palette)
            }
        }
        .environment(\.palette, palette)
    }
}

private struct LockScene: View {
    let data: GalleryData

    var body: some View {
        let palette = Palette.dark
        let entry = data.entry(theme: .dark)
        let notice = data.entry(theme: .dark, snapshot: data.noticeSnapshot("Christmas Day"))
        ZStack {
            GalleryWallpaper(palette: palette)
            VStack(spacing: 10) {
                Text("LOCK SCREEN")
                    .dfStyle(.overline)
                    .foregroundStyle(palette.inkSecondary)
                GalleryWidget(kind: .todayLine, family: .accessoryInline, mode: .vibrant, entry: entry,
                              caption: "accessoryInline \u{00B7} todayLine", wallpaper: palette)
                ClockText(text: Fmt.clock(data.minute))
                HStack(spacing: 8) {
                    GalleryWidget(kind: .upNext, family: .accessoryRectangular, mode: .vibrant, entry: entry,
                                  caption: "accessoryRectangular \u{00B7} upNext", wallpaper: palette)
                    GalleryWidget(kind: .progressRing, family: .accessoryCircular, mode: .vibrant, entry: entry,
                                  caption: "circular \u{00B7} ring", wallpaper: palette)
                    GalleryWidget(kind: .dayDial, family: .accessoryCircular, mode: .vibrant, entry: entry,
                                  caption: "circular \u{00B7} dial", wallpaper: palette)
                }
                .padding(.top, 14)
                Spacer(minLength: 24)
                Text("ON A NOTICE DAY")
                    .dfStyle(.overline)
                    .foregroundStyle(palette.inkSecondary)
                GalleryWidget(kind: .todayLine, family: .accessoryInline, mode: .vibrant, entry: notice,
                              caption: "accessoryInline \u{00B7} todayLine", wallpaper: palette)
                GalleryWidget(kind: .upNext, family: .accessoryRectangular, mode: .vibrant, entry: notice,
                              caption: "accessoryRectangular \u{00B7} upNext", wallpaper: palette)
                Spacer(minLength: 24)
            }
            .padding(.top, 24)
        }
        .environment(\.palette, palette)
    }
}

private struct BasicScene: View {
    let data: GalleryData

    var body: some View {
        let palette = Palette.dark
        let entry = data.basicEntry(theme: .dark)
        ZStack {
            GalleryWallpaper(palette: palette)
            VStack(spacing: 14) {
                Text("BASIC MODE \u{00B7} NO TASK DATA")
                    .dfStyle(.overline)
                    .foregroundStyle(palette.inkSecondary)
                HStack(alignment: .center, spacing: 21) {
                    GalleryWidget(kind: .progressRing, family: .systemSmall, mode: .fullColor, entry: entry,
                                  caption: "systemSmall \u{00B7} progressRing", wallpaper: palette)
                    GalleryWidget(kind: .upNext, family: .accessoryRectangular, mode: .vibrant, entry: entry,
                                  caption: "accessoryRectangular \u{00B7} upNext", wallpaper: palette)
                }
                GalleryWidget(kind: .todayLine, family: .accessoryInline, mode: .vibrant, entry: entry,
                              caption: "accessoryInline \u{00B7} todayLine", wallpaper: palette)
                GalleryWidget(kind: .wave, family: .systemMedium, mode: .fullColor, entry: entry,
                              caption: "systemMedium \u{00B7} wave", wallpaper: palette)
                GalleryWidget(kind: .dayDial, family: .systemMedium, mode: .fullColor, entry: entry,
                              caption: "systemMedium \u{00B7} dayDial", wallpaper: palette)
            }
        }
        .environment(\.palette, palette)
    }
}

// MARK: Pieces

/// A wallpaper-like backdrop: a deep base with a cool glow and a faint iridescent wash.
private struct GalleryWallpaper: View {
    let palette: Palette

    var body: some View {
        ZStack {
            Rectangle().fill(palette.isDark ? palette.sheet : palette.control)
            RadialGradient(
                colors: [palette.accent.opacity(0.4), .clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 460
            )
            LinearGradient(
                colors: Palette.iridescentStatic.map { $0.opacity(0.2) },
                startPoint: .bottomLeading,
                endPoint: .topTrailing
            )
        }
        .ignoresSafeArea()
    }
}

/// One widget at its real size, clipped like the system clips it, with a tiny caption.
private struct GalleryWidget: View {
    let kind: DFWidgetKind
    let family: WidgetFamily
    let mode: WidgetRenderingMode
    let entry: DFWidgetEntry
    let caption: String
    let wallpaper: Palette

    private var size: CGSize {
        switch family {
        case .systemSmall: CGSize(width: 170, height: 170)
        case .systemMedium: CGSize(width: 364, height: 170)
        case .accessoryCircular: CGSize(width: 76, height: 76)
        case .accessoryRectangular: CGSize(width: 172, height: 76)
        case .accessoryInline: CGSize(width: 250, height: 24)
        default: CGSize(width: 170, height: 170)
        }
    }

    private var shape: AnyShape {
        switch family {
        case .accessoryCircular: AnyShape(Circle())
        case .accessoryRectangular: AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        case .accessoryInline: AnyShape(Rectangle())
        default: AnyShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    /// The inline face takes its type and colour from the system, so the gallery supplies both.
    @ViewBuilder
    private var face: some View {
        let view = DFWidgetView(kind: kind, family: family, renderingMode: mode, entry: entry)
        if family == .accessoryInline {
            view.font(.callout.weight(.semibold)).foregroundStyle(Palette.dark.ink)
        } else {
            view
        }
    }

    private var hasPlate: Bool { family != .accessoryInline }

    var body: some View {
        VStack(spacing: 6) {
            face
                .frame(width: size.width, height: size.height)
                .background { DFWidgetBackground(family: family, theme: entry.theme) }
                .clipShape(shape)
                .overlay {
                    if hasPlate {
                        shape.stroke(wallpaper.bevel, lineWidth: 1)
                    }
                }
            Text(caption)
                .dfStyle(.micro)
                .foregroundStyle(wallpaper.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                // Never wider than the widget, so a long caption cannot push the row off screen.
                .frame(width: size.width)
        }
    }
}
#endif
