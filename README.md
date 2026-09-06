# SwiftDrawnQurve

An iOS/macOS **AUv3 MIDI processor** (`aumi DrwQ`) that turns a drawn line into
looping MIDI. Draw with a finger or a Pencil; the gesture becomes a curve that
loops at the speed you drew it, sending control changes, channel pressure, pitch
bend or notes. Four independent lanes.

The fifth plug-in on [`enkerli-swift`](https://github.com/Enkerli/enkerli-swift),
and the **third kind**: MelGen, ProgGenie and SwiftSerpe generate,
[SwiftPitchFold](https://github.com/Enkerli/SwiftPitchFold) transforms, and this
loops a gesture. The shared kernel grew a capability for it.

It is **not** the JUCE [DrawnQurve](https://github.com/Enkerli/DrawnQurve). That
one is `aumi Dqau`, ships on more formats, and has features this does not — see
below. This one is AUv3 only, macOS and iOS only, SwiftUI rather than WebView,
and a different four-character code and bundle id so both can be installed at
once and compared.

## Why native matters here more than anywhere else

For the other four plug-ins in this suite the SwiftUI interface is a preference.
Here it is the feature.

A drawing surface in a WebView receives pointer events through a bridge: the
coalescing is the browser's, predicted touches are gone, and Apple Pencil's
pressure and tilt never arrive at all. A SwiftUI `DragGesture` on the same glass
gets them natively. `PORTING.md` §0 argues this in the abstract — "native, no
WebView, no bridge" — and a plug-in whose entire input is a gesture is where the
argument stops being abstract.

## One rule, three jobs

The kernel schedules notes, rewrites incoming ones, and now loops drawn curves.
Three different dataflows, one invariant, and it only survives all three because
of where the line falls:

> **The decision is off-thread. Only the lookup is on it.**

A drawn stroke is resampled — once, in Swift, off the audio thread — into 256
normalised samples. The render thread indexes that table, interpolates, smooths,
maps and emits. It never allocates, never blocks, and never asks a question
whose answer is still being drawn.

The resampling is even **in time across the stroke**, not in distance along it,
so drawing slowly through the middle spends more of the loop there. That is what
a drawn automation curve should do, and it is not what arc-length resampling
gives you.

## Verifying

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh curves     # one suite
```

| Suite | Checks |
|---|---|
| `identity` | The component triple **and the bundle id** are unique across every sibling checkout, JUCE and Swift alike. Both are forever, and the second one is why: a Swift plug-in built with a JUCE build's bundle id does not appear in a host at all |
| `curves` | What the plug-in decides: what each lane sends, what a stroke becomes, and the scale mask a note lane hands the kernel |
| `kernel` | **The foundation package's own check, run from here.** The render loop — looping the curve, emitting it, and releasing notes it started |

That last row matters more here than in any sibling: **this plug-in's product is
the render loop.** A green from `curves` alone would be saying almost nothing.

## What is here, and what is the package

| File | Lines | What it is |
|---|---:|---|
| `Curves/DrawnQurveState.swift` | ~130 | Four lanes, and what a drawn stroke does to one |
| `UI/DrawnQurveMainView.swift` | ~300 | The drawing surface, the lane row, the settings |
| `AudioUnit/` (3 files) | ~180 | The session half of the audio unit, three overrides, the parameter tree |

A curve itself is `Carrier`'s `GestureCurve`; the playback is the kernel; the
scale masks are `Theory`'s `PitchClassSet`; the theme, metrics and controls are
the shared UI kit. **There is no engine in this repo.**

## Building

```bash
git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift
```

Then open `SwiftDrawnQurve.xcodeproj` (Xcode 27+, iOS/macOS 26.0+).

## Pencil pressure

A stroke that carries pressure produces **two curves from one gesture**: the line
you drew, and how hard you pressed while drawing it. They share a time base by
construction — sample *i* of each is the same instant — which is why they are
paired rather than drawn separately. A swell that arrives exactly where the line
peaks is something you play; two passes over the surface could only approximate
it.

The companion defaults to CC 2 (breath) rather than the line's controller, since
two curves fighting over one destination is the least useful thing a pair could
do. It can be muted without muting the line.

Where the input has no pressure — a mouse, a trackpad, a finger on a screen
without force — there is **no** companion, rather than a flat one pinned at
zero. "No pressure information" and "pressed evenly" are different facts.

`PressureCanvas.swift` is where this lives, and it is about a hundred lines: a
platform view, because `DragGesture` has location and nothing else. It also asks
for coalesced touches, which is the other half of what a bridge costs — the OS
captures at up to 240 Hz and delivers at 60.

## What has not been done

- **None of this has been heard on a device**, and for this plug-in that gap is
  wider than usual: the whole product is how a drawn gesture *feels* looping
  back, and nothing about a passing test suite speaks to that.
- **No Pencil tilt or azimuth.** Pressure took one file; tilt would take the
  same one. The question is whether a third curve per gesture is legible, not
  whether it is possible.
- **No X/Y grid quantization**, which the JUCE build has: snap the playhead to
  tick boundaries, or the value to grid levels.
- **No teach / CC-learn**, no per-lane speed or direction, no host sync for
  curves — a curve loops on its own recorded duration, not on beats.
- **One curve per lane.** The JUCE engine holds four "qurves" per lane so a note
  lane can sound polyphonically; here a lane is one line.
- **No smoothing on the first value.** Deliberate — easing up from zero opens
  every lane with a swoop nobody drew — but it means a lane's first message
  jumps to wherever the curve starts.

## The full register

The list above is this plug-in's. The shared gaps — host sync, theme choice,
presets, MIDI panic — and the **strategy** for which of them get built back live
in [GAPS.md](https://github.com/Enkerli/enkerli-swift/blob/main/GAPS.md) in the
foundation, along with the things we have decided *not* to build. `Scripts/verify.sh`
runs its staleness check, so this plug-in cannot quietly acquire gaps nobody
wrote down.

## Licence

Public domain, all the way down. See [LICENSE](LICENSE).
