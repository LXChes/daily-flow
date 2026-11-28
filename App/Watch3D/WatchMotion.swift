import CoreMotion
import Foundation
import simd

/// Where the 3D watch is turned, in radians about x and y (x: the top tips toward the viewer, y: the face turns
/// to the viewer's right). Three things move it:
///
/// - gravity from the phone's motion sensors, so the watch tilts as the phone does and the reflections slide
///   (no entitlement and no Info.plist key: device motion is open to every app),
/// - a gentle idle sway (the whole motion when the phone has no sensors, as in the simulator),
/// - a finger: drag to tilt, and it springs back on release.
///
/// Everything is smoothed, and clamped to about 24 degrees. With Reduce Motion there is no sensor tilt and no
/// sway; a finger still works, and settles back without bouncing.
@MainActor
final class WatchMotion {
    /// The most the watch turns either way.
    static let limit: Float = 24 * .pi / 180

    /// False with Reduce Motion: no sensor tilt and no sway.
    var usesDeviceMotion = true
    /// True with Reduce Motion: the spring back from a drag is critically damped.
    var calm = false

    private let manager = CMMotionManager()
    private var isRunning = false
    private var smoothed = SIMD2<Float>(0, 0)
    private var drag = SIMD2<Float>(0, 0)
    private var dragVelocity = SIMD2<Float>(0, 0)
    private var dragTarget = SIMD2<Float>(0, 0)
    private var isDragging = false

    /// True when nothing is moving the watch, so an on-demand renderer can stop redrawing.
    var isSettled: Bool {
        !isDragging && simd_length(drag) < 0.0005 && simd_length(dragVelocity) < 0.002
    }

    func start() {
        guard !isRunning, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates()
        isRunning = true
    }

    /// Stops the sensors. Call when the view goes away or off screen.
    func stop() {
        guard isRunning else { return }
        manager.stopDeviceMotionUpdates()
        isRunning = false
    }

    // MARK: Finger

    func beginDrag() {
        isDragging = true
        dragVelocity = SIMD2<Float>(0, 0)
    }

    /// `dx` and `dy` are the finger's travel in points since it went down.
    func updateDrag(dx: CGFloat, dy: CGFloat) {
        let scale: Float = 0.0045
        let limit = WatchMotion.limit
        dragTarget = SIMD2<Float>(
            min(max(Float(dy) * scale, -limit), limit),
            min(max(Float(dx) * scale, -limit), limit)
        )
    }

    func endDrag() {
        isDragging = false
    }

    // MARK: Per frame

    /// The tilt for this frame. `dt` is the time since the last call, `time` any steadily growing seconds.
    func step(dt: Float, time: Double) -> SIMD2<Float> {
        let dt = min(max(dt, 0.001), 0.05)
        var target = SIMD2<Float>(0, 0)
        if usesDeviceMotion {
            let t = Float(time.truncatingRemainder(dividingBy: 10_000))
            let sway = SIMD2<Float>(0.12 * sin(0.45 * t), 0.157 * sin(0.31 * t + 1))
            if let gravity = manager.deviceMotion?.gravity {
                // Held upright and leaned back a little, gravity points mostly down the screen and a bit out of it.
                target.x = -(Float(gravity.z) + 0.5) * 0.9
                target.y = Float(gravity.x) * 0.9
                target += sway * 0.2
            } else {
                target = sway
            }
        }
        smoothed += (target - smoothed) * (1 - exp(-dt * 6))

        if isDragging {
            drag += (dragTarget - drag) * (1 - exp(-dt * 18))
            dragVelocity = SIMD2<Float>(0, 0)
        } else {
            let stiffness: Float = 70
            let damping: Float = calm ? 2 * stiffness.squareRoot() : 8
            dragVelocity += (-stiffness * drag - damping * dragVelocity) * dt
            drag += dragVelocity * dt
        }

        let limit = WatchMotion.limit
        let total = smoothed + drag
        return SIMD2<Float>(min(max(total.x, -limit), limit), min(max(total.y, -limit), limit))
    }
}
