//
//  SwiftDrawnQurveTests.swift
//  SwiftDrawnQurveTests
//
//  This target can reach almost nothing, and that is worth stating rather than
//  discovering.
//
//  Everything real is either in the `SwiftDrawnQurveExtension` target (extension-only
//  membership) or in the `enkerli-swift` package next door. A green test action
//  in Xcode says the host app compiles. The checks that matter are in
//  `Scripts/verify.sh`, which runs outside Xcode for exactly this reason.
//
//  Kept rather than deleted so the absence reads as a decision.
//

import Testing

@Test func theRealChecksAreElsewhere() {
    // Scripts/verify.sh identity — the component triple, which is the one thing
    // about this plug-in that is unrecoverable if it is wrong.
    #expect(Bool(true))
}
