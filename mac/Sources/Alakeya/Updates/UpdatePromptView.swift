import SwiftUI

struct UpdatePromptView: View {
    let info: UpdateInfo
    @ObservedObject var manager: UpdateManager

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            card
                .frame(width: 460)
                .shadow(color: .black.opacity(0.6), radius: 40, y: 20)
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(WAI.accentBright)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Доступна новая версия")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(WAI.text)
                    Text("Alakeya \(info.version)")
                        .font(.system(size: 13))
                        .foregroundStyle(WAI.textMuted)
                }
                Spacer()
                let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Текущая: \(current)")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textMuted)
                    Text("Новая: \(info.version)")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.accentBright)
                }
            }
            .padding(20)

            Divider().overlay(WAI.line)

            // Release notes
            if !info.releaseNotes.isEmpty {
                ScrollView {
                    Text(info.releaseNotes)
                        .font(.system(size: 12))
                        .foregroundStyle(WAI.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }
                .frame(maxHeight: 140)
                Divider().overlay(WAI.line)
            }

            // Download progress
            if case .downloading(let p) = manager.state {
                VStack(spacing: 6) {
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .tint(WAI.accentBright)
                    Text("Загрузка… \(Int(p * 100))%")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textMuted)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                Divider().overlay(WAI.line)
            }

            // Actions
            HStack(spacing: 10) {
                Button {
                    manager.skipVersion(info.version)
                } label: {
                    Text("Пропустить версию")
                        .font(.system(size: 12))
                        .foregroundStyle(WAI.textMuted)
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    manager.dismissPrompt()
                } label: {
                    Text("Позже")
                        .font(.system(size: 13))
                        .foregroundStyle(WAI.textDim)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(WAI.surface)
                        .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
                }
                .buttonStyle(.plain)

                Button {
                    manager.downloadAndInstall(info)
                } label: {
                    Group {
                        if case .downloading(_) = manager.state {
                            Text("Загрузка…")
                        } else if case .installing = manager.state {
                            Text("Установка…")
                        } else {
                            Text("Обновить")
                        }
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(WAI.accent)
                    .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
                }
                .buttonStyle(.plain)
                .disabled({
                    if case .downloading(_) = manager.state { return true }
                    if case .installing = manager.state { return true }
                    return false
                }())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(WAI.surfaceStrong)
        .overlay(RoundedRectangle(cornerRadius: WAI.r2xl).stroke(WAI.lineStrong))
        .clipShape(RoundedRectangle(cornerRadius: WAI.r2xl))
    }
}
