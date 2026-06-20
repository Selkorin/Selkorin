import SwiftUI

struct UpdatesSettingsView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var manager: UpdateManager

    private var currentVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "v\(v) (build \(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Обновления")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WAI.text)

            // Version info
            row("Текущая версия") {
                Text(currentVersion)
                    .font(.system(size: 13))
                    .foregroundStyle(WAI.textDim)
            }

            // Channel picker
            row("Канал") {
                Picker("", selection: Binding(
                    get: { manager.channel },
                    set: { manager.channel = $0; saveSettings() }
                )) {
                    ForEach(UpdateChannel.allCases, id: \.self) { ch in
                        Text(ch.displayName).tag(ch)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
            }

            // Auto-check toggle
            Toggle(isOn: Binding(
                get: { manager.autoCheck },
                set: { manager.autoCheck = $0; saveSettings() }
            )) {
                Text("Проверять автоматически")
                    .font(.system(size: 13))
                    .foregroundStyle(WAI.textDim)
            }
            .toggleStyle(.switch)
            .tint(WAI.accent)

            // Last checked
            row("Последняя проверка") {
                if let date = manager.lastChecked {
                    Text(date, style: .relative)
                        .font(.system(size: 12))
                        .foregroundStyle(WAI.textMuted)
                } else {
                    Text("Никогда")
                        .font(.system(size: 12))
                        .foregroundStyle(WAI.textMuted)
                }
            }

            Divider().overlay(WAI.line)

            // Status + check button
            HStack(spacing: 12) {
                statusBadge
                Spacer()
                Button {
                    Task { await manager.checkForUpdates(quiet: false) }
                } label: {
                    Text("Проверить обновления")
                        .font(.system(size: 13))
                        .foregroundStyle(WAI.text)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(WAI.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
                }
                .buttonStyle(.plain)
                .disabled(isCheckingOrDownloading)
            }

            // Show "View update" button if update is available but prompt was dismissed
            if case .updateAvailable(let info) = manager.state, !manager.showPrompt {
                Button {
                    manager.showPrompt = true
                } label: {
                    Text("Посмотреть обновление до \(info.version) →")
                        .font(.system(size: 12))
                        .foregroundStyle(WAI.accentBright)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch manager.state {
        case .idle:
            EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Проверка…").font(.system(size: 12)).foregroundStyle(WAI.textMuted)
            }
        case .updateAvailable(let info):
            Label("Доступна \(info.version)", systemImage: "arrow.down.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(WAI.accentBright)
        case .downloading(let p):
            HStack(spacing: 8) {
                ProgressView(value: p).frame(width: 80).controlSize(.small)
                Text("\(Int(p * 100))%").font(.system(size: 11)).foregroundStyle(WAI.textMuted)
            }
        case .installing:
            Label("Установка…", systemImage: "gearshape")
                .font(.system(size: 12))
                .foregroundStyle(WAI.textMuted)
        case .upToDate:
            Label("Установлена последняя версия", systemImage: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(WAI.success)
        case .failed(let e):
            Label(e, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(WAI.danger)
                .lineLimit(2)
        }
    }

    private var isCheckingOrDownloading: Bool {
        switch manager.state {
        case .checking, .downloading(_), .installing: return true
        default: return false
        }
    }

    private func saveSettings() {
        store.settings.updates = manager.exportSettings()
        store.settings.save()
    }

    private func row(_ label: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(WAI.textDim)
            Spacer()
            control()
        }
    }
}
