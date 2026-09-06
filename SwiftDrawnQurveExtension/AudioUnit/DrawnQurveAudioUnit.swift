//
//  DrawnQurveAudioUnit.swift
//  SwiftDrawnQurveExtension
//
//  The session, and the curves it commits.
//
//  Fifth time this file has been written and the third thing it commits:
//  MelGen and its siblings commit a sequence, SwiftPitchFold commits a 128-byte
//  map, and this commits four curves. Same shape every time, because the
//  shell's contract is the same — hand the render thread a fixed-size thing,
//  atomically, from here.
//

import AVFoundation
import Shell

public final class DrawnQurveAudioUnit: PluginAudioUnit, @unchecked Sendable {

    private let stateLock = NSLock()
    private var _state = DrawnQurveState()

    /// What the kernel is holding, so redrawing a curve pushes and moving a
    /// slider that changed nothing does not.
    private var lastCommitted: [CurveLane]?

    var state: DrawnQurveState {
        get { stateLock.withLock { _state } }
        set { update(state: newValue) }
    }

    func update(state newState: DrawnQurveState) {
        stateLock.withLock { _state = newState }
        if newState.lanes != lastCommitted {
            setCurveLanes(newState.lanes)
            lastCommitted = newState.lanes
        }
        areCurvesRunning = newState.isRunning
    }

    /// Mirrors the host's Play parameter into the curve engine.
    ///
    /// The parameter and the session's `isRunning` are two names for one fact,
    /// and they have to agree in both directions: a host pressing play must
    /// start the lanes, and the on-screen button must move the host's
    /// automation. `PluginAudioUnit` routes every parameter change into the
    /// kernel, which is where the *sequence* path reads `playMelody` — this
    /// plug-in commits no sequence, so nothing was reading it at all until now.
    ///
    /// Guarded against the loop it would otherwise make: setting the parameter
    /// calls this, which sets the state, which would set the parameter.
    private var isMirroring = false

    /// The host's Play, arriving as a parameter change.
    ///
    /// The kernel reads `playMelody` inside `processMelody`, which this plug-in
    /// never uses — so without this the parameter would exist, appear in every
    /// host's automation lane, and do nothing at all. That is the exact bug the
    /// empty tree on `main` was avoiding, and the reason declaring these three
    /// only became honest once something read them.
    public override func parameterDidChange(_ address: AUParameterAddress, _ value: AUValue) {
        guard address == TransportParameter.play.rawValue else { return }
        mirrorTransport(playing: value >= 0.5)
    }

    func mirrorTransport(playing: Bool) {
        guard !isMirroring else { return }
        isMirroring = true
        defer { isMirroring = false }
        var next = state
        guard next.isRunning != playing else { return }
        next.isRunning = playing
        update(state: next)
    }

    /// Where each lane's playhead is, for drawing them. Nil where a lane is not
    /// running, which is what lets the UI tell "at the start" from "stopped".
    var phases: [Double?] {
        (0..<DrawnQurveState.laneCount).map { curvePhase(ofLane: $0) }
    }

    private static let stateKey = "SwiftDrawnQurve.sessionState"

    public override var fullState: [String: Any]? {
        get {
            var dictionary = super.fullState ?? [:]
            if let data = try? JSONEncoder().encode(state) {
                dictionary[Self.stateKey] = data
            }
            return dictionary
        }
        set {
            super.fullState = newValue
            guard let data = newValue?[Self.stateKey] as? Data,
                  let restored = try? JSONDecoder().decode(DrawnQurveState.self, from: data) else {
                return
            }
            state = restored
        }
    }

    public override var fullStateForDocument: [String: Any]? {
        get { fullState }
        set { fullState = newValue }
    }

    /// A reopened session has its curves in the kernel before the view exists,
    /// so a project that was playing plays again without being looked at.
    public override init(componentDescription: AudioComponentDescription,
                         options: AudioComponentInstantiationOptions) throws {
        try super.init(componentDescription: componentDescription, options: options)
        update(state: _state)
    }
}
