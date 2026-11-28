import Metal
import MetalKit
import SwiftUI
import UIKit

/// Whether the 3D watch can run here at all: a Metal device and the compiled shader library. The 2D watch
/// shows when this is false, or when `Watch3DView` reports a failure while it sets up.
enum Watch3D {
    static let isSupported: Bool = {
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        return device.makeDefaultLibrary() != nil
    }()
}

/// An `MTKView` that tells the renderer when it joins or leaves a window, so it can start and stop at once.
final class WatchMetalView: MTKView {
    var onWindowChange: (() -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onWindowChange?()
    }
}

/// The Metal view behind the 3D watch. SwiftUI owns the data; the renderer owns the drawing. Tap a gear to select
/// it, drag (or press and hold, then drag) to tilt the watch. If Metal setup fails, `onFailure` is called once so
/// the screen can show the 2D watch instead.
struct Watch3DView: UIViewRepresentable {
    let input: WatchRenderInput
    /// False when the app is not in the foreground.
    let isActive: Bool
    let onSelect: (UUID) -> Void
    let onFailure: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WatchMetalView {
        let view = WatchMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.isAccessibilityElement = false
        context.coordinator.onSelect = onSelect

        guard let renderer = WatchRenderer.make(view: view, input: input) else {
            let failure = onFailure
            Task { @MainActor in failure() }
            return view
        }
        context.coordinator.renderer = renderer
        view.onWindowChange = { [weak renderer] in
            renderer?.viewDidMoveToWindow()
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        let hold = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleHold(_:)))
        hold.minimumPressDuration = 0.16
        hold.allowableMovement = 14
        for gesture in [tap, pan, hold] {
            gesture.delegate = context.coordinator
            view.addGestureRecognizer(gesture)
        }
        renderer.update(input, sceneActive: isActive)
        renderer.startObserving()
        return view
    }

    func updateUIView(_ view: WatchMetalView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.renderer?.update(input, sceneActive: isActive)
    }

    static func dismantleUIView(_ view: WatchMetalView, coordinator: Coordinator) {
        coordinator.renderer?.teardown()
        coordinator.renderer = nil
    }

    // MARK: Gestures

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var renderer: WatchRenderer?
        var onSelect: (UUID) -> Void = { _ in }
        private var holdOrigin = CGPoint.zero
        private let feedback = UIImpactFeedbackGenerator(style: .light)

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view, let renderer else { return }
            if let id = renderer.gearHit(at: gesture.location(in: view), in: view.bounds.size) {
                onSelect(id)
            }
        }

        /// A horizontal drag tilts the watch; vertical drags are left to the scroll view.
        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view, let renderer else { return }
            switch gesture.state {
            case .began:
                renderer.dragBegan()
            case .changed:
                let move = gesture.translation(in: view)
                renderer.dragChanged(dx: move.x, dy: move.y)
            case .ended, .cancelled, .failed:
                renderer.dragEnded()
            default:
                break
            }
        }

        /// Press and hold, then move in any direction: a free tilt, like turning the watch over in your fingers.
        @objc func handleHold(_ gesture: UILongPressGestureRecognizer) {
            guard let view = gesture.view, let renderer else { return }
            switch gesture.state {
            case .began:
                holdOrigin = gesture.location(in: view)
                feedback.impactOccurred()
                renderer.dragBegan()
            case .changed:
                let point = gesture.location(in: view)
                renderer.dragChanged(dx: point.x - holdOrigin.x, dy: point.y - holdOrigin.y)
            case .ended, .cancelled, .failed:
                renderer.dragEnded()
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y)
        }
    }
}
