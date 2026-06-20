import SwiftUI
import AppKit

// ============================================================
// PermissionCardView.swift — confirmation dialog, ported from
// PermissionCard.jsx. ⌘⏎ allow once · ⌘. / Esc cancel.
// ============================================================

struct PermissionCardView: View {
    let action: Action
    var onAllowOnce: () -> Void
    var onAlwaysAllow: () -> Void
    var onCancel: () -> Void

    private var riskColor: Color {
        switch action.risk { case .low: return WAI.success; case .medium: return WAI.accentBright; case .high: return WAI.warning }
    }
    private var riskLabel: String {
        switch action.risk { case .low: return "● Низкий риск"; case .medium: return "◆ Средний риск"; case .high: return "▲ Высокий риск" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Circle().fill(WAI.orbCore).frame(width: 44, height: 44).shadow(color: WAI.accentGlow, radius: 10)
                VStack(alignment: .leading, spacing: 4) {
                    Text("ПОДТВЕРЖДЕНИЕ ДЕЙСТВИЯ")
                        .font(.system(size: 11, weight: .medium)).tracking(2).foregroundStyle(WAI.textMuted)
                    Text(action.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(WAI.text)
                }
            }.padding(.bottom, 22)

            VStack(alignment: .leading, spacing: 12) {
                Text(action.description).font(.system(size: 14)).foregroundStyle(WAI.textDim).lineSpacing(3)
                if let code = action.code {
                    Text(code).font(WAI.mono).foregroundStyle(WAI.text)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WAI.accentSoft)
                        .overlay(RoundedRectangle(cornerRadius: WAI.rMd).stroke(WAI.lineAccent))
                        .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.03))
            .overlay(RoundedRectangle(cornerRadius: WAI.rLg).stroke(WAI.line))
            .clipShape(RoundedRectangle(cornerRadius: WAI.rLg))
            .padding(.bottom, 18)

            VStack(spacing: 0) {
                metaRow("Уровень риска", riskLabel, color: riskColor)
                metaRow("Обратимо", action.reversible ? "Да" : "Нет")
                metaRow("Затронет", action.scope)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white.opacity(0.02))
            .overlay(RoundedRectangle(cornerRadius: WAI.rMd).stroke(Color.white.opacity(0.05)))
            .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
            .padding(.bottom, 22)

            HStack(spacing: 8) {
                ghostButton("Отмена", action: onCancel)
                secondaryButton("Разрешить один раз", action: onAllowOnce)
                primaryButton("Всегда для \(action.target)", action: onAlwaysAllow)
            }

            Text("⌘ . отмена · ⌘ ⏎ разрешить")
                .font(.system(size: 11)).foregroundStyle(WAI.textMuted)
                .frame(maxWidth: .infinity).padding(.top, 12)
        }
        .padding(32)
        .frame(maxWidth: 420)
        .background(WAI.surfaceStrong)
        .overlay(RoundedRectangle(cornerRadius: WAI.r2xl).stroke(WAI.lineStrong))
        .clipShape(RoundedRectangle(cornerRadius: WAI.r2xl))
        .shadow(color: .black.opacity(0.7), radius: 30, y: 24)
        .background(KeyHandler(onAllow: onAllowOnce, onCancel: onCancel))
    }

    private func metaRow(_ label: String, _ value: String, color: Color = WAI.text) -> some View {
        HStack {
            Text(label).font(.system(size: 12)).foregroundStyle(WAI.textMuted)
            Spacer()
            Text(value).font(.system(size: 12)).foregroundStyle(color)
        }.padding(.vertical, 4)
    }

    private func ghostButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { btnLabel(t, WAI.textDim) }
            .buttonStyle(.plain)
            .overlay(RoundedRectangle(cornerRadius: WAI.rLg).stroke(WAI.lineStrong))
    }
    private func secondaryButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { btnLabel(t, WAI.text).background(Color.white.opacity(0.06)) }
            .buttonStyle(.plain)
            .overlay(RoundedRectangle(cornerRadius: WAI.rLg).stroke(WAI.lineStrong))
            .clipShape(RoundedRectangle(cornerRadius: WAI.rLg))
    }
    private func primaryButton(_ t: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            btnLabel(t, Color(hex: 0x001018), weight: .semibold)
                .background(LinearGradient(colors: [WAI.accent, WAI.accentDeep], startPoint: .top, endPoint: .bottom))
        }
        .buttonStyle(.plain)
        .clipShape(RoundedRectangle(cornerRadius: WAI.rLg))
        .shadow(color: WAI.accent.opacity(0.4), radius: 9)
    }
    private func btnLabel(_ t: String, _ c: Color, weight: Font.Weight = .medium) -> some View {
        Text(t).font(.system(size: 13, weight: weight)).foregroundStyle(c)
            .frame(maxWidth: .infinity).padding(.vertical, 12)
    }
}

// Catches ⌘⏎ and ⌘. / Esc at the window level.
private struct KeyHandler: NSViewRepresentable {
    let onAllow: () -> Void
    let onCancel: () -> Void
    func makeNSView(context: Context) -> NSView {
        let v = KeyView(); v.onAllow = onAllow; v.onCancel = onCancel
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class KeyView: NSView {
        var onAllow: (() -> Void)?
        var onCancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func keyDown(with event: NSEvent) {
            let cmd = event.modifierFlags.contains(.command)
            if event.keyCode == 53 || (cmd && event.charactersIgnoringModifiers == ".") { onCancel?(); return }
            if cmd && event.keyCode == 36 { onAllow?(); return }
            super.keyDown(with: event)
        }
    }
}
