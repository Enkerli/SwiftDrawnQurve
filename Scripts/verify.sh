#!/bin/bash
#
# Checks the parts of SwiftDrawnQurve that Xcode's test targets can't reach.
#
#   Scripts/verify.sh          # all suites
#   Scripts/verify.sh curves   # one suite
#
# Suites:
#   identity — the audio component triple is unique across every sibling
#              checkout, JUCE and Swift alike, and matches the host app's
#              lookup. First, because codes are forever and this project was
#              scaffolded from another one's.
#   curves   — what the plug-in decides: what each lane sends, and what a drawn
#              stroke becomes. The OTHER half — the render thread looping the
#              curve and emitting it — is C++ and lives in the foundation
#              package's own Scripts/check-kernel.sh, which this runs too,
#              because a green here with a broken kernel would be a lie by
#              omission. That is more true for this plug-in than any other: its
#              product IS the render loop.
#
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXT="$REPO/SwiftDrawnQurveExtension"
PACKAGE="${ENKERLI_SWIFT:-$REPO/../enkerli-swift}"
MUSIC_SUITE="${MUSIC_SUITE:-$REPO/../music-suite}"

BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT

which="${1:-all}"
status=0

PKG_BIN=""
build_package() {
    [ -n "$PKG_BIN" ] && return 0
    if [ ! -f "$PACKAGE/Package.swift" ]; then
        echo "FAIL: no foundation package at $PACKAGE"
        echo "      git clone https://github.com/Enkerli/enkerli-swift ../enkerli-swift"
        echo "      (or set ENKERLI_SWIFT=/path/to/enkerli-swift)"
        status=1
        return 1
    fi
    swift build --package-path "$PACKAGE" >/dev/null || {
        echo "FAIL: the foundation package did not build"; status=1; return 1; }
    PKG_BIN="$(swift build --package-path "$PACKAGE" --show-bin-path)"
}

# UI and Shell are left out — these suites are headless — and so are the
# package's own test targets, whose objects carry a second `main`.
# Shell is linked here, unlike in the other plug-ins' scripts: `NoteMap` lives
# in it and it is the thing this plug-in is about. That drags in `Kernel`, which
# is a C++ target — no .swiftmodule, just a module map SwiftPM generates beside
# its objects — so Swift has to be pointed at that and told to speak C++. This
# is the first of these scripts to link the shell at all, and therefore the
# first to need any of it.
package_flags() {
    build_package || return 1
    echo "-I $PKG_BIN/Modules"
    echo "-Xcc -fmodule-map-file=$PKG_BIN/Kernel.build/module.modulemap"
    echo "-Xcc -I$PACKAGE/Sources/Kernel/include"
    echo "-cxx-interoperability-mode=default"
    find "$PKG_BIN" -name "*.o" ! -path "*Tests.build/*" | sort
}

# Every extension source that does not need the AU shell: the session and what
# it derives. The two AU subclasses and the view need CoreAudioKit and a host,
# and are checked by building the schemes.
headless_sources() {
    find "$EXT/Curves" -name "*.swift" 2>/dev/null | sort
}

run_identity() {
    echo "── identity ───────────────────────────────────────"
    python3 "$REPO/Scripts/tests/component-identity.py" || status=1
}

run_curves() {
    echo "── curves ─────────────────────────────────────────"
    cp "$REPO/Scripts/tests/curves-main.swift" "$BUILD/main.swift"
    swiftc -Onone $(package_flags) $(headless_sources) "$BUILD/main.swift" \
        -o "$BUILD/curves" || { status=1; return 0; }
    "$BUILD/curves" || status=1
}

# The render-thread half, from the package that owns it. Running somebody else's
# check is unusual and is the right thing here: this is the first plug-in whose
# behaviour depends on the kernel doing something other than scheduling, and a
# green run that skipped it would be saying "the quantizer works" on the
# strength of the half that cannot produce a stuck note.
# The gaps register, from the package that holds it. A plug-in whose gaps are
# not written down has them anyway, and this repo is exactly the kind that would
# acquire some quietly: it was built in an afternoon.
run_gaps() {
    echo "── gaps (from the foundation package) ─────────────"
    if [ ! -x "$PACKAGE/Scripts/check-gaps.sh" ]; then
        echo "FAIL: no gaps check at $PACKAGE/Scripts/check-gaps.sh"
        status=1
        return 0
    fi
    "$PACKAGE/Scripts/check-gaps.sh" || status=1
}

run_kernel() {
    echo "── kernel (from the foundation package) ───────────"
    if [ ! -x "$PACKAGE/Scripts/check-kernel.sh" ]; then
        echo "FAIL: no kernel check at $PACKAGE/Scripts/check-kernel.sh"
        status=1
        return 0
    fi
    "$PACKAGE/Scripts/check-kernel.sh" || status=1
}

case "$which" in
    identity) run_identity ;;
    curves) run_curves ;;
    kernel) run_kernel ;;
    gaps) run_gaps ;;
    all) run_identity; run_curves; run_kernel; run_gaps ;;
    *) echo "unknown suite: $which"; exit 2 ;;
esac

echo
if [ $status -eq 0 ]; then echo "verify: OK"; else echo "verify: FAILURES"; fi
exit $status
