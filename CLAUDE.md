# Working on SwiftDrawnQurve

*Short on purpose. This is the fifth plug-in on a shared foundation and the
third kind — it neither generates a pattern nor transforms one, it loops a
gesture — so most of what you need to know is about the one line that makes all
three safe.*

---

## The two things that surprise everybody

**Nothing builds without the foundation checked out beside this repo.**

```bash
git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift
```

`Scripts/verify.sh` and `SwiftDrawnQurve.xcodeproj` both look in `$REPO/../enkerli-swift`;
override with `ENKERLI_SWIFT=...`. Without it every suite fails with that line
printed, which is deliberate — a suite that quietly passed without the foundation
would be checking nothing.

**Xcode's test targets reach almost nothing.** Everything real is either in the
`SwiftDrawnQurveExtension` target (extension-only membership) or in the package next
door. A green test action says the host app compiles. The real check is:

```bash
Scripts/verify.sh            # all suites
Scripts/verify.sh curves     # one
```

If you cannot run a terminal, say so plainly and ask for it to be run rather than
reporting a change as verified. Building both schemes is necessary and is not
sufficient.

---

## Where a change belongs

The question to ask about any new type is *would a third plug-in want this?*

| It is | Put it |
|---|---|
| Chords, scales, voice leading, progressions, **and rhythm algorithms** | `enkerli-swift` → `Sources/Theory` |
| A pattern, a note, measurement, curation of material | → `Sources/Carrier` |
| A control any plug-in could use | → `Sources/UI` |
| AU plumbing | → `Sources/Shell` |
| A render-thread capability — anything the kernel does per note | `Sources/Kernel` **and** its harness in `Tests/Kernel` |
| A drawn curve, or anything that performs one | `enkerli-swift` → `Sources/Carrier` |
| About looping a gesture as *this product* sees it | here |

**When in doubt, put it here.** Moving something down later is a `git mv` plus a
`public` sweep; moving it up is a compile error you find immediately. And a
foundation that grows by accident is the failure mode the whole layering exists
to prevent — see `PORTING.md` in [MelGen](https://github.com/Enkerli/MelGen),
which is where the reasoning lives.

Changing the foundation means changing another repo. Run *its* checks and
MelGen's `Scripts/verify.sh` too: MelGen is the other consumer, and a `public`
you narrow or a signature you change breaks it silently from here.

---

## Rules that are not negotiable

**The component triple is forever.** `aumi/DrwQ/Enke` — not `Dqau`, which is the
JUCE DrawnQurve's and would collide with the AUv3 that build ships. This project
was scaffolded by copying a sibling's project file, which had been copied from
another's, so it started life claiming somebody else's code several removes back.

This paragraph named *Serpe's* triple until 2026-09, having been copied along
with the file it describes — which is the same failure it warns about, in prose
instead of in a plist. `Scripts/verify.sh identity` reads the Info.plist and was
green the whole time, so nothing caught it; the check is on the identifier, not
on the sentence about it. `Scripts/verify.sh identity` exists because that exact class of mistake
already shipped once. Never change the triple. The check reads every sibling
checkout, JUCE `CMakeLists.txt` and Swift `Info.plist` alike.

**Nothing generates on the audio thread.** Generation produces a whole
progression off-thread and hands the kernel already-decided notes. This is
inherited from the shell and it is load-bearing.

**The decision is off-thread; only the lookup is on it.** This is the sentence
that keeps a transformer inside PORTING.md §8's invariant, and it is a rule
about where code goes, not a description. Anything that *thinks* — which set,
which direction, what a chord is — belongs in `SwiftDrawnQurveState` or in the
package's `Theory`. The render thread reads a 128-byte table. If you find
yourself wanting the kernel to decide something, you want a bigger table.

**A note a curve started must be ended by the same lane, on the channel it
started on.** A note lane walking up a scale that never releases fills a synth's
voices inside one loop and leaves them there — after this plug-in has been
removed from the chain. `Tests/Kernel/curves-main.mm` in the foundation package
covers that and three other shapes of it; run `Scripts/verify.sh kernel` after
touching anything in the render path.

**A lane emits at most one message per render block.** A message per frame is
48,000 control changes a second for a curve nobody can hear moving that fast.
Values are deduplicated too, so a flat curve sends one message rather than one
per block. If you find yourself wanting finer resolution, the question is
whether anything downstream could act on it.

**`Scripts/verify.sh curves` is not "the plug-in works".** This product IS the
render loop, and that half is C++ in the package. `verify.sh` reaches in and
runs the package's own kernel check for exactly that reason; a green from the
Swift half alone says almost nothing here.

---

## House style

The prose in this repo — comments, commit messages, documents — explains *why*,
records what was measured, and says plainly what is not known. A comment that
restates the code is noise; a comment naming the bug that made the code look like
that is the reason the file is readable a month later. When you are unsure
whether something works, write that down instead of rounding up. The README's
"What has not been done" section is the model.
