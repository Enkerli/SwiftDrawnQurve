//
//  AudioUnitViewController.swift
//  SwiftDrawnQurveExtension
//
//  SwiftDrawnQurve's principal class: the three things a plug-in tells the shell.
//
//  Info.plist names `$(PRODUCT_MODULE_NAME).AudioUnitViewController` as both the
//  principal class and the factory function, so this type keeps that name. The
//  lifecycle it used to hold — creating the audio unit on the main queue,
//  setting up the parameter tree before the `@AUParameterUI` properties are
//  built, hosting a SwiftUI view and pinning it to the bounds — is
//  `PluginViewController` in the shared package.
//
//  Thirty lines, and identical in shape to the other three. That the fourth
//  plug-in — the first that transforms rather than generates — writes the same
//  file is the strongest thing anybody can say about the shell.
//

import CoreAudioKit
import SwiftUI
import Shell

@MainActor
public final class AudioUnitViewController: PluginViewController {

    public override func makeAudioUnit(componentDescription: AudioComponentDescription) throws -> PluginAudioUnit {
        try DrawnQurveAudioUnit(componentDescription: componentDescription, options: [])
    }

    public override var parameterTreeSpec: ParameterTreeSpec { SwiftDrawnQurveParameterSpecs }

    public override func makeRootView(parameterTree: ObservableAUParameterGroup,
                                      audioUnit: PluginAudioUnit) -> AnyView {
        AnyView(DrawnQurveMainView(parameterTree: parameterTree,
                              audioUnit: audioUnit as? DrawnQurveAudioUnit))
    }
}
