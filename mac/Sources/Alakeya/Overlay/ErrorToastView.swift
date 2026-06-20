import SwiftUI

// ============================================================
// ErrorToastView.swift — soft amber/red toast, ported from ErrorToast.jsx.
// ============================================================

struct ErrorToastView: View {
    let message: String
    let blocked: Bool
    var onDismiss: () -> Void
    var onOpenSettings: () -> Void

    @State private var opacity: Double = 1
    @State private var hasFaded = false

    private var accent: Color { blocked ? WAI.warning : WAI.danger }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(blocked ? "ДЕЙСТВИЕ ЗАБЛОКИРОВАНО" : "ОШИБКА")
                .font(.system(size: 11, weight: .medium)).tracking(2).foregroundStyle(accent)
            Text(message).font(.system(size: 14)).foregroundStyle(WAI.text).lineSpacing(2)
            HStack(spacing: 6) {
                Button("Закрыть", action: { fadeAndDismiss() })
                    .buttonStyle(.plain).foregroundStyle(WAI.textDim).font(.system(size: 13))
                if blocked {
                    Button("Открыть настройки", action: onOpenSettings)
                        .buttonStyle(.plain).foregroundStyle(WAI.text).font(.system(size: 13))
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .frame(width: 280, alignment: .leading)
        .background(Color(hex: 0x140C04, alpha: 0.85))
        .overlay(RoundedRectangle(cornerRadius: WAI.rLg).stroke(accent))
        .clipShape(RoundedRectangle(cornerRadius: WAI.rLg))
        .shadow(color: .black.opacity(0.5), radius: 12)
        .opacity(opacity)
        .task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            fadeAndDismiss()
        }
    }

    private func fadeAndDismiss() {
        guard !hasFaded else { return }
        hasFaded = true
        withAnimation(.easeOut(duration: 0.4)) { opacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { onDismiss() }
    }
}
