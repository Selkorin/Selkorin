import SwiftUI
import AppKit

// ============================================================
// ChatView.swift — main chat window content.
//
// Structure:
//   Normal mode:    [AgentSidebar] [Chat] [Browser 560px optional]
//   Full browser:   [BrowserPaneView full frame] [BrowserAssistantPanel optional]
// ============================================================

private struct AlakeyaOrbIcon: View {
    var size: CGFloat = 56
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.333, green: 0.839, blue: 1.0),
                            Color(red: 0.0, green: 0.518, blue: 0.706),
                            Color(red: 0.0, green: 0.302, blue: 0.471)
                        ],
                        center: .topLeading,
                        startRadius: 4,
                        endRadius: size
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: Color(red: 0.0, green: 0.518, blue: 0.706).opacity(0.35), radius: 16, y: 6)
            VStack(spacing: 4) {
                HStack(spacing: size * 0.16) {
                    Capsule()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: size * 0.11, height: size * 0.22)
                    Capsule()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: size * 0.11, height: size * 0.22)
                }
                Capsule()
                    .stroke(Color.white.opacity(0.95), lineWidth: 3)
                    .frame(width: size * 0.42, height: size * 0.20)
                    .mask(
                        Rectangle()
                            .frame(height: size * 0.13)
                            .offset(y: size * 0.05)
                    )
            }
            .offset(y: size * 0.03)
        }
        .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

struct ChatView: View {

    @ObservedObject var store: AgentStore
    @ObservedObject var updateManager: UpdateManager
    var onSubmit      : (String) -> Void
    var onVoiceStart  : () -> Void
    var onVoiceStop   : () -> Void
    var onClose       : () -> Void
    var onMinimize    : () -> Void = {}
    var onFullscreen  : () -> Void = {}
    var onBrowserToggle: (Bool) -> Void = { _ in }
    var onWidgetToggle: (() -> Void)? = nil

    @ObservedObject private var browser = AlakeyaBrowser.shared
    @ObservedObject private var profiles = ProfileStore.shared
    @ObservedObject private var skills = SkillStore.shared
    @ObservedObject private var agentProfiles = AgentProfileStore.shared
    @State private var text            = ""
    @State private var attachments     : [URL] = []
    @State private var previewImage    : NSImage? = nil
    @State private var isDragTargeted  = false
    @State private var inputTextHeight : CGFloat = 36
    @State private var sidebarOpen     = false
    @State private var agentsOpen      = false
    @State private var settingsTab     = "appearance"
    @State private var showsCreateAgent = false
    @State private var showsProfilePanel = false
    @State private var navigationExpanded = true
    @State private var isVoiceCompanionVisible = false
    @FocusState private var focused    : Bool

    // Traffic lights hover
    @State private var hoveringLights = false

    // ── Browser state machine ─────────────────────────────
    @State private var browserFullFrameMode = false
    @State private var browserAssistantPanelVisible = false
    @State private var browserAssistantInput = ""
    @State private var browserAssistantIsThinking = false
    @State private var browserAssistantMessages: [BrowserAssistantMessage] = []

    private var isListening: Bool { store.status == .listening }
    private var showsExpandedNavigation: Bool { navigationExpanded }

    // ── Root ─────────────────────────────────────────────

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                topBar
                    .zIndex(1)
                mainLayoutArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Full-screen image preview overlay ─────────
            if let img = previewImage {
                Color.black.opacity(0.78)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) { previewImage = nil }
                    }

                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(32)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .onAppear {
            focused = true
            agentProfiles.reload()
        }
        .onChange(of: browser.isPresented) { _, isPresented in
            onBrowserToggle(isPresented)
            // If browser closes while in full frame mode, exit it
            if !isPresented {
                browserFullFrameMode = false
                browserAssistantPanelVisible = false
            }
        }
        .onExitCommand {
            if isVoiceCompanionVisible {
                isVoiceCompanionVisible = false
                if isListening { onVoiceStop() }
            }
        }
        .sheet(isPresented: $showsCreateAgent) {
            CreateAgentSheet(store: store) { profile, avatarData in
                if let avatarData {
                    try? profiles.setAgentAvatar(avatarData, agentID: profile.id)
                }
                activateAgent(profile.id)
                showsCreateAgent = false
                agentsOpen = true
            }
        }
        .sheet(isPresented: $showsProfilePanel) {
            ProfileSettingsSheet(store: store, onClose: { showsProfilePanel = false })
        }
    }

    // ── Main layout state machine ─────────────────────────

    @ViewBuilder
    private var mainLayoutArea: some View {
        if browser.isPresented && browserFullFrameMode {
            browserFullFrameLayout
        } else {
            normalWorkspaceLayout
        }
    }

    // ── NORMAL MODE: chat + optional fixed-width browser ──

    @ViewBuilder
    private var normalWorkspaceLayout: some View {
        HStack(spacing: 0) {
            chatAreaLayout
                .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
                .clipped()
            if browser.isPresented {
                BrowserPaneView(
                    store: browser.store,
                    isFullFrame: false,
                    assistantPanelVisible: false,
                    onEnterFullFrame: { enterBrowserFullFrame(openAssistant: false) },
                    onExitFullFrame: { exitBrowserFullFrame() },
                    onToggleAssistantPanel: { toggleBrowserAssistantPanel() },
                    onCloseBrowser: { closeBrowser() }
                )
                .frame(width: 390)
                .frame(maxHeight: .infinity)
                .layoutPriority(0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── FULL BROWSER MODE ─────────────────────────────────

    private var browserFullFrameLayout: some View {
        GeometryReader { geo in
            let panelWidth = min(CGFloat(390), max(CGFloat(320), geo.size.width * 0.34))
            HStack(spacing: 0) {
                BrowserPaneView(
                    store: browser.store,
                    isFullFrame: true,
                    assistantPanelVisible: browserAssistantPanelVisible,
                    onEnterFullFrame: { enterBrowserFullFrame(openAssistant: false) },
                    onExitFullFrame: { exitBrowserFullFrame() },
                    onToggleAssistantPanel: { toggleBrowserAssistantPanel() },
                    onCloseBrowser: { closeBrowser() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottomTrailing) {
                    if !browserAssistantPanelVisible {
                        browserOrbButton
                            .padding(.trailing, 24)
                            .padding(.bottom, 24)
                    }
                }
                if browserAssistantPanelVisible {
                    BrowserAssistantPanel(
                        messages: browserAssistantMessages,
                        input: $browserAssistantInput,
                        isThinking: browserAssistantIsThinking,
                        onSend: { sendBrowserAssistantMessage($0) },
                        onClose: { toggleBrowserAssistantPanel() },
                        onExitFullFrame: { exitBrowserFullFrame() }
                    )
                    .frame(width: panelWidth)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // ── Chat area: sidebar + messages + input ─────────────

    @ViewBuilder
    private var chatAreaLayout: some View {
        HStack(spacing: 0) {
            if navigationExpanded && !store.showSettings {
                AgentSidebarView(
                    store: store,
                    agentsOpen: $agentsOpen,
                    sidebarOpen: $sidebarOpen,
                    showsExpandedNavigation: showsExpandedNavigation,
                    onStartChat: {}
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if sidebarOpen {
                SidebarView(store: store, isOpen: $sidebarOpen)
                    .transition(.opacity)
            }
            VStack(spacing: 0) {
                if store.showSettings {
                    SettingsView(
                        store: store,
                        updateManager: updateManager,
                        onClose: { store.showSettings = false },
                        tab: $settingsTab
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if agentsOpen {
                    AgentWorkspaceView(store: store) {
                        agentsOpen = false
                    }
                } else {
                    middleArea
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    inputBar
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
    }

    // ── Browser state machine helpers ─────────────────────

    private func enterBrowserFullFrame(openAssistant: Bool = false) {
        guard browser.isPresented else { return }
        withAnimation(.easeInOut(duration: 0.22)) {
            browserFullFrameMode = true
            browserAssistantPanelVisible = openAssistant
        }
    }

    private func exitBrowserFullFrame() {
        withAnimation(.easeInOut(duration: 0.22)) {
            browserFullFrameMode = false
            browserAssistantPanelVisible = false
        }
    }

    private func toggleBrowserAssistantPanel() {
        guard browserFullFrameMode else { return }
        withAnimation(.easeInOut(duration: 0.18)) {
            browserAssistantPanelVisible.toggle()
        }
    }

    private func closeBrowser() {
        withAnimation(.easeInOut(duration: 0.18)) {
            browserFullFrameMode = false
            browserAssistantPanelVisible = false
            browser.close()
        }
    }

    // ── AI panel send ─────────────────────────────────────

    private func sendBrowserAssistantMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        browserAssistantMessages.append(BrowserAssistantMessage(role: .user, text: trimmed))
        browserAssistantInput = ""
        browserAssistantIsThinking = true
        // TODO: connect to real agent pipeline
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            browserAssistantMessages.append(BrowserAssistantMessage(
                role: .assistant,
                text: "Команда получена: \(trimmed). TODO: подключить к основному pipeline агента."
            ))
            browserAssistantIsThinking = false
        }
    }

    // ── Orb button (full browser mode only) ──────────────

    private var browserOrbButton: some View {
        Button {
            guard browserFullFrameMode else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                browserAssistantPanelVisible = true
            }
        } label: {
            AlakeyaOrbIcon(size: 56)
        }
        .buttonStyle(.plain)
        .help("Открыть AI-панель")
    }

    // ── Background ────────────────────────────────────────

    private var windowBackground: some View {
        WAI.canvas
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // ── Top bar ───────────────────────────────────────────

    private var topBar: some View {
        HStack(alignment: .center, spacing: 0) {
            // Traffic lights
            HStack(spacing: 8) {
                Circle().fill(Color(red: 1, green: 0.27, blue: 0.23))
                    .frame(width: 12, height: 12)
                    .onTapGesture { onClose() }
                Circle().fill(Color(red: 1, green: 0.76, blue: 0.18))
                    .frame(width: 12, height: 12)
                    .onTapGesture { onMinimize() }
                Circle().fill(Color(red: 0.20, green: 0.85, blue: 0.33))
                    .frame(width: 12, height: 12)
                    .onTapGesture { onFullscreen() }
            }
            .padding(.leading, 10)
            .onHover { hoveringLights = $0 }

            // Sidebar toggle
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    navigationExpanded.toggle()
                }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(navigationExpanded ? WAI.accentBright : WAI.textDim)
            }
            .buttonStyle(.plain)
            .help(navigationExpanded ? "Скрыть боковую панель" : "Показать боковую панель")
            .padding(.leading, 10)

            Spacer()

            Text(screenTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(WAI.textDim)

            Spacer()

            Button {
                onWidgetToggle?()
            } label: {
                personaAsset(size: 30)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(WAI.surfaceInset))
                    .overlay(Circle().stroke(WAI.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Показать/скрыть виджет")
            .padding(.trailing, 8)

            // Browser toggle
            Button {
                if browser.isPresented {
                    closeBrowser()
                } else {
                    AlakeyaBrowser.shared.open()
                }
            } label: {
                Image(systemName: browser.isPresented ? "globe.desk.fill" : "globe.desk")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(browser.isPresented ? WAI.accentBright : WAI.textDim)
            }
            .buttonStyle(.plain)
            .help(browser.isPresented ? "Закрыть браузер" : "Открыть браузер")
            .padding(.trailing, 12)
        }
        .frame(height: 44)
        .background(WAI.surfaceStrong)
        .overlay(Rectangle().fill(WAI.line).frame(height: 1), alignment: .bottom)
    }

    private var screenTitle: String {
        if store.showSettings { return "Центр управления" }
        if agentsOpen { return "Мои агенты" }
        if sidebarOpen { return "История" }
        return store.sessions.first(where: { $0.id == store.activeSessionID })?.title
            ?? activeAssistantName
    }

    // ── Middle area (messages) ────────────────────────────

    private var middleArea: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                if isFreshChat {
                    chatEmptyState
                        .frame(maxWidth: .infinity)
                        .frame(height: geo.size.height)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            ForEach(store.messages) { msg in
                                MessageBubbleView(
                                    message: msg,
                                    chatWidth: geo.size.width,
                                    userName: profiles.user.name,
                                    userAvatar: profiles.userAvatar(),
                                    assistantName: activeAssistantName,
                                    assistantAvatar: profiles.agentAvatar(
                                        for: store.settings.models.activeSkillID
                                    )
                                ) { img in
                                    withAnimation(.easeOut(duration: 0.2)) { previewImage = img }
                                }
                                .frame(maxWidth: .infinity)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 28)
                        .frame(maxWidth: min(760, geo.size.width), alignment: .topLeading)
                    }
                }
                Color.clear
                    .frame(width: 0, height: 0)
                    .onChange(of: store.messages.count) { _, _ in
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("bottom")
                        }
                    }
            }
        }
    }

    private var isFreshChat: Bool {
        !store.messages.contains(where: { $0.role == .user })
    }

    private var activeAssistantName: String {
        if store.settings.models.activeSkillID == "general" { return "Алакея" }
        return agentProfiles.profile(for: store.settings.models.activeSkillID)?.name
            ?? skills.availableSkills.first(
                where: { $0.id == store.settings.models.activeSkillID }
            )?.title
            ?? "Алакея"
    }

    private var activeAgentRoleLabel: String {
        if store.settings.models.activeSkillID == "general" { return "помощник" }
        return agentProfiles.profile(for: store.settings.models.activeSkillID)?.roleLabel
            ?? "помощник"
    }

    private var welcomeTitle: String {
        "Привет, я твой \(activeAgentRoleLabel)."
    }

    private var chatEmptyState: some View {
        GeometryReader { geo in
            let compactHeight = geo.size.height < 590
            let heroSize: CGFloat = (compactHeight ? 72 : 104) * 0.9

            VStack {
                Spacer()
                welcomeAvatar(size: heroSize)
                    .frame(width: heroSize, height: heroSize)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func quickAction(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(WAI.accentBright)
                    .frame(height: 22)
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(WAI.textDim)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(WAI.surfaceInset)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WAI.line, lineWidth: 0.5))
            )
        }
        .buttonStyle(QuickActionButtonStyle())
    }

    @ViewBuilder
    private func welcomeAvatar(size: CGFloat) -> some View {
        if let image = profiles.agentAvatar(for: store.settings.models.activeSkillID) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                        .stroke(WAI.lineAccent, lineWidth: 1)
                )
                .shadow(color: WAI.accentGlow.opacity(0.24), radius: 14)
        } else {
            personaAsset(size: size)
        }
    }

    private var voiceCompanion: some View {
        VStack(spacing: 10) {
            if profiles.agentAvatar(for: store.settings.models.activeSkillID) != nil {
                welcomeAvatar(size: 144)
                    .frame(width: 144, height: 144)
            } else {
                OrbView(
                    state: store.assistantState,
                    emotion: store.orbEmotion,
                    size: 144
                )
                .frame(width: 144, height: 144)
                .shadow(color: WAI.accentGlow.opacity(0.28), radius: 18)
            }

            HStack(spacing: 7) {
                Image(systemName: isListening ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: isListening)
                Text(isListening ? "Слушаю…" : "Голосовой режим")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(WAI.accentBright)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WAI.surfaceStrong.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WAI.lineAccent, lineWidth: 1)
        )
        .shadow(color: WAI.accentGlow.opacity(0.24), radius: 20)
    }

    @ViewBuilder
    private func personaAsset(size: CGFloat) -> some View {
        if let url = Bundle.module.url(forResource: "pers_1", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: size * 0.55, weight: .medium))
                .foregroundStyle(WAI.accentBright)
        }
    }

    // ── Input bar ─────────────────────────────────────────

    private var inputBar: some View {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return HStack(spacing: 8) {
            Button {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = true
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.begin { response in
                    if response == .OK {
                        attachments.append(contentsOf: panel.urls)
                    }
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WAI.textDim)
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .help("Прикрепить файл")

            TextField("Напишите сообщение...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(WAI.text)
                .focused($focused)
                .lineLimit(1...6)
                .onSubmit { sendMessage() }

            Button {
                if hasText {
                    if isListening { onVoiceStop() }
                    sendMessage()
                } else {
                    isListening ? onVoiceStop() : onVoiceStart()
                }
            } label: {
                Image(systemName: hasText ? "arrow.up" : (isListening ? "waveform" : "mic.fill"))
                    .font(.system(size: hasText ? 14 : 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color(hex: 0x1D9BF0)))
                    .overlay(Circle().stroke(Color(hex: 0x4DB8FF).opacity(0.55), lineWidth: 1))
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .help(hasText ? "Отправить" : (isListening ? "Остановить запись" : "Голосовой режим"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: 760)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WAI.control)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(WAI.lineAccent, lineWidth: 1)
                )
        )
        .shadow(color: WAI.accentGlow.opacity(0.10), radius: 14, y: 4)
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(WAI.canvas)
    }

    // ── Actions ───────────────────────────────────────────

    private func sendMessage() {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.appendMessage(ChatMessage(role: .user, content: t))
        text = ""
        onSubmit(t)
    }

    private func activateAgent(_ id: String) {
        store.newChat(agentId: id)
        agentsOpen = false
        sidebarOpen = false
        store.showSettings = false
    }
}

// ── Private helpers ───────────────────────────────────────

private struct QuickActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
    }
}

private struct AttachmentDeleteButton: View {
    var action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.11, green: 0.61, blue: 0.94))
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.15), radius: 3)
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .scaleEffect(hovered ? 1.08 : 1.0)
            .animation(.easeOut(duration: 0.15), value: hovered)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
