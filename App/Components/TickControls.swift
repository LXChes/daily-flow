import SwiftUI

private struct TickAnimationValues {
    var pop = 1.0
    var ringScale = 0.6
    var ringOpacity = 0.0
}

/// The tick: an empty ring that fills with the accent, draws its check mark on, pops and sends out a ring.
/// With Reduce Motion it simply cross-fades.
struct TickGlyph: View {
    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isDone: Bool
    var size: CGFloat = 28
    /// Ring colour while unticked, for sitting on the bright "now" block.
    var restingRing: Color?

    @State private var burst = 0

    var body: some View {
        // The keyframe closures run off the main actor, so they get plain values, not `self`.
        let accent = palette.accent
        ZStack {
            Circle().fill(isDone ? palette.accent : Color.clear)
            Circle().strokeBorder(isDone ? palette.accent : (restingRing ?? palette.tickLine), lineWidth: 2)
            TickShape()
                .trim(from: 0, to: isDone ? 1 : 0)
                .stroke(
                    palette.onAccent,
                    style: StrokeStyle(lineWidth: max(2, size * 0.1), lineCap: .round, lineJoin: .round)
                )
                .frame(width: size * 0.48, height: size * 0.34)
        }
        .frame(width: size, height: size)
        .animation(Motion.resolve(Motion.tick, reduceMotion: reduceMotion), value: isDone)
        .keyframeAnimator(initialValue: TickAnimationValues(), trigger: burst) { content, values in
            content
                .scaleEffect(values.pop)
                .overlay {
                    Circle()
                        .strokeBorder(accent, lineWidth: 2)
                        .scaleEffect(values.ringScale)
                        .opacity(values.ringOpacity)
                }
        } keyframes: { _ in
            KeyframeTrack(\.pop) {
                SpringKeyframe(1.3, duration: 0.14)
                SpringKeyframe(1.0, duration: 0.4, spring: .bouncy)
            }
            KeyframeTrack(\.ringScale) {
                MoveKeyframe(0.6)
                CubicKeyframe(1.9, duration: 0.55)
            }
            KeyframeTrack(\.ringOpacity) {
                MoveKeyframe(0.9)
                LinearKeyframe(0.0, duration: 0.55)
            }
        }
        .onChange(of: isDone) { _, done in
            if done && !reduceMotion {
                burst += 1
            }
        }
    }
}

/// Press-and-release squash for round controls.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

/// A tick with a 44-point touch target and a spoken state.
struct TickButton: View {
    let isDone: Bool
    let label: String
    var size: CGFloat = 28
    var restingRing: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            TickGlyph(isDone: isDone, size: size, restingRing: restingRing)
                .frame(width: max(size, Metrics.hit), height: max(size, Metrics.hit))
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
        .accessibilityValue(isDone ? "Done" : "Not done")
        .accessibilityAddTraits(.isToggle)
    }
}
