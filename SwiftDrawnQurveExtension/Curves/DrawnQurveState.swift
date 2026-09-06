//
//  DrawnQurveState.swift
//  SwiftDrawnQurveExtension
//
//  Four lanes, each holding a line somebody drew.
//
//  The fifth plug-in on `enkerli-swift` and the third kind: MelGen, ProgGenie
//  and SwiftSerpe generate, SwiftPitchFold transforms, and this loops a gesture.
//  The kernel grew a capability for it, and §8's invariant covered it without
//  amendment because the shape is the same as the other two — the decision is
//  off the audio thread, only the lookup is on it. A curve's decision is 256
//  samples and a handful of parameters; the render thread indexes a table.
//
//  What this file is *not* is an engine. `GestureCurve` is `Carrier`, the
//  playback is the shared kernel, the scale masks are `Theory`. This is the
//  arrangement: which lane is which, what it sends, and what the drawing
//  surface hands back.
//

import Foundation
import Carrier
import Shell
import Theory

struct DrawnQurveState: Codable, Hashable, Sendable {

    /// Four, because that is what the kernel holds. The JUCE build says
    /// "three independent lanes" in its README and `kMaxLanes = 4` in its code;
    /// four is the truthful number and the extra one costs nothing.
    static let laneCount = 4

    var lanes: [CurveLane]
    /// Which lane the drawing surface is pointed at. Drawing replaces that
    /// lane's curve and nothing else.
    var selectedLane: Int = 0
    /// Whether the lanes run at all. Separate from a lane's own enable, which
    /// is a mute — "not now" and "not this one" are different questions.
    var isRunning: Bool = false

    init(lanes: [CurveLane]? = nil, selectedLane: Int = 0, isRunning: Bool = false) {
        // Lane 0 starts on CC 74 and enabled, so a first drawn curve makes a
        // sound without anything else being touched. The other three start
        // silent: four lanes all sending at once, on a plug-in nobody has
        // configured, is noise rather than a demonstration.
        self.lanes = lanes ?? (0..<Self.laneCount).map { index in
            var curve = GestureCurve()
            curve.controller = [74, 71, 1, 11][index]
            curve.channel = 0
            return CurveLane(curve: curve, isEnabled: index == 0)
        }
        self.selectedLane = min(max(0, selectedLane), Self.laneCount - 1)
        self.isRunning = isRunning
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var restored = try c.decodeIfPresent([CurveLane].self, forKey: .lanes) ?? []
        while restored.count < Self.laneCount { restored.append(CurveLane()) }
        self.init(lanes: Array(restored.prefix(Self.laneCount)),
                  selectedLane: try c.decodeIfPresent(Int.self, forKey: .selectedLane) ?? 0,
                  isRunning: try c.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false)
    }

    // MARK: - The lane being drawn on

    var lane: CurveLane {
        get { lanes[selectedLane] }
        set { lanes[selectedLane] = newValue }
    }

    /// Replaces the selected lane's curve with a drawn stroke.
    ///
    /// - Parameter seconds: how long the gesture took, which becomes the loop's
    ///   length. A drawn curve loops at the speed it was drawn, which is the
    ///   plug-in's whole premise and the reason duration is captured rather
    ///   than set.
    mutating func draw(_ points: [(x: Double, y: Double)], seconds: Double) {
        guard var drawn = GestureCurve.fromStroke(points, durationSeconds: seconds) else { return }
        // Everything except the shape is kept: you are redrawing the line, not
        // resetting what it is wired to.
        let existing = lane.curve
        drawn.message = existing.message
        drawn.controller = existing.controller
        drawn.channel = existing.channel
        drawn.minOut = existing.minOut
        drawn.maxOut = existing.maxOut
        drawn.smoothing = existing.smoothing
        drawn.velocity = existing.velocity
        drawn.phaseOffset = existing.phaseOffset
        drawn.isOneShot = existing.isOneShot
        lanes[selectedLane].curve = drawn
        lanes[selectedLane].isEnabled = true
    }

    /// Whether a lane has anything worth playing yet.
    func hasCurve(_ index: Int) -> Bool {
        index >= 0 && index < lanes.count && !lanes[index].curve.isFlat
    }

    // MARK: - Saying what a lane is

    func summary(of index: Int) -> String {
        guard index >= 0, index < lanes.count else { return "" }
        let lane = lanes[index]
        let target: String
        switch lane.curve.message {
        case .controlChange: target = "CC \(lane.curve.controller)"
        case .channelPressure: target = "Pressure"
        case .pitchBend: target = "Bend"
        case .note:
            target = lane.pitchClasses.isEmpty
                ? "Notes"
                : "Notes · \(PitchClassSet.ringName(lane.root)) "
                  + "\(lane.pitchClasses.count) of 12"
        }
        let length = lane.curve.durationSeconds
            .formatted(.number.precision(.fractionLength(1)))
        return hasCurve(index)
            ? "\(target) · ch \(lane.curve.channel + 1) · \(length)s"
            : "\(target) · nothing drawn"
    }
}
