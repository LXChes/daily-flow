import DailyFlowCore
import SwiftUI
import UIKit

/// The flat printed parts of the 3D watch, drawn by the 2D painter into images the renderer maps onto the
/// bezel, the hour ring, the progress overlay and the strap. Rendered on the main actor with `ImageRenderer`,
/// and only when the tasks, theme or minute change, never per frame.
enum WatchTextures {
    /// Points across the printed square, and the scale to render it at. The square spans `2 * WatchMesh.uvExtent`
    /// mesh units, so 1 point is about `2.5 / 1024` units.
    private static let printPoints: CGFloat = 1024
    private static let printScale: CGFloat = 1.5

    private static func stage(in size: CGSize) -> WatchStage {
        WatchStage(
            center: CGPoint(x: size.width / 2, y: size.height / 2),
            unit: size.width / (2 * CGFloat(WatchMesh.uvExtent))
        )
    }

    /// Hour ring, 24 hour bezel and task arcs, in one image (see the planar UVs in `WatchMesh`).
    @MainActor
    static func ringsImage(_ frame: WatchFrame) -> CGImage? {
        var copy = frame
        copy.selected = nil
        let plain = copy
        let content = Canvas { context, size in
            let s = stage(in: size)
            WatchPainter.hourRing(&context, plain, s)
            WatchPainter.bezel(&context, plain, s)
            WatchPainter.taskArcs(&context, plain, s)
        }
        .frame(width: printPoints, height: printPoints)
        return render(content, scale: printScale)
    }

    /// The progress arc and its "x / y DONE" label, larger and brighter than the 2D watch draws them.
    @MainActor
    static func progressImage(_ frame: WatchFrame) -> CGImage? {
        let content = Canvas { context, size in
            progress(&context, frame, stage(in: size))
        }
        .frame(width: printPoints, height: printPoints)
        return render(content, scale: printScale)
    }

    /// A strap: padded leather with stitching, and buckle holes on the lower one. Row 0 is next to the case.
    @MainActor
    static func strapImage(_ frame: WatchFrame, holes: Bool) -> CGImage? {
        let content = Canvas { context, size in
            strap(&context, frame.palette, size, holes: holes)
        }
        .frame(width: 262, height: 600)
        return render(content, scale: 2.5)
    }

    @MainActor
    private static func render<Content: View>(_ content: Content, scale: CGFloat) -> CGImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        renderer.isOpaque = false
        return renderer.cgImage
    }

    // MARK: Progress

    private static func progress(_ ctx: inout GraphicsContext, _ f: WatchFrame, _ s: WatchStage) {
        let p = f.palette
        let radius = s.d(107.5)
        // The track runs 120 degrees, from the lower left (SwiftUI 100 degrees) up to 10 o'clock (220).
        var track = Path()
        track.addArc(center: s.center, radius: radius, startAngle: .degrees(100), endAngle: .degrees(220), clockwise: false)
        ctx.stroke(track, with: .color(p.depth.opacity(0.7)), style: StrokeStyle(lineWidth: s.d(5.2), lineCap: .round))
        ctx.stroke(track, with: .color(p.progress.opacity(0.2)), style: StrokeStyle(lineWidth: s.d(4.0), lineCap: .round))

        let sweep = WatchGeometry.progressSweep(f.progress, trackDegrees: 120)
        if sweep > 0.5 {
            var fill = Path()
            fill.addArc(center: s.center, radius: radius, startAngle: .degrees(220 - sweep), endAngle: .degrees(220), clockwise: false)
            ctx.stroke(fill, with: .color(p.progress.opacity(0.3)), style: StrokeStyle(lineWidth: s.d(8.5), lineCap: .round))
            ctx.stroke(fill, with: .color(p.progress), style: StrokeStyle(lineWidth: s.d(4.0), lineCap: .round))
        }

        // "3 / 9 DONE", along the arc and reading upward, bigger than in 2D.
        let label = f.progress.total == 0 ? "NO TASKS" : "\(f.progress.done) / \(f.progress.total) DONE"
        let size = s.d(9)
        let advance = s.d(6.6)
        let labelRadius = s.d(96.5)
        let span = Double(label.count) * Double(advance / labelRadius) * 180 / .pi
        var angle = 250 - span / 2
        for character in label {
            let step = Double((character == " " ? advance * 0.55 : advance) / labelRadius) * 180 / .pi
            angle += step / 2
            let spot = s.polar(labelRadius, degrees: angle)
            let glyph = Text(String(character))
                .font(DFTextStyle.badge.font(fixedSize: size))
                .foregroundStyle(p.progress)
            let halo = Text(String(character))
                .font(DFTextStyle.badge.font(fixedSize: size))
                .foregroundStyle(p.depth.opacity(0.95))
            var rotated = ctx
            rotated.translateBy(x: spot.x, y: spot.y)
            rotated.rotate(by: .degrees(angle))
            rotated.draw(halo, at: CGPoint(x: s.d(0.9), y: s.d(0.9)), anchor: .center)
            rotated.draw(glyph, at: .zero, anchor: .center)
            angle += step / 2
        }
    }

    // MARK: Strap

    private static func strap(_ ctx: inout GraphicsContext, _ p: WatchPalette, _ size: CGSize, holes: Bool) {
        let rect = CGRect(origin: .zero, size: size)
        let shape = Path(roundedRect: rect, cornerRadius: size.width * 0.04)
        // Padded leather: dark at the edges, lighter across the crown.
        ctx.fill(
            shape,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: p.leatherDark, location: 0),
                    .init(color: p.leatherLight, location: 0.5),
                    .init(color: p.leatherDark, location: 1)
                ]),
                startPoint: CGPoint(x: rect.minX, y: rect.midY),
                endPoint: CGPoint(x: rect.maxX, y: rect.midY)
            )
        )
        // The rolled edge catching the light.
        let edge = Path(roundedRect: rect.insetBy(dx: size.width * 0.012, dy: 0), cornerRadius: size.width * 0.04)
        ctx.stroke(edge, with: .color(p.leatherLight.opacity(0.9)), lineWidth: size.width * 0.012)

        // Stitching down both sides.
        let inset = size.width * 0.085
        for x in [inset, size.width - inset] {
            var stitch = Path()
            stitch.move(to: CGPoint(x: x, y: 0))
            stitch.addLine(to: CGPoint(x: x, y: size.height))
            ctx.stroke(
                stitch,
                with: .color(p.stitch.opacity(0.9)),
                style: StrokeStyle(lineWidth: size.width * 0.014, lineCap: .round, dash: [size.width * 0.05, size.width * 0.04])
            )
        }

        if holes {
            for index in 0..<5 {
                let centre = CGPoint(x: size.width / 2, y: size.height * 0.4 + CGFloat(index) * size.height * 0.105)
                let radius = size.width * 0.045
                let hole = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
                ctx.fill(hole, with: .color(p.depth.opacity(0.95)))
                ctx.stroke(hole, with: .color(p.leatherLight.opacity(0.85)), lineWidth: size.width * 0.011)
                let ring = Path(ellipseIn: CGRect(x: centre.x - radius * 1.5, y: centre.y - radius * 1.5, width: radius * 3, height: radius * 3))
                ctx.stroke(ring, with: .color(p.stitch.opacity(0.35)), lineWidth: size.width * 0.007)
            }
        }

        // Dark where the strap tucks under the case.
        let root = CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.2)
        ctx.fill(
            Path(root),
            with: .linearGradient(
                Gradient(colors: [p.depth.opacity(0.75), p.depth.opacity(0)]),
                startPoint: CGPoint(x: root.midX, y: root.minY),
                endPoint: CGPoint(x: root.midX, y: root.maxY)
            )
        )
    }
}
