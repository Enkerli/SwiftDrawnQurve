//
//  PressureCanvas.swift
//  SwiftDrawnQurveExtension
//
//  A drawing surface that knows how hard you are pressing.
//
//  This file is the reason this plug-in is worth porting natively, and it is
//  short, which is the interesting part: the whole argument in PORTING.md §0
//  about "native, no WebView, no bridge" comes down to about a hundred lines of
//  platform view that a bridged UI cannot write at all.
//
//  SwiftUI's `DragGesture` gives location and nothing else. Pressure lives on
//  `UITouch.force` and `NSEvent.pressure`, which means dropping to a platform
//  view — and that is fine, because a platform view is exactly what a WebView
//  cannot be. A browser gets pointer events through a bridge: coalescing is the
//  browser's, predicted touches are gone, and force never arrives.
//
//  Two things worth knowing about `force`:
//
//  · **It is not normalised.** `maximumPossibleForce` is the divisor and it
//    differs by device and by input — a Pencil, a 3D Touch screen and a finger
//    on a screen without force all report differently. Dividing is not optional.
//  · **A finger on a modern screen reports force 0**, not "no force". So the
//    test for "does this input have pressure" is the touch's *type*, not its
//    value, and getting that wrong gives every finger-drawn curve a pressure
//    companion pinned at zero.
//

import SwiftUI
import Carrier

#if canImport(UIKit)
import UIKit

/// A view that reports a stroke with pressure where the input has any.
struct PressureCanvas: UIViewRepresentable {
    /// Called for every sample while drawing, so the line can be shown live.
    var onChange: ([GestureCurve.StrokeSample]) -> Void
    /// Called once when the finger or pen lifts, with how long it took.
    var onEnd: ([GestureCurve.StrokeSample], TimeInterval) -> Void

    func makeUIView(context: Context) -> StrokeView {
        let view = StrokeView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateUIView(_ view: StrokeView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class StrokeView: UIView {
        var onChange: (([GestureCurve.StrokeSample]) -> Void)?
        var onEnd: (([GestureCurve.StrokeSample], TimeInterval) -> Void)?

        private var samples: [GestureCurve.StrokeSample] = []
        private var startedAt: TimeInterval = 0

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isMultipleTouchEnabled = false
        }

        required init?(coder: NSCoder) { fatalError("not from a nib") }

        private func sample(_ touch: UITouch) -> GestureCurve.StrokeSample {
            let point = touch.location(in: self)
            let x = min(1, max(0, point.x / max(1, bounds.width)))
            // Screen y grows downward and a curve's 1 is the top.
            let y = 1 - min(1, max(0, point.y / max(1, bounds.height)))

            // Pressure only where the input actually has it. A finger on a
            // modern screen reports force 0 rather than "none", so the question
            // is what kind of touch this is, not what it says.
            var pressure: Double?
            if touch.type == .pencil || touch.maximumPossibleForce > 0,
               touch.type != .direct || touch.maximumPossibleForce > 0 {
                if touch.type == .pencil {
                    pressure = Double(touch.force / max(0.0001, touch.maximumPossibleForce))
                }
            }
            return GestureCurve.StrokeSample(x: x, y: y, pressure: pressure)
        }

        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            samples = [sample(touch)]
            startedAt = CACurrentMediaTime()
            onChange?(samples)
        }

        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let touch = touches.first else { return }
            // Coalesced touches, which is the other half of what a bridge costs:
            // the OS captures at up to 240 Hz and delivers at 60, and asking for
            // them is how a drawn line keeps the detail the hand actually made.
            for coalesced in event?.coalescedTouches(for: touch) ?? [touch] {
                samples.append(sample(coalesced))
            }
            onChange?(samples)
        }

        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            finish()
        }

        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            // A cancelled stroke is not a stroke. Reporting it would commit a
            // curve to a lane because a phone call arrived.
            samples = []
            onChange?(samples)
        }

        private func finish() {
            guard samples.count > 1 else { samples = []; onChange?(samples); return }
            onEnd?(samples, max(0.1, CACurrentMediaTime() - startedAt))
            samples = []
        }
    }
}

#elseif canImport(AppKit)
import AppKit

/// The same on macOS, where pressure comes from a Force Touch trackpad.
struct PressureCanvas: NSViewRepresentable {
    var onChange: ([GestureCurve.StrokeSample]) -> Void
    var onEnd: ([GestureCurve.StrokeSample], TimeInterval) -> Void

    func makeNSView(context: Context) -> StrokeView {
        let view = StrokeView()
        view.onChange = onChange
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ view: StrokeView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class StrokeView: NSView {
        var onChange: (([GestureCurve.StrokeSample]) -> Void)?
        var onEnd: (([GestureCurve.StrokeSample], TimeInterval) -> Void)?

        private var samples: [GestureCurve.StrokeSample] = []
        private var startedAt: TimeInterval = 0

        override var acceptsFirstResponder: Bool { true }
        override var isFlipped: Bool { false }

        private func sample(_ event: NSEvent) -> GestureCurve.StrokeSample {
            let point = convert(event.locationInWindow, from: nil)
            let x = min(1, max(0, point.x / max(1, bounds.width)))
            // The view is not flipped, so y already grows upward here.
            let y = min(1, max(0, point.y / max(1, bounds.height)))
            // Only a pressure-sensitive device reports it; a mouse does not,
            // and `pressure` is then a constant that means nothing.
            let pressure: Double? = event.subtype == .tabletPoint
                || NSEvent.pressureBehavior(for: event) != .unknown
                ? Double(event.pressure) : nil
            return GestureCurve.StrokeSample(x: x, y: y, pressure: pressure)
        }

        override func mouseDown(with event: NSEvent) {
            samples = [sample(event)]
            startedAt = CACurrentMediaTime()
            onChange?(samples)
        }

        override func mouseDragged(with event: NSEvent) {
            samples.append(sample(event))
            onChange?(samples)
        }

        override func mouseUp(with event: NSEvent) {
            guard samples.count > 1 else { samples = []; onChange?(samples); return }
            onEnd?(samples, max(0.1, CACurrentMediaTime() - startedAt))
            samples = []
        }
    }
}

private extension NSEvent {
    /// Whether this event's device reports pressure at all. AppKit has no
    /// direct answer, so a tablet subtype is the reliable signal and everything
    /// else is treated as pressureless — which is the safe way round: a false
    /// negative loses a feature, a false positive invents a curve.
    static func pressureBehavior(for event: NSEvent) -> NSEvent.PressureBehavior {
        event.type == .pressure ? event.pressureBehavior : .unknown
    }
}
#endif
