//
//  Parameters.swift
//  SwiftDrawnQurveExtension
//
//  The three knobs a host sees.
//
//  They are the kernel's, not this plug-in's: `playMelody`, `playbackDirection`
//  and `hostSync` are what a loop player has, and `PluginParameterAddresses.h`
//  in the shared package is where they are declared. That naming was the last
//  seam SwiftDrawnQurve had to cut before this plug-in could exist — while the header was
//  called `SwiftDrawnQurveExtensionParameterAddresses.h` the kernel looked as though it
//  depended on the melody app.
//
//  Everything that is actually SwiftDrawnQurve's — key, bars, surprise, freshness,
//  reharm — is session state rather than an AU parameter, deliberately. A host
//  automating "surprise" bar by bar would be automating a re-generation, and a
//  progression that changes under the automation lane is not a progression.
//

import AudioToolbox
import Foundation
import Kernel
import Shell

// The transport, and only the transport.
//
// This tree was empty on `main`, and the emptiness was honest rather than
// lazy: it had held `playMelody`, `playbackDirection` and `hostSync` inherited
// from a plug-in that schedules notes, and the kernel acts on all three inside
// `processMelody` — which this plug-in never uses. Three automatable controls
// that did nothing. A missing control is a gap; a control that lies is a bug.
//
// What changed is that they are no longer lies. `playMelody` is mirrored into
// the curve engine's run state by `DrawnQurveAudioUnit`, so a host pressing
// play starts the lanes; `hostSync` and direction reach the kernel's curve path
// the same way the sequence path already used them. This was the register's
// most-wanted row: a looping gesture plug-in a host cannot start is a real
// limitation, and every other plug-in in the suite wanted the same three
// controls, which is why they are declared from `AUHost.TransportParameters`
// rather than retyped here.
//
// Everything that is actually this plug-in's — which lane, what was drawn, the
// quantization grid — stays session state. A host automating "which lane you
// are drawing on" would be automating a gesture, and a gesture that changes
// under the automation lane is not a gesture.
let SwiftDrawnQurveParameterSpecs = ParameterTreeSpec {
    TransportParameters.group(.loop)
}

extension ParameterSpec {
    init(
        address: PluginParameterAddress,
        identifier: String,
        name: String,
        units: AudioUnitParameterUnit,
        valueRange: ClosedRange<AUValue>,
        defaultValue: AUValue,
        unitName: String? = nil,
        flags: AudioUnitParameterOptions = [AudioUnitParameterOptions.flag_IsWritable, AudioUnitParameterOptions.flag_IsReadable],
        valueStrings: [String]? = nil,
        dependentParameters: [NSNumber]? = nil
    ) {
        self.init(address: address.rawValue,
                  identifier: identifier,
                  name: name,
                  units: units,
                  valueRange: valueRange,
                  defaultValue: defaultValue,
                  unitName: unitName,
                  flags: flags,
                  valueStrings: valueStrings,
                  dependentParameters: dependentParameters)
    }
}
