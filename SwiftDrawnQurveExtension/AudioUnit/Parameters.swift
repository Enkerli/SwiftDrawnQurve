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

// No transport parameters, for now, and the "for now" is the honest part.
//
// This tree held `playMelody`, `playbackDirection` and `hostSync` until
// 2026-09, inherited by being scaffolded from a plug-in that schedules notes.
// The kernel acts on all three inside `processMelody`; this plug-in never
// commits a sequence, so a host showed three automatable controls that did
// nothing. A missing control is a gap; a control that lies is a bug.
//
// Run/stop is a UI button today and *should* be a parameter — a looping
// gesture plug-in a host cannot start is a real limitation, and it is listed in
// GAPS.md rather than papered over with a control that happens to compile.
let SwiftDrawnQurveParameterSpecs = ParameterTreeSpec {
    ParameterGroupSpec(identifier: "global", name: "Global") {
    }
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
