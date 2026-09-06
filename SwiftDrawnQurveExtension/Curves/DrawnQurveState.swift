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
import UI

struct DrawnQurveState: Codable, Hashable, Sendable {

    /// Four, because that is what the kernel holds. The JUCE build says
    /// "three independent lanes" in its README and `kMaxLanes = 4` in its code;
    /// four is the truthful number and the extra one costs nothing.
    /// Four drawn lanes. The kernel holds eight curve slots, because a lane
    /// carries a line and, when the input reported it, a pressure companion.
    static let laneCount = 4

    /// Light, dark, or whatever the host says.
    ///
    /// Session state rather than a parameter: a host automating the colour
    /// scheme at bar 17 is not a musical decision anybody draws.
    var themePreference: ThemePreference = .system

    var lanes: [CurveLane]
    /// Which lane the drawing surface is pointed at. Drawing replaces that
    /// lane's curve and nothing else.
    var selectedLane: Int = 0
    /// Whether the lanes run at all. Separate from a lane's own enable, which
    /// is a mute — "not now" and "not this one" are different questions.
    var isRunning: Bool = false

    init(lanes: [CurveLane]? = nil, selectedLane: Int = 0, isRunning: Bool = false,
         themePreference: ThemePreference = .system) {
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
        self.themePreference = themePreference
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var restored = try c.decodeIfPresent([CurveLane].self, forKey: .lanes) ?? []
        while restored.count < Self.laneCount { restored.append(CurveLane()) }
        self.init(lanes: Array(restored.prefix(Self.laneCount)),
                  selectedLane: try c.decodeIfPresent(Int.self, forKey: .selectedLane) ?? 0,
                  isRunning: try c.decodeIfPresent(Bool.self, forKey: .isRunning) ?? false,
                  themePreference: try c.decodeIfPresent(ThemePreference.self,
                                                         forKey: .themePreference) ?? .system)
    }

    // MARK: - The lane being drawn on

    var lane: CurveLane {
        get { lanes[selectedLane] }
        set { lanes[selectedLane] = newValue }
    }

    /// Replaces the selected lane's curve — and its pressure companion, when
    /// the stroke carried one — with a drawn gesture.
    ///
    /// - Parameter seconds: how long the gesture took, which becomes the loop's
    ///   length. A drawn curve loops at the speed it was drawn, which is the
    ///   plug-in's whole premise and the reason duration is captured rather
    ///   than set.
    ///
    /// One gesture, up to two curves. They share a time base by construction —
    /// sample *i* of each is the same instant — which is what makes pressure
    /// worth pairing with the line rather than drawing separately. A swell that
    /// arrives exactly where the line peaks is a thing you play; two passes
    /// over the surface could only approximate it.
    mutating func draw(_ samples: [GestureCurve.StrokeSample], seconds: Double) {
        guard let pair = GestureCurve.fromStroke(samples, durationSeconds: seconds) else { return }
        lanes[selectedLane].curve = rewired(pair.position, like: lane.curve)
        lanes[selectedLane].isEnabled = true

        if let pressure = pair.pressure {
            // Only replace a pressure companion when the stroke had one. A
            // Pencil curve redrawn with a finger keeps the pressure it had
            // rather than silently losing it — you changed the line, not the
            // device's abilities.
            lanes[selectedLane].pressure = rewired(pressure, like: lane.pressure ?? defaultPressureCurve)
            lanes[selectedLane].isPressureEnabled = true
        }
    }

    /// A newly drawn shape with an existing curve's wiring on it.
    ///
    /// Redrawing is redrawing the *line*, not resetting what it is connected to.
    private func rewired(_ drawn: GestureCurve, like existing: GestureCurve) -> GestureCurve {
        var result = drawn
        result.message = existing.message
        result.controller = existing.controller
        result.channel = existing.channel
        result.minOut = existing.minOut
        result.maxOut = existing.maxOut
        result.smoothing = existing.smoothing
        result.velocity = existing.velocity
        result.phaseOffset = existing.phaseOffset
        result.isOneShot = existing.isOneShot
        return result
    }

    /// What a pressure companion is wired to before anybody says otherwise.
    ///
    /// CC 2 — breath — because that is what pressure most often stands in for,
    /// and because sending it to the same controller as the line would be two
    /// curves fighting over one destination, which is the least useful thing a
    /// pair could do.
    private var defaultPressureCurve: GestureCurve {
        var curve = GestureCurve()
        curve.controller = 2
        curve.smoothing = 0.15
        return curve
    }

    /// Whether a lane has pressure recorded.
    func hasPressure(_ index: Int) -> Bool {
        index >= 0 && index < lanes.count
            && lanes[index].pressure.map { !$0.isFlat } == true
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
        guard hasCurve(index) else { return "\(target) · nothing drawn" }
        let pressure = hasPressure(index)
            ? " · + pressure → CC \(lane.pressure?.controller ?? 2)"
            : ""
        return "\(target) · ch \(lane.curve.channel + 1) · \(length)s\(pressure)"
    }
}
