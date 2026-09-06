//
//  DrawnQurveMainView.swift
//  SwiftDrawnQurveExtension
//
//  Draw a line. It loops.
//
//  This is the plug-in where the native port has the clearest argument, and it
//  is worth stating plainly because PORTING.md §0 makes it in the abstract. A
//  drawing surface in a WebView gets pointer events through a bridge: the
//  coalescing is the browser's, the predicted touches are gone, and Apple
//  Pencil's pressure and tilt never arrive at all. A SwiftUI `DragGesture` on
//  the same glass gets them natively. For every other plug-in in this suite the
//  native UI is a preference; here it is the feature.
//
//  What is shared is everything the drawing is not: the theme and its audited
//  palette, the metrics, the touch targets, `Eyebrow`, `ChipPicker`,
//  `LabelledSlider`. Four plug-ins' worth of interface decisions that this one
//  did not have to make.
//

import Combine
import SwiftUI
import Carrier
import Shell
import Theory
import UI

struct DrawnQurveMainView: View {
    var parameterTree: ObservableAUParameterGroup
    weak var audioUnit: DrawnQurveAudioUnit?

    @State private var state = DrawnQurveState()
    /// The stroke in progress, in normalised coordinates. Empty when not drawing.
    @State private var stroke: [(x: Double, y: Double)] = []
    @State private var strokeStarted: Date?
    @State private var phases: [Double?] = Array(repeating: nil, count: DrawnQurveState.laneCount)
    @Environment(\.colorScheme) private var colorScheme

    private let clock = Timer.publish(every: 1.0 / 30, on: .main, in: .common).autoconnect()
    private var theme: MelGenTheme { colorScheme == .dark ? .dark : .light }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MelGenMetrics.space3) {
                transport
                canvas
                laneRow
                laneSettings
            }
            .padding(MelGenMetrics.space3)
        }
        .background(theme.background)
        .onAppear { if let audioUnit { state = audioUnit.state } }
        .onReceive(clock) { _ in
            // Playheads only. Everything else redraws when it changes.
            if state.isRunning, let audioUnit { phases = audioUnit.phases }
        }
    }

    // MARK: - Running

    private var transport: some View {
        HStack(spacing: MelGenMetrics.space2) {
            Button {
                state.isRunning.toggle()
                if !state.isRunning { phases = Array(repeating: nil, count: DrawnQurveState.laneCount) }
                commit()
            } label: {
                Label(state.isRunning ? "Stop" : "Play",
                      systemImage: state.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(state.isRunning ? theme.accentText : theme.text)
                    .frame(maxWidth: .infinity, minHeight: MelGenMetrics.controlHeight)
                    .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .fill(state.isRunning ? theme.accent : theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .strokeBorder(theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            Button {
                // Erase this lane's curve, not its wiring. A flat line at the
                // middle is "nothing drawn", and the lane goes quiet.
                state.lanes[state.selectedLane].curve = {
                    var blank = state.lane.curve
                    blank = GestureCurve(table: Array(repeating: 0.5, count: GestureCurve.sampleCount),
                                         durationSeconds: blank.durationSeconds,
                                         message: blank.message,
                                         controller: blank.controller,
                                         channel: blank.channel,
                                         minOut: blank.minOut, maxOut: blank.maxOut,
                                         smoothing: blank.smoothing, velocity: blank.velocity,
                                         phaseOffset: blank.phaseOffset, isOneShot: blank.isOneShot)
                    return blank
                }()
                state.lanes[state.selectedLane].isEnabled = false
                commit()
            } label: {
                Image(systemName: "eraser")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: MelGenMetrics.controlHeight * 1.4,
                           height: MelGenMetrics.controlHeight)
                    .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .fill(theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .strokeBorder(theme.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Erase this lane's curve")
        }
    }

    // MARK: - The drawing surface

    private var canvas: some View {
        GeometryReader { geometry in
            let size = geometry.size
            Canvas { context, canvasSize in
                draw(in: &context, size: canvasSize)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if strokeStarted == nil {
                            strokeStarted = Date()
                            stroke = []
                        }
                        let x = min(1, max(0, value.location.x / max(1, size.width)))
                        // Screen y grows downward and a curve's 1 is the top,
                        // so this flips. Getting it wrong draws every gesture
                        // upside down, which is obvious on screen and silent in
                        // the MIDI.
                        let y = 1 - min(1, max(0, value.location.y / max(1, size.height)))
                        stroke.append((x: x, y: y))
                    }
                    .onEnded { _ in
                        // The gesture's own duration becomes the loop's length:
                        // a curve drawn slowly loops slowly. That is the whole
                        // premise, and it is why the clock starts on first
                        // contact rather than being a setting.
                        let seconds = max(0.1, -(strokeStarted?.timeIntervalSinceNow ?? -1))
                        state.draw(stroke, seconds: seconds)
                        stroke = []
                        strokeStarted = nil
                        commit()
                    }
            )
        }
        .frame(height: 260)
        .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall).fill(theme.sunken))
        .overlay(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
            .strokeBorder(theme.border, lineWidth: 1))
        .accessibilityLabel("Drawing surface")
        .accessibilityValue(state.summary(of: state.selectedLane))
        .accessibilityHint("Drag to draw a curve for the selected lane")
    }

    private func draw(in context: inout GraphicsContext, size: CGSize) {
        func point(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: x * size.width, y: (1 - y) * size.height)
        }

        // The unselected lanes behind, faintly: what else is playing is context
        // for what you are about to draw, and hiding it makes four lanes feel
        // like four plug-ins.
        for index in 0..<DrawnQurveState.laneCount where index != state.selectedLane {
            guard state.hasCurve(index), state.lanes[index].isEnabled else { continue }
            context.stroke(path(of: state.lanes[index].curve, in: size),
                           with: .color(theme.textMuted.opacity(0.25)), lineWidth: 1)
        }

        // The selected lane, or the stroke being drawn.
        if stroke.count > 1 {
            var live = Path()
            live.move(to: point(stroke[0].x, stroke[0].y))
            for sample in stroke.dropFirst() { live.addLine(to: point(sample.x, sample.y)) }
            context.stroke(live, with: .color(theme.accent), lineWidth: 2.5)
        } else if state.hasCurve(state.selectedLane) {
            context.stroke(path(of: state.lane.curve, in: size),
                           with: .color(theme.accent), lineWidth: 2)
        }

        // Playheads, one per running lane, on their own curve.
        for index in 0..<DrawnQurveState.laneCount {
            guard let phase = phases.indices.contains(index) ? phases[index] : nil,
                  state.hasCurve(index) else { continue }
            let value = state.lanes[index].curve.ranged(atPhase: phase)
            let at = point(phase, value)
            let dot = CGRect(x: at.x - 4, y: at.y - 4, width: 8, height: 8)
            context.fill(Path(ellipseIn: dot),
                         with: .color(index == state.selectedLane ? theme.accent : theme.textMuted))
        }
    }

    private func path(of curve: GestureCurve, in size: CGSize) -> Path {
        var path = Path()
        let steps = 128
        for step in 0...steps {
            let phase = Double(step) / Double(steps)
            let value = curve.ranged(atPhase: phase)
            let at = CGPoint(x: phase * size.width, y: (1 - value) * size.height)
            if step == 0 { path.move(to: at) } else { path.addLine(to: at) }
        }
        return path
    }

    // MARK: - The lanes

    private var laneRow: some View {
        HStack(spacing: 4) {
            ForEach(0..<DrawnQurveState.laneCount, id: \.self) { index in
                let isSelected = index == state.selectedLane
                Button {
                    state.selectedLane = index
                } label: {
                    VStack(spacing: 2) {
                        Text("\(index + 1)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(isSelected ? theme.accentText : theme.text)
                        Circle()
                            .fill(state.lanes[index].isEnabled && state.hasCurve(index)
                                  ? theme.accent : theme.border)
                            .frame(width: 5, height: 5)
                    }
                    .frame(maxWidth: .infinity, minHeight: MelGenMetrics.controlHeight)
                    .background(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .fill(isSelected ? theme.accent.opacity(0.9) : theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: MelGenMetrics.radiusSmall)
                        .strokeBorder(isSelected ? theme.accent : theme.border,
                                      lineWidth: isSelected ? 1.5 : 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Lane \(index + 1)")
                .accessibilityValue(state.summary(of: index))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }

    // MARK: - What the selected lane sends

    private var laneSettings: some View {
        VStack(alignment: .leading, spacing: MelGenMetrics.space2) {
            HStack {
                Eyebrow(text: "Lane \(state.selectedLane + 1)", theme: theme)
                Spacer(minLength: 0)
                ToggleChip(title: state.lane.isEnabled ? "Playing" : "Muted",
                           systemImage: state.lane.isEnabled ? "waveform" : "speaker.slash",
                           isOn: Binding(get: { state.lane.isEnabled },
                                         set: { state.lanes[state.selectedLane].isEnabled = $0
                                                commit() }),
                           theme: theme)
            }
            Text(state.summary(of: state.selectedLane))
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)

            ChipPicker(options: CurveMessage.allCases.map { ($0, $0.label) },
                       selection: Binding(get: { state.lane.curve.message },
                                          set: { state.lanes[state.selectedLane].curve.message = $0
                                                 commit() }),
                       theme: theme)

            if state.lane.curve.message == .controlChange {
                LabelledSlider(title: "Controller", lowLabel: "0", highLabel: "127",
                               value: Binding(get: { Double(state.lane.curve.controller) / 127 },
                                              set: { state.lanes[state.selectedLane].curve
                                                        .controller = Int(($0 * 127).rounded()) }),
                               theme: theme,
                               format: { "CC \(Int(($0 * 127).rounded()))" },
                               onCommit: { commit() })
            }

            if state.lane.curve.message == .note {
                ChipPicker(options: [(0, "Chromatic"), (7, "Major"), (5, "Pentatonic")],
                           selection: Binding(
                               get: { state.lane.pitchClasses.isEmpty ? 0
                                      : state.lane.pitchClasses.count },
                               set: { size in
                                   state.lanes[state.selectedLane].pitchClasses =
                                       size == 0 ? [] : PitchClassSet.family(size, root: 0)
                                   commit()
                               }),
                           theme: theme)
            }

            LabelledSlider(title: "Smoothing", lowLabel: "off", highLabel: "soft",
                           value: Binding(get: { state.lane.curve.smoothing },
                                          set: { state.lanes[state.selectedLane].curve.smoothing = $0 }),
                           theme: theme, onCommit: { commit() })

            LabelledSlider(title: "Range low", lowLabel: "0", highLabel: "max",
                           value: Binding(get: { state.lane.curve.minOut },
                                          set: { state.lanes[state.selectedLane].curve.minOut = $0 }),
                           theme: theme, onCommit: { commit() })
            LabelledSlider(title: "Range high", lowLabel: "0", highLabel: "max",
                           value: Binding(get: { state.lane.curve.maxOut },
                                          set: { state.lanes[state.selectedLane].curve.maxOut = $0 }),
                           theme: theme, onCommit: { commit() })
        }
    }

    private func commit() { audioUnit?.update(state: state) }
}
