import SwiftUI

// ============================================================
// OnboardingView.swift — 6-step onboarding, ported from OnboardingFlow.jsx
// (Welcome → Voice → Permissions → Safety → Personalize → Ready).
// ============================================================

struct OnboardingView: View {
    var onComplete: (OnboardingResult) -> Void
    var onSkip: () -> Void

    @State private var step = 0
    @State private var accent: UInt32 = 0x06B6D4
    @State private var face = "friendly"
    @State private var showSkipAlert = false

    private let total = 6

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer()
            stepBody.frame(maxWidth: 420)
            Spacer()
            footer
        }
        .padding(28)
        .frame(width: 640, height: 520)
        .background(WAI.bg)
        .overlay(RoundedRectangle(cornerRadius: WAI.r2xl).stroke(WAI.lineStrong))
        .clipShape(RoundedRectangle(cornerRadius: WAI.r2xl))
        .alert("Пропустить онбординг?", isPresented: $showSkipAlert) {
            Button("Пропустить", role: .destructive) { onSkip() }
            Button("Продолжить", role: .cancel) { }
        } message: {
            Text("Вы сможете пройти его позже в настройках Алакеи.")
        }
    }

    private var header: some View {
        HStack {
            Text(String(format: "%02d / %02d", step + 1, total)).font(.system(size: 10, design: .monospaced)).foregroundStyle(WAI.textMuted)
            Spacer()
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule().fill(i <= step ? WAI.accent : Color.white.opacity(0.12))
                        .frame(width: i == step ? 16 : 8, height: 3)
                }
            }
            Spacer()
            Button { showSkipAlert = true } label: { Image(systemName: "xmark").foregroundStyle(WAI.textDim) }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private var stepBody: some View {
        switch step {
        case 0: welcome
        case 1: voice
        case 2: permissions
        case 3: safety
        case 4: personalize
        default: ready
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            OrbView(state: .idle, size: 96)
            Text("Знакомься, Alakeya.").font(.system(size: 28, weight: .semibold)).foregroundStyle(WAI.text)
            Text("Твой AI-компаньон для рабочего стола.\nГолосом, контекстом, всегда в углу.")
                .multilineTextAlignment(.center).foregroundStyle(WAI.textDim)
        }
    }

    private var voice: some View {
        VStack(spacing: 16) {
            OrbView(state: .listening, size: 80)
            Text("Скажи что-нибудь").font(.system(size: 28, weight: .semibold)).foregroundStyle(WAI.text)
            Text("Проверим, что Alakeya тебя слышит.").foregroundStyle(WAI.textDim)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Что Alakeya может").font(.system(size: 28, weight: .semibold)).foregroundStyle(WAI.text)
                .frame(maxWidth: .infinity, alignment: .center)
            permRow("Чтение экрана", "Чтобы понимать контекст") { _ = PermissionsManager.shared.requestScreenRecording() }
            permRow("Микрофон", "Для голосовых команд") { Task { _ = await PermissionsManager.shared.requestMicrophone() } }
            permRow("Управление UI", "Accessibility — включается по запросу") { PermissionsManager.shared.requestAccessibility() }
        }
    }

    private var safety: some View {
        VStack(spacing: 24) {
            OrbView(state: .waitingForConfirmation, size: 64)
            Text("Ты всегда контролируешь").font(.system(size: 28, weight: .semibold)).foregroundStyle(WAI.text)
            Text("Alakeya спрашивает перед отправкой,\nудалением или оплатой. Всегда.")
                .multilineTextAlignment(.center).foregroundStyle(WAI.textDim)
        }
    }

    private var personalize: some View {
        VStack(spacing: 20) {
            Text("Сделай своим").font(.system(size: 28, weight: .semibold)).foregroundStyle(WAI.text)
            OrbView(state: .idle, size: 72)
            HStack(spacing: 8) {
                ForEach([UInt32(0x3B82F6), 0x06B6D4, 0x8B5CF6, 0xEC4899, 0x4ADE80], id: \.self) { c in
                    Circle().fill(Color(hex: c)).frame(width: 28, height: 28)
                        .overlay(Circle().stroke(.white, lineWidth: accent == c ? 2 : 0))
                        .onTapGesture { accent = c; WAI.accent = Color(hex: c) }
                }
            }
        }
    }

    private var ready: some View {
        VStack(spacing: 24) {
            OrbView(state: .idle, size: 104)
            Text("Всё готово.").font(.system(size: 28, weight: .semibold)).foregroundStyle(WAI.text)
            Text("Скажи «Hey Alakeya» в любое время,\nили нажми на орб в углу.")
                .multilineTextAlignment(.center).foregroundStyle(WAI.textDim)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 && step < total - 1 {
                Button("Назад") { step -= 1 }.buttonStyle(.plain).foregroundStyle(WAI.textDim)
            }
            Spacer()
            Button(action: advance) {
                Text(step == 0 ? "Начать →" : step == total - 1 ? "Открыть Alakeya →" : "Продолжить →")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(hex: 0x001018))
                    .frame(minWidth: 200).padding(.vertical, 12)
                    .background(LinearGradient(colors: [WAI.accent, WAI.accentDeep], startPoint: .top, endPoint: .bottom))
                    .clipShape(RoundedRectangle(cornerRadius: WAI.rLg))
            }.buttonStyle(.plain)
        }
    }

    private func advance() {
        if step < total - 1 { step += 1 }
        else { onComplete(OnboardingResult(accent: accent, faceStyle: face)) }
    }

    private func permRow(_ label: String, _ desc: String, _ action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.system(size: 13, weight: .medium)).foregroundStyle(WAI.text)
                Text(desc).font(.system(size: 11)).foregroundStyle(WAI.textMuted)
            }
            Spacer()
            Button("Выдать", action: action).buttonStyle(.plain).foregroundStyle(WAI.accentBright).font(.system(size: 12))
        }
        .padding(12)
        .background(Color.white.opacity(0.03))
        .overlay(RoundedRectangle(cornerRadius: WAI.rMd).stroke(WAI.line))
        .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
    }
}
