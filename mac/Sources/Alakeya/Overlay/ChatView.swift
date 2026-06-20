import SwiftUI
import AppKit

// ============================================================
// ChatView.swift — main chat window content.
//
// Structure:
//   Top bar:   [● ● ●]  Alakeya  |  Настройки
//   Middle:    messages
//   Input bar: text field | mic | send
// ============================================================

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

    // ── Browser split layout ──────────────────────────────
    // Constraints (px)
    private let kMinBrowserWidth:     CGFloat = 360
    // This is the whole chat side, including the 240 pt agent sidebar.
    // Reserving only the conversation width used to collapse messages to a
    // narrow strip whenever an old, oversized browser width was restored.
    private let kMinChatPanelWidth:   CGFloat = 640
    private let kIdealChatPanelWidth: CGFloat = 760
    private let kDefaultBrowserWidth: CGFloat = 680
    private let kDividerHitWidth:     CGFloat = 12    // comfortable hit area

    // Persisted sidebar width (UserDefaults)
    @AppStorage("browserSidebarWidth") private var savedBrowserWidth: Double = 600

    // Live width used during the session — initialized from savedBrowserWidth on appear
    @State private var browserWidth: CGFloat = 600

    // Drag + hover state
    @State private var isDraggingDivider  = false
    @State private var dividerDragStart:   CGFloat = 0
    @State private var isDividerHovered   = false

    private var isListening: Bool { store.status == .listening }
    // One source of truth: the header button always controls the rail.
    // Individual workspaces handle narrow widths internally.
    private var showsExpandedNavigation: Bool { navigationExpanded }

    // ── Root ─────────────────────────────────────────────

    var body: some View {
        ZStack {
            // ── TopBar (full width) + content row ─────────
            VStack(spacing: 0) {
                topBar
                    .zIndex(1)
                GeometryReader { geo in
                    let reservedChatWidth = min(
                        kIdealChatPanelWidth,
                        max(kMinChatPanelWidth, geo.size.width * 0.46)
                    )
                    let maxBW = max(
                        kMinBrowserWidth,
                        geo.size.width - reservedChatWidth - kDividerHitWidth
                    )
                    let effectiveBW = max(kMinBrowserWidth, min(maxBW, browserWidth))
                    let chatPanelW = geo.size.width - (browser.isPresented ? effectiveBW + kDividerHitWidth : 0)

                    HStack(spacing: 0) {
                        // ── Chat area — always fills remaining space ───────
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
                                    middleArea(chatW: chatPanelW)
                                    inputBar(chatW: chatPanelW)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // ── Resizable browser panel — always in hierarchy ──
                        // WKWebView never removed → page state survives show/hide/resize.
                        HStack(spacing: 0) {
                            // Draggable divider: 10 px hit area, 1 px visual line.
                            // Hover → highlight + resize cursor.
                            // Double-click → reset to default width.
                            ZStack {
                                Rectangle()
                                    .fill((isDraggingDivider || isDividerHovered)
                                          ? WAI.accent.opacity(0.45)
                                          : Color.white.opacity(0.08))
                                    .frame(width: 1)
                            }
                            .frame(width: kDividerHitWidth)
                            .contentShape(Rectangle())
                            .onHover { inside in
                                isDividerHovered = inside
                                if inside { NSCursor.resizeLeftRight.push() }
                                else      { NSCursor.pop() }
                            }
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    browserWidth = min(kDefaultBrowserWidth, maxBW)
                                }
                                savedBrowserWidth = Double(browserWidth)
                            }
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        if !isDraggingDivider {
                                            isDraggingDivider = true
                                            dividerDragStart  = browserWidth
                                        }
                                        let newW = dividerDragStart - value.translation.width
                                        browserWidth = max(kMinBrowserWidth, min(maxBW, newW))
                                        #if DEBUG
                                        let chatW = geo.size.width - browserWidth - kDividerHitWidth
                                        print("[Split] avail=\(Int(geo.size.width)) chat=\(Int(chatW)) browser=\(Int(browserWidth)) maxBW=\(Int(maxBW))")
                                        #endif
                                    }
                                    .onEnded { _ in
                                        isDraggingDivider = false
                                        savedBrowserWidth = Double(browserWidth)
                                    }
                            )

                            BrowserPaneView(store: browser.store)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(
                            width: browser.isPresented ? effectiveBW + kDividerHitWidth : 0,
                            alignment: .leading
                        )
                        .clipped()
                    }
                    .onChange(of: geo.size) { _, newSize in
                        let reserved = min(
                            kIdealChatPanelWidth,
                            max(kMinChatPanelWidth, newSize.width * 0.46)
                        )
                        let clampedMax = max(
                            kMinBrowserWidth,
                            newSize.width - reserved - kDividerHitWidth
                        )
                        if browserWidth > clampedMax {
                            browserWidth = clampedMax
                            savedBrowserWidth = Double(clampedMax)
                        }
                        #if DEBUG
                        let mBW = clampedMax
                        let eBW = max(kMinBrowserWidth, min(mBW, browserWidth))
                        let cW  = newSize.width - (browser.isPresented ? eBW + kDividerHitWidth : 0)
                        print("[Layout] avail=\(Int(newSize.width))×\(Int(newSize.height)) chatW=\(Int(cW)) browserW=\(Int(eBW)) maxBW=\(Int(mBW)) browser=\(browser.isPresented)")
                        #endif
                    }
                }
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
            let restored = CGFloat(savedBrowserWidth)
            browserWidth = restored.isFinite && restored >= kMinBrowserWidth
                ? restored
                : kDefaultBrowserWidth
            agentProfiles.reload()
        }
        .onChange(of: browser.isPresented) { _, isPresented in
            onBrowserToggle(isPresented)
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
                personaAsset(size: 24)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(WAI.surfaceInset))
                    .overlay(Circle().stroke(WAI.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Показать/скрыть виджет")
            .padding(.trailing, 8)

            // Browser toggle
            Button {
                if browser.isPresented {
                    AlakeyaBrowser.shared.close()
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

    private func middleArea(chatW: CGFloat) -> some View {
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
                                    chatWidth: chatW,
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
                        .frame(maxWidth: min(760, chatW), alignment: .topLeading)
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

    private func inputBar(chatW: CGFloat) -> some View {
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
        .frame(maxWidth: min(760, chatW))
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
