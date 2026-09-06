//
//  curves-main.swift
//  SwiftDrawnQurve
//
//  What the plug-in decides, away from a host.
//
//  The off-thread half. The render-thread half — looping the curve and emitting
//  it — is C++ and is checked by `Scripts/check-kernel.sh` in the enkerli-swift
//  package, which `verify.sh` runs too. That matters more here than in the other
//  plug-ins: this one's product IS the render loop, so a green from this file
//  alone would be saying almost nothing.
//

import Foundation
import Carrier
import Shell
import Theory

/// Shorthand, because these read better as a list of points than as a list of
/// initialisers, and every one of them is a point.
func S(_ x: Double, _ y: Double, _ pressure: Double? = nil) -> GestureCurve.StrokeSample {
    GestureCurve.StrokeSample(x: x, y: y, pressure: pressure)
}

var failures = 0
var checks = 0

func check(_ what: String, _ passed: Bool, _ detail: String = "") {
    checks += 1
    print("  \(passed ? "PASS" : "FAIL")  \(what)\(detail.isEmpty ? "" : " — \(detail)")")
    if !passed { failures += 1 }
}

print("── four lanes, and what starts in them ────────────")

var state = DrawnQurveState()
check("there are four lanes", state.lanes.count == 4)
check("only the first is live, so a fresh plug-in is not four things at once",
      state.lanes.filter(\.isEnabled).count == 1 && state.lanes[0].isEnabled)
check("and it is pointed at CC 74", state.lanes[0].curve.message == .controlChange
      && state.lanes[0].curve.controller == 74)
check("nothing is drawn yet", !state.hasCurve(0), state.summary(of: 0))
check("and nothing is running", !state.isRunning)

print("\n── drawing ────────────────────────────────────────")

state.draw([S(0, 0), S(0.5, 1), S(1, 0)], seconds: 2.5)
check("a stroke becomes a curve on the selected lane", state.hasCurve(0))
check("the gesture's own duration becomes the loop's length",
      abs(state.lanes[0].curve.durationSeconds - 2.5) < 0.001,
      "\(state.lanes[0].curve.durationSeconds)s")
check("drawing enables the lane it was drawn on", state.lanes[0].isEnabled)
check("the peak is where it was drawn",
      state.lanes[0].curve.value(atPhase: 0.5) > 0.98,
      "\(state.lanes[0].curve.value(atPhase: 0.5))")

// Redrawing is redrawing the LINE, not resetting the lane.
state.lanes[0].curve.message = .pitchBend
state.lanes[0].curve.channel = 5
state.lanes[0].curve.smoothing = 0.4
state.draw([S(0, 1), S(1, 0)], seconds: 1)
check("redrawing keeps what the lane is wired to",
      state.lanes[0].curve.message == .pitchBend
      && state.lanes[0].curve.channel == 5
      && abs(state.lanes[0].curve.smoothing - 0.4) < 1e-9)
check("but takes the new shape and the new duration",
      state.lanes[0].curve.value(atPhase: 0) > 0.98
      && abs(state.lanes[0].curve.durationSeconds - 1) < 0.001)

print("\n── lanes are independent ──────────────────────────")

state.selectedLane = 2
state.draw([S(0, 0.25), S(1, 0.75)], seconds: 0.5)
check("drawing on lane 3 leaves lane 1 alone",
      state.hasCurve(0) && state.hasCurve(2)
      && state.lanes[0].curve.durationSeconds != state.lanes[2].curve.durationSeconds)
check("and lanes 2 and 4 are still empty", !state.hasCurve(1) && !state.hasCurve(3))

print("\n── the mask a note lane hands the kernel ──────────")

state.selectedLane = 1
state.lanes[1].curve.message = .note
state.lanes[1].pitchClasses = []
check("no scale is chromatic — 0xFFF, no quantization",
      state.lanes[1].scaleMask == 0x0FFF,
      String(format: "0x%03X", state.lanes[1].scaleMask))
state.lanes[1].pitchClasses = PitchClassSet.family(7, root: 0)
check("C major is 0xAB5", state.lanes[1].scaleMask == 0xAB5,
      String(format: "0x%03X", state.lanes[1].scaleMask))
state.lanes[1].pitchClasses = [0, 2, 4, 6, 7, 9, 11]
check("and 0xAD5 is Lydian, which is the one it keeps being confused with",
      state.lanes[1].scaleMask == 0xAD5,
      String(format: "0x%03X", state.lanes[1].scaleMask))

// The mask is root-relative, so the same shape at another root is the same mask.
state.lanes[1].pitchClasses = PitchClassSet.family(7, root: 7)
state.lanes[1].root = 7
check("G major has C major's mask, because the mask is intervals",
      state.lanes[1].scaleMask == 0xAB5,
      String(format: "0x%03X", state.lanes[1].scaleMask))

print("\n── pressure, as a second curve from one gesture ───")

var pen = DrawnQurveState()
pen.draw([S(0, 0, 0.1), S(0.5, 1, 0.9), S(1, 0, 0.2)], seconds: 1)
check("a Pencil stroke records a pressure companion", pen.hasPressure(0),
      pen.summary(of: 0))
check("and the companion is not the line",
      pen.lanes[0].pressure?.value(atPhase: 0) ?? 0 < 0.2
      && pen.lanes[0].curve.value(atPhase: 0) < 0.05
      && (pen.lanes[0].pressure?.value(atPhase: 0.5) ?? 0) > 0.85)
check("both share a time base, which is the whole reason to pair them",
      pen.lanes[0].pressure?.durationSeconds == pen.lanes[0].curve.durationSeconds)
check("the companion goes somewhere else by default — CC 2, not the line's 74",
      pen.lanes[0].pressure?.controller == 2 && pen.lanes[0].curve.controller == 74,
      "two curves fighting over one destination is the least useful pair")
check("and it plays", pen.lanes[0].isPressureEnabled)

var finger = DrawnQurveState()
finger.draw([S(0, 0), S(1, 1)], seconds: 1)
check("a stroke without pressure records none rather than a flat one",
      !finger.hasPressure(0), finger.summary(of: 0))

// Redrawing a Pencil curve with a finger keeps the pressure it had: you
// changed the line, not the device's abilities.
pen.draw([S(0, 1), S(1, 0)], seconds: 2)
check("redrawing without pressure keeps the pressure that was there",
      pen.hasPressure(0) && (pen.lanes[0].pressure?.value(atPhase: 0.5) ?? 0) > 0.85)
check("while the line takes the new shape",
      pen.lanes[0].curve.value(atPhase: 0) > 0.95)

// Muting pressure is not muting the lane.
pen.lanes[0].isPressureEnabled = false
check("pressure can be muted without muting the line it came from",
      pen.lanes[0].isEnabled && !pen.lanes[0].isPressureEnabled)

print("\n── the session ────────────────────────────────────")

state.isRunning = true
let encoded = try! JSONEncoder().encode(state)
let restored = try! JSONDecoder().decode(DrawnQurveState.self, from: encoded)
check("the session round-trips through JSON", restored == state)
check("including every lane's curve",
      restored.lanes[0].curve.table == state.lanes[0].curve.table)

// A session saved by a build with fewer lanes still opens.
let short = """
{"lanes":[{"curve":{"table":[0,1],"durationSeconds":1,"message":"controlChange",\
"controller":74,"channel":0,"minOut":0,"maxOut":1,"smoothing":0.08,"velocity":100,\
"phaseOffset":0,"isOneShot":false},"isEnabled":true,"pitchClasses":[],"root":0}],\
"selectedLane":0,"isRunning":false}
"""
let padded = try! JSONDecoder().decode(DrawnQurveState.self, from: Data(short.utf8))
check("a session with fewer lanes than this build has is padded, not refused",
      padded.lanes.count == 4 && padded.lanes[0].isEnabled)

print("\n── what a lane says about itself ──────────────────")

var described = DrawnQurveState()
described.draw([S(0, 0), S(1, 1)], seconds: 1.5)
check("a drawn CC lane names its controller, channel and length",
      described.summary(of: 0).contains("CC 74")
      && described.summary(of: 0).contains("ch 1")
      && described.summary(of: 0).contains("1.5s"),
      described.summary(of: 0))
check("and an empty one says so rather than lying about a length",
      described.summary(of: 3).contains("nothing drawn"),
      described.summary(of: 3))

print("\n\(failures == 0 ? "all checks passed" : "\(failures) of \(checks) FAILED")")
exit(failures == 0 ? 0 : 1)
