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

let SwiftDrawnQurveParameterSpecs = ParameterTreeSpec {
    ParameterGroupSpec(identifier: "global", name: "Global") {
        ParameterSpec(
            address: .playMelody,
            identifier: "playMelody",
            name: "Play",
            units: .boolean,
            valueRange: 0...1,
            defaultValue: 0
        )

        ParameterSpec(
            address: .playbackDirection,
            identifier: "playbackDirection",
            name: "Playback Direction",
            units: .indexed,
            valueRange: 0...2,
            defaultValue: AUValue(PluginPlaybackDirection.forward.rawValue),
            valueStrings: ["Forward", "Backward", "Ping-Pong"]
        )

        ParameterSpec(
            address: .hostSync,
            identifier: "hostSync",
            name: "Sync to Host",
            units: .boolean,
            valueRange: 0...1,
            defaultValue: 0
        )
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
