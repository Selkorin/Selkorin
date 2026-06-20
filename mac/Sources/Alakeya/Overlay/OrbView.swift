import SwiftUI

// Friendly, state-driven ALAKEYA character.
// Built only from native SwiftUI shapes so it remains sharp at every size.
struct OrbView: View {
    let state: AssistantState
    var emotion: OrbEmotion = .neutral
    var size: CGFloat = 72
    var showsStatus = false
    var onTap: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPressed = false

    var body: some View {
        VStack(spacing: size >= 100 ? 16 : 9) {
            TimelineView(.animation(minimumInterval: reduceMotion ? 1 : 1 / 30)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                character(time: time)
            }
            .frame(width: size * 1.48, height: size * 1.48)

            if showsStatus, !state.statusText.isEmpty {
                HStack(spacing: 7) {
                    if state.isBusy {
                        Circle()
                            .fill(state.accentColor)
                            .frame(width: 6, height: 6)
                    }
                    Text(state.statusText)
                        .font(.system(size: size >= 100 ? 14 : 11, weight: .medium))
                        .foregroundStyle(state == .error ? WAI.coral : WAI.textDim)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard onTap != nil else { return }
            if !reduceMotion {
                withAnimation(.easeOut(duration: 0.10)) { isPressed = true }
                withAnimation(.easeOut(duration: 0.24).delay(0.10)) { isPressed = false }
            }
            onTap?()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityAddTraits(onTap == nil ? [] : .isButton)
    }

    private func character(time: TimeInterval) -> some View {
        let breath = reduceMotion ? 0 : sin(time * .pi * 2 / 4.6)
        let float = reduceMotion || state.isStill ? 0 : sin(time * .pi * 2 / 5.4) * size * 0.025
        let statePulse = reduceMotion || !state.isBusy ? 0 : sin(time * .pi * 2 / 1.7) * 0.012
        let scale = (1 + breath * 0.017 + statePulse) * (isPressed ? 0.92 : 1)

        return ZStack {
            ambientGlow
                .scaleEffect(1 + breath * 0.025)

            if state == .listening {
                listeningRings(time: time)
            }

            if state == .processing {
                progressArc(time: time)
            }

            blobShell(time: time)
                .frame(width: size, height: size)
                .overlay { face(time: time) }
                .overlay { stateSymbol(time: time) }
                .shadow(color: state.accentColor.opacity(0.28), radius: size * 0.18, y: size * 0.06)
                .scaleEffect(scale)
                .offset(y: float)

            if state == .thinking {
                thinkingDots(time: time)
                    .offset(y: -size * 0.69 + float)
            }

            if state == .success {
                successSparkle
                    .offset(x: size * 0.39, y: -size * 0.38)
            }

            if state == .offline {
                offlineBadge
                    .offset(x: size * 0.40, y: size * 0.38)
            }
        }
        .frame(width: size * 1.48, height: size * 1.48)
        .opacity(state == .offline ? 0.62 : 1)
        .saturation(state == .offline ? 0.55 : 1)
    }

    private var ambientGlow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [state.accentColor.opacity(0.30), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.72
                )
            )
            .frame(width: size * 1.46, height: size * 1.46)
            .blur(radius: size * 0.055)
    }

    private func blobShell(time: TimeInterval) -> some View {
        let morph = reduceMotion || state.isStill ? 0 : sin(time * .pi * 2 / 7.6)
        return OrganicOrbShape(morph: morph)
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: Color(hex: 0xB6ECF9), location: 0.00),
                        .init(color: Color(hex: 0x66C6E8), location: 0.17),
                        .init(color: Color(hex: 0x1E9ACB), location: 0.39),
                        .init(color: Color(hex: 0x0A7CAC), location: 0.56),
                        .init(color: Color(hex: 0x0C5C84), location: 0.74),
                        .init(color: Color(hex: 0x093E5E), location: 1.00),
                    ],
                    center: UnitPoint(x: 0.36, y: 0.28),
                    startRadius: 0,
                    endRadius: size * 0.92
                )
            )
            .overlay {
                OrganicOrbShape(morph: morph)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color(hex: 0x06263C, alpha: 0.82)],
                            startPoint: UnitPoint(x: 0.5, y: 0.46),
                            endPoint: .bottom
                        )
                    )
            }
            .overlay(alignment: .topLeading) {
                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [.white.opacity(0.92), .clear],
                            center: UnitPoint(x: 0.42, y: 0.40),
                            startRadius: 0,
                            endRadius: size * 0.18
                        )
                    )
                    .frame(width: size * 0.34, height: size * 0.27)
                    .offset(x: size * 0.13, y: size * 0.08)
                    .blur(radius: 0.5)
            }
    }

    private func face(time: TimeInterval) -> some View {
        let blinkPhase = time.truncatingRemainder(dividingBy: 6.2)
        let blinkScale: CGFloat = (!state.isStill && blinkPhase > 5.91 && blinkPhase < 6.06) ? 0.08 : 1
        let eyeShift: CGFloat = state == .thinking || state == .generating ? -size * 0.025 : 0

        return ZStack {
            HStack(spacing: size * 0.16) {
                eye(highlightOnLeft: true)
                eye(highlightOnLeft: true)
            }
            .scaleEffect(y: state == .listening ? 1.10 * blinkScale : blinkScale)
            .offset(y: -size * 0.055 + eyeShift)

            mouth
                .frame(width: size * 0.30, height: size * 0.17)
                .offset(y: size * 0.19)
        }
    }

    private func eye(highlightOnLeft: Bool) -> some View {
        Ellipse()
            .fill(Color(hex: 0xF2FCFF))
            .frame(width: size * 0.165, height: size * 0.226)
            .overlay(alignment: .topLeading) {
                if size >= 58 {
                    Ellipse()
                        .fill(Color(hex: 0x60C4E6, alpha: 0.50))
                        .frame(width: size * 0.05, height: size * 0.067)
                        .offset(x: size * 0.035, y: size * 0.035)
                }
            }
    }

    @ViewBuilder
    private var mouth: some View {
        switch state {
        case .error:
            OrbMouthShape(kind: .concerned)
                .stroke(Color(hex: 0xF2FCFF), style: mouthStroke)
        case .thinking, .generating, .processing, .vectorizing:
            OrbMouthShape(kind: .softFlat)
                .stroke(Color(hex: 0xF2FCFF), style: mouthStroke)
        case .speaking:
            OrbMouthShape(kind: .neutral)
                .stroke(Color(hex: 0xF2FCFF), style: mouthStroke)
        case .success:
            OrbMouthShape(kind: .bigSmile)
                .stroke(Color(hex: 0xF2FCFF), style: mouthStroke)
        default:
            OrbMouthShape(kind: .smile)
                .stroke(Color(hex: 0xF2FCFF), style: mouthStroke)
        }
    }

    private var mouthStroke: StrokeStyle {
        StrokeStyle(lineWidth: max(2, size * 0.04), lineCap: .round, lineJoin: .round)
    }

    @ViewBuilder
    private func stateSymbol(time: TimeInterval) -> some View {
        switch state {
        case .generating:
            Image(systemName: "photo")
                .font(.system(size: size * 0.19, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .offset(y: size * 0.30)
        case .processing:
            Image(systemName: "doc.text.fill")
                .font(.system(size: size * 0.18, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .offset(y: size * 0.30)
        case .vectorizing:
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: size * 0.19, weight: .medium))
                .foregroundStyle(.white.opacity(0.94))
                .offset(y: size * 0.30)
        case .speaking:
            speakingBars(time: time)
                .offset(y: size * 0.30)
        default:
            EmptyView()
        }
    }

    private func thinkingDots(time: TimeInterval) -> some View {
        HStack(spacing: size * 0.075) {
            ForEach(0..<3, id: \.self) { index in
                ThinkingOrbDot(
                    time: time,
                    index: index,
                    size: size,
                    reduceMotion: reduceMotion
                )
            }
        }
    }

    private func listeningRings(time: TimeInterval) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let raw = (time / 2.6 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                Circle()
                    .stroke(WAI.accentBright.opacity(reduceMotion ? 0.34 : 0.48 * (1 - raw)), lineWidth: 1.5)
                    .frame(width: size, height: size)
                    .scaleEffect(reduceMotion ? 1.18 : 0.82 + raw * 0.82)
            }
        }
    }

    private func progressArc(time: TimeInterval) -> some View {
        Circle()
            .trim(from: 0, to: 0.24)
            .stroke(WAI.accentBright, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: size * 1.17, height: size * 1.17)
            .rotationEffect(.degrees(reduceMotion ? -55 : time * 110))
    }

    private func speakingBars(time: TimeInterval) -> some View {
        HStack(spacing: size * 0.025) {
            ForEach(0..<5, id: \.self) { index in
                let phase = sin(time * 9 + Double(index) * 0.9)
                Capsule()
                    .fill(.white.opacity(0.94))
                    .frame(width: max(2, size * 0.025), height: size * (0.07 + CGFloat(abs(phase)) * 0.08))
            }
        }
    }

    private var successSparkle: some View {
        Image(systemName: "sparkle")
            .font(.system(size: size * 0.23, weight: .semibold))
            .foregroundStyle(Color(hex: 0xCFF3FF))
    }

    private var offlineBadge: some View {
        Image(systemName: "wifi.slash")
            .font(.system(size: size * 0.14, weight: .semibold))
            .foregroundStyle(WAI.textDim)
            .frame(width: size * 0.32, height: size * 0.32)
            .background(Circle().fill(Color(hex: 0x1B2128)))
            .overlay(Circle().stroke(Color(hex: 0x2A3138), lineWidth: 2))
    }
}

private struct ThinkingOrbDot: View {
    let time: TimeInterval
    let index: Int
    let size: CGFloat
    let reduceMotion: Bool

    var body: some View {
        let angle = time * Double.pi * 2 / 1.4 - Double(index) * 0.8
        let phase = max(0, sin(angle))
        let offset = reduceMotion ? CGFloat.zero : -CGFloat(phase) * size * 0.08
        let opacity = 0.52 + phase * 0.48

        Circle()
            .fill(WAI.accentBright)
            .frame(width: size * 0.07, height: size * 0.07)
            .offset(y: offset)
            .opacity(opacity)
    }
}

private struct OrganicOrbShape: Shape {
    var morph: Double

    var animatableData: Double {
        get { morph }
        set { morph = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let inset = rect.width * 0.025
        let r = rect.insetBy(dx: inset, dy: inset)
        let m = CGFloat(morph) * rect.width * 0.018
        var path = Path()
        path.move(to: CGPoint(x: r.midX, y: r.minY + m))
        path.addCurve(
            to: CGPoint(x: r.maxX - m, y: r.midY),
            control1: CGPoint(x: r.maxX * 0.78, y: r.minY - m),
            control2: CGPoint(x: r.maxX + m, y: r.height * 0.25)
        )
        path.addCurve(
            to: CGPoint(x: r.midX, y: r.maxY - m),
            control1: CGPoint(x: r.maxX - m, y: r.height * 0.78),
            control2: CGPoint(x: r.width * 0.76, y: r.maxY + m)
        )
        path.addCurve(
            to: CGPoint(x: r.minX + m, y: r.midY),
            control1: CGPoint(x: r.width * 0.25, y: r.maxY - m),
            control2: CGPoint(x: r.minX - m, y: r.height * 0.76)
        )
        path.addCurve(
            to: CGPoint(x: r.midX, y: r.minY + m),
            control1: CGPoint(x: r.minX + m, y: r.height * 0.23),
            control2: CGPoint(x: r.width * 0.22, y: r.minY + m)
        )
        path.closeSubpath()
        return path
    }
}

private enum OrbMouthKind {
    case smile
    case bigSmile
    case softFlat
    case concerned
    case neutral
}

private struct OrbMouthShape: Shape {
    let kind: OrbMouthKind

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch kind {
        case .smile:
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.28))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.height * 0.28),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
        case .bigSmile:
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.18))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.height * 0.18),
                control: CGPoint(x: rect.midX, y: rect.maxY * 1.08)
            )
        case .softFlat:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.midY),
                control: CGPoint(x: rect.midX, y: rect.height * 0.42)
            )
        case .concerned:
            path.move(to: CGPoint(x: rect.minX, y: rect.height * 0.72))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.height * 0.72),
                control: CGPoint(x: rect.midX, y: rect.minY)
            )
        case .neutral:
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
        return path
    }
}
