import SwiftUI

// ============================================================
// SettingsView.swift — settings window, ported from SettingsWindow.jsx
// (6+1 tabs). Bindings persist via AgentStore.settings.
// ============================================================

struct SettingsView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var updateManager: UpdateManager
    var onClose: () -> Void

    @Binding var tab: String

    private let tabs: [(String, String, String)] = [
        ("profile", "Профиль", "person.crop.circle"),
        ("appearance", "Внешний вид", "paintbrush"),
        ("voice", "Голос", "waveform"),
        ("models", "Модели и API", "cpu"),
        ("skills", "Агенты и навыки", "person.2"),
        ("knowledge", "База знаний", "books.vertical"),
        ("connectors", "Подключения", "link"),
        ("permissions", "Разрешения", "lock.shield"),
        ("automation", "Автоматизация", "clock.arrow.2.circlepath"),
        ("memory", "Память и данные", "externaldrive"),
        ("developer", "Разработчик", "terminal"),
        ("updates", "Обновления", "arrow.triangle.2.circlepath"),
        ("about", "О программе", "info.circle"),
    ]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(WAI.line).frame(width: 1)
            ScrollView {
                content
                    .frame(maxWidth: 820, alignment: .topLeading)
                    .padding(32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(WAI.canvas)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onClose) {
                Label("Назад в ALAKEYA", systemImage: "chevron.left")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(WAI.textDim)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.bottom, 14)

            Text("Центр управления")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WAI.text)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)

            ForEach(tabs, id: \.0) { t in
                Button { tab = t.0 } label: {
                    Label(t.1, systemImage: t.2)
                        .font(.system(size: 12.5, weight: tab == t.0 ? .semibold : .regular))
                        .foregroundStyle(tab == t.0 ? WAI.text : WAI.textMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 36)
                        .background(tab == t.0 ? WAI.accentSoft : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                }.buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(14)
        .frame(width: 224, alignment: .topLeading)
        .background(WAI.sidebar)
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case "profile": ProfileSettingsView(store: store)
        case "appearance": appearance
        case "models": ModelsSettingsView(store: store)
        case "skills": SkillsSettingsView(store: store)
        case "knowledge": KnowledgeSettingsView()
        case "connectors": ConnectorsSettingsView()
        case "voice": VoiceSettingsView(store: store)
        case "permissions": permissions
        case "automation": automation
        case "memory": memory
        case "developer": developer
        case "updates": UpdatesSettingsView(store: store, manager: updateManager)
        default: about
        }
    }

    // ── sections ──────────────────────────────────────────
    private var appearance: some View {
        section("Внешний вид") {
            row("Акцент") {
                HStack(spacing: 8) {
                    ForEach([UInt32(0x3B82F6), 0x06B6D4, 0x8B5CF6, 0xEC4899, 0x4ADE80], id: \.self) { c in
                        Circle().fill(Color(hex: c)).frame(width: 26, height: 26)
                            .overlay(Circle().stroke(.white, lineWidth: store.settings.appearance.accentHex == c ? 2 : 0))
                            .onTapGesture {
                                store.settings.appearance.accentHex = c
                                WAI.accent = Color(hex: c); store.settings.save()
                            }
                    }
                }
            }
            row("Размер орба") { picker(["small", "medium", "large"], $store.settings.appearance.size)
                    .onChange(of: store.settings.appearance.size) { newSize in
                        let px: CGFloat = newSize == "small" ? 56 : newSize == "large" ? 120 : 72
                        UserDefaults.standard.set(Double(px), forKey: "alakeya.orb.size")
                    } }
            row("Тема") { picker(["system", "dark", "light"], $store.settings.appearance.theme) }
        }
    }

    private var permissions: some View {
        section("Разрешения") {
            permRow("Accessibility", PermissionsManager.shared.accessibilityGranted) { PermissionsManager.shared.requestAccessibility() }
            permRow("Screen Recording", PermissionsManager.shared.screenRecordingGranted) { _ = PermissionsManager.shared.requestScreenRecording() }
            permRow("Микрофон", PermissionsManager.shared.microphoneGranted) { Task { _ = await PermissionsManager.shared.requestMicrophone() } }
        }
    }

    private var automation: some View {
        section("Автоматизация") {
            toggleRow("Авто-подтверждать безопасные действия", Binding(
                get: { store.settings.automation.autoSafe },
                set: { store.settings.automation.autoSafe = $0
                       PolicyEngine.shared.mode = $0 ? .auto : .manual
                       store.settings.save() }))
            Text("Жёсткие лимиты (всегда спрашивать): отправка писем, удаление, платежи.")
                .font(.system(size: 12)).foregroundStyle(WAI.textMuted)
        }
    }

    private var memory: some View {
        VStack(alignment: .leading, spacing: 24) {
            MemorySettingsView()
            Divider().overlay(WAI.line)
            Button("Очистить журнал и правила") {
                store.activity = []; Store.shared.saveActivity([])
            }
            .buttonStyle(.plain)
            .foregroundStyle(WAI.danger)
            .font(.system(size: 13))
        }
    }

    private var developer: some View {
        section("Разработчик") {
            row("Модель") { Text(store.settings.developer.model).foregroundStyle(WAI.textDim) }
            Text("OPENAI_API_KEY читается из окружения. Без ключа работает офлайн-планировщик.")
                .font(.system(size: 12)).foregroundStyle(WAI.textMuted)
        }
    }

    private var about: some View {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        return section("О программе") {
            Text("Alakeya · v\(version) · 2026").foregroundStyle(WAI.text)
            Text("Нативный macOS-ассистент. Electron-референс — в /desktop.")
                .font(.system(size: 12)).foregroundStyle(WAI.textMuted)
        }
    }

    // ── helpers ───────────────────────────────────────────
    private func section(_ title: String, @ViewBuilder _ body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.system(size: 22, weight: .semibold)).foregroundStyle(WAI.text)
            body()
        }
    }
    private func row(_ label: String, @ViewBuilder _ control: () -> some View) -> some View {
        HStack { Text(label).font(.system(size: 13)).foregroundStyle(WAI.textDim); Spacer(); control() }
    }
    private func toggleRow(_ label: String, _ binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) { Text(label).font(.system(size: 13)).foregroundStyle(WAI.textDim) }
            .toggleStyle(.switch).tint(WAI.accent)
            .onChange(of: binding.wrappedValue) { _, _ in store.settings.save() }
    }
    private func picker(_ options: [String], _ binding: Binding<String>) -> some View {
        Picker("", selection: binding) { ForEach(options, id: \.self) { Text($0).tag($0) } }
            .pickerStyle(.segmented).frame(width: 240)
            .onChange(of: binding.wrappedValue) { _, _ in store.settings.save() }
    }
    private func permRow(_ label: String, _ granted: Bool, _ request: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(WAI.textDim)
            Spacer()
            if granted { Text("Выдано").foregroundStyle(WAI.success).font(.system(size: 12)) }
            else { Button("Выдать", action: request).buttonStyle(.plain).foregroundStyle(WAI.accentBright).font(.system(size: 12)) }
        }
    }
}
