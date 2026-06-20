import SwiftUI

// ============================================================
// AgentSidebarView.swift — Agent-centric sidebar
// Agents own chats. Each agent shows its threads when expanded.
// ============================================================

struct AgentSidebarView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject private var agentProfiles = AgentProfileStore.shared
    @ObservedObject private var profiles = ProfileStore.shared

    @State private var expandedAgentIDs = Set<String>()
    @State private var showsCreateAgent = false
    @State private var showsProfilePanel = false
    @State private var editingAgent: AgentProfile?
    @State private var editingAvatar: AgentAvatarTarget?
    @Binding var agentsOpen: Bool
    @Binding var sidebarOpen: Bool
    let showsExpandedNavigation: Bool
    var onStartChat: () -> Void = {}

    var body: some View {
        VStack(alignment: showsExpandedNavigation ? .leading : .center, spacing: 0) {
            headerView
            if showsExpandedNavigation { createAgentCard }
            agentList
            Spacer(minLength: 8)
            skillsButtonView.padding(.horizontal, 8)
            bottomBarView
        }
        .padding(.horizontal, 8)
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .background(WAI.sidebar)
        .overlay(Rectangle().fill(WAI.line).frame(width: 1), alignment: .trailing)
        .sheet(isPresented: $showsCreateAgent) {
            CreateAgentSheet(store: store) { profile, avatarData in
                if let avatarData {
                    try? profiles.setAgentAvatar(avatarData, agentID: profile.id)
                }
                doActivateAgent(profile.id)
                showsCreateAgent = false
                agentsOpen = true
            }
        }
        .sheet(isPresented: $showsProfilePanel) {
            ProfileSettingsSheet(store: store, onClose: { showsProfilePanel = false })
        }
        .sheet(item: $editingAgent) { profile in
            EditAgentSheet(store: store, profile: profile)
        }
        .sheet(item: $editingAvatar) { target in
            AvatarEditorView(
                store: store,
                title: "Аватар агента «\(target.name)»",
                initialImage: profiles.agentAvatar(for: target.id)
            ) { data in
                try profiles.setAgentAvatar(data, agentID: target.id)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            if showsExpandedNavigation {
                Text("ALAKEYA v2")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(WAI.accentBright)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, showsExpandedNavigation ? 12 : 8)
        .padding(.top, 11)
        .padding(.bottom, 4)
    }

    // MARK: - Create Agent button

    private var createAgentCard: some View {
        Button { showsCreateAgent = true } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(WAI.accentBright)
                Text("Создать агента")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WAI.text)
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(WAI.accentSoft.opacity(0.4))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WAI.accentSoft, lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .padding(.bottom, 6)
    }

    // MARK: - Agent list

    private var agentList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 4) {
                agentCardView(id: "general", name: "Алакея", isDefault: true)
                ForEach(agentProfiles.agents) { agent in
                    agentCardView(id: agent.id, name: agent.name, isDefault: false)
                }
                if agentProfiles.agents.isEmpty && showsExpandedNavigation {
                    emptyStateView
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("Создайте агентов для дизайна,\nкода, маркетинга или бизнес-задач.")
                .font(.system(size: 11.5))
                .foregroundStyle(WAI.textMuted)
                .multilineTextAlignment(.center)
                .padding(.vertical, 12)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Agent card

    private func agentCardView(id: String, name: String, isDefault: Bool) -> some View {
        let isExpanded = expandedAgentIDs.contains(id)
        let isActive = store.settings.models.activeSkillID == id
        let count = store.sessions.filter({ $0.agentId == id }).count

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button {
                    store.openLatestChat(for: id)
                    agentsOpen = false
                    sidebarOpen = false
                    store.showSettings = false
                } label: {
                    HStack(spacing: 9) {
                    if isDefault {
                        defaultAvatar(size: 32)
                    } else {
                        userAgentAvatar(id: id, size: 32)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(WAI.text).lineLimit(1)
                        if showsExpandedNavigation {
                            Text(isDefault ? "Основной агент" : "\(count) чатов")
                                .font(.system(size: 10.5)).foregroundStyle(WAI.textMuted)
                        }
                    }
                    Spacer(minLength: 4)
                    if showsExpandedNavigation {
                        if count > 0 {
                            Text("\(count)")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(WAI.textMuted)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
                        }
                    }
                    }
                    .padding(.leading, 10)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        if isExpanded { expandedAgentIDs.remove(id) }
                        else { expandedAgentIDs.insert(id) }
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(isExpanded ? WAI.accentBright : WAI.textMuted)
                        .frame(width: 34, height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "Скрыть чаты" : "Показать чаты")
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(isActive ? WAI.accentSoft.opacity(0.3) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(
                isActive ? WAI.accentSoft : Color.white.opacity(0.04), lineWidth: isActive ? 1 : 0.5))
            .contextMenu {
                if !isDefault, let profile = agentProfiles.profile(for: id) {
                    Button {
                        editingAgent = profile
                    } label: {
                        Label("Редактировать агента", systemImage: "pencil")
                    }
                }
                Button {
                    doCreateChat(id, name: name)
                } label: {
                    Label("Новый чат", systemImage: "bubble.left")
                }
            }

            if isExpanded {
                VStack(spacing: 2) {
                    let chats = store.sessions
                        .filter { $0.agentId == id }
                        .sorted {
                            if $0.isPinned != $1.isPinned { return $0.isPinned }
                            return $0.updatedAt > $1.updatedAt
                        }
                    if chats.isEmpty {
                        noChatsView(agentId: id, name: name)
                    } else {
                        ForEach(chats) { session in
                            threadRowView(session: session, agentId: id)
                        }
                    }
                }
                .padding(.leading, 12).padding(.vertical, 4)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isActive ? WAI.accentSoft.opacity(0.14) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? WAI.accentBright.opacity(0.48) : WAI.lineAccent, lineWidth: 1)
        )
    }

    // MARK: - Thread row

    @ViewBuilder
    private func threadRowView(session: ChatSession, agentId: String) -> some View {
        let isActive = store.activeSessionID == session.id
        EditableThreadRow(
            session: session,
            isActive: isActive,
            agentId: agentId,
            store: store,
            preview: sessionPreview(session),
            timeText: timeAgoStr(session.updatedAt),
            miniAvatar: { miniAgentAvatar(id: agentId, size: 18) },
            onSelect: {
                store.switchSession(id: session.id)
                agentsOpen = false
                sidebarOpen = false
                store.showSettings = false
            },
            onRename: { newTitle in
                store.renameSession(id: session.id, title: newTitle)
            },
            onChangeAvatar: {
                editingAvatar = AgentAvatarTarget(id: agentId, name: agentName(for: agentId))
            },
            onTogglePin: {
                store.togglePinnedSession(id: session.id)
            },
            onDelete: {
                store.deleteSession(id: session.id)
            }
        )
    }

    // MARK: - Empty + new chat

    private func noChatsView(agentId: String, name: String) -> some View {
        Text("Пока нет чатов")
            .font(.system(size: 11))
            .foregroundStyle(WAI.textFaint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
    }

    // MARK: - Bottom

    private var skillsButtonView: some View {
        Button {
            store.showSettings = true
            agentsOpen = false
            sidebarOpen = false
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox").font(.system(size: 13.5, weight: .medium))
                if showsExpandedNavigation {
                    Text("Навыки").font(.system(size: 12.5, weight: .medium))
                    Spacer()
                }
            }
            .foregroundStyle(store.showSettings ? WAI.accentBright : WAI.textDim)
            .frame(height: 36).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9).fill(store.showSettings ? WAI.accentSoft : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var bottomBarView: some View {
        HStack(spacing: 4) {
            Button {
                showsProfilePanel = true
                agentsOpen = false; sidebarOpen = false; store.showSettings = false
            } label: {
                HStack(spacing: 7) {
                    Group {
                        if let image = profiles.userAvatar() {
                            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 13)).foregroundStyle(WAI.textDim)
                        }
                    }
                    .frame(width: 24, height: 24).clipShape(Circle())
                    .overlay(Circle().stroke(WAI.line, lineWidth: 1))
                    if showsExpandedNavigation {
                        Text(profiles.user.name)
                            .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(WAI.text).lineLimit(1)
                    }
                }
                .padding(.horizontal, 8).frame(height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(showsProfilePanel ? WAI.accentSoft : Color.clear))
            }
            .buttonStyle(.plain)

            if showsExpandedNavigation { Spacer(minLength: 0) }

            Button {
                store.showSettings = true
                agentsOpen = false; sidebarOpen = false
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(store.showSettings ? WAI.accentBright : WAI.textDim)
                    .frame(width: 32, height: 32)
                    .background(RoundedRectangle(cornerRadius: 7).fill(store.showSettings ? WAI.accentSoft : Color.clear))
            }
            .buttonStyle(.plain).help("Настройки")
        }
        .padding(.horizontal, 8).padding(.bottom, 10)
    }

    // MARK: - Avatars

    private func defaultAvatar(size: CGFloat) -> some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(WAI.accentBright)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28).fill(WAI.accentSoft.opacity(0.3)))
    }

    private func userAgentAvatar(id: String, size: CGFloat) -> some View {
        if let img = profiles.agentAvatar(for: id) {
            return AnyView(
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
            )
        }
        return AnyView(
            Image(systemName: "person.crop.circle")
                .font(.system(size: size * 0.45)).foregroundStyle(WAI.textDim)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.28).fill(WAI.surfaceInset))
        )
    }

    // MARK: - Helpers

    private func sessionPreview(_ session: ChatSession) -> String? {
        guard let content = session.messages.last(where: { $0.role == .user })?.content else { return nil }
        let s = String(content.prefix(40)).replacingOccurrences(of: "\n", with: " ")
        return s.isEmpty ? nil : s
    }

    private func timeAgoStr(_ date: Date) -> String {
        let f = DateFormatter()
        let d = Date().timeIntervalSince(date)
        if d < 86400 {
            // Today — just hours:minutes
            f.dateFormat = "HH:mm"
            return f.string(from: date)
        }
        if d < 604800 {
            // This week — day + hour
            f.dateFormat = "E HH:mm"
            return f.string(from: date)
        }
        f.dateFormat = "dd.MM HH:mm"
        return f.string(from: date)
    }

    private func agentName(for id: String) -> String {
        if id == "general" { return "Алакея" }
        return agentProfiles.profile(for: id)?.name ?? "Агент"
    }

    private func doCreateChat(_ agentId: String, name: String) {
        store.newChat(agentId: agentId, title: "Новый чат с \(name)")
        expandedAgentIDs.insert(agentId)
    }

    private func miniAgentAvatar(id: String, size: CGFloat) -> some View {
        if id == "general" {
            return AnyView(
                Image(systemName: "sparkles")
                    .font(.system(size: size * 0.5, weight: .medium))
                    .foregroundStyle(WAI.accentBright)
                    .frame(width: size, height: size)
                    .background(RoundedRectangle(cornerRadius: size * 0.22).fill(WAI.accentSoft.opacity(0.3)))
            )
        }
        if let img = profiles.agentAvatar(for: id) {
            return AnyView(
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            )
        }
        return AnyView(
            Image(systemName: "person.crop.circle")
                .font(.system(size: size * 0.5)).foregroundStyle(WAI.textDim)
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: size * 0.22).fill(WAI.surfaceInset))
        )
    }

// MARK: - Editable Thread Row

private struct EditableThreadRow: View {
    let session: ChatSession
    let isActive: Bool
    let agentId: String
    @ObservedObject var store: AgentStore
    let preview: String?
    let timeText: String
    let miniAvatar: () -> any View
    let onSelect: () -> Void
    let onRename: (String) -> Void
    let onChangeAvatar: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false
    @State private var isRenaming = false
    @State private var renameText = ""
    @State private var showsMenu = false

    var body: some View {
        HStack(spacing: 10) {
            AnyView(miniAvatar())
                .frame(width: 22, height: 22)

            if isRenaming {
                TextField("", text: $renameText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundStyle(WAI.text)
                    .onSubmit {
                        let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !t.isEmpty { onRename(t) }
                        isRenaming = false
                    }
                    .onExitCommand { isRenaming = false }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title)
                        .font(.system(size: 12.5, weight: isActive ? .semibold : .medium))
                        .foregroundStyle(isActive ? WAI.text : WAI.textDim)
                        .lineLimit(1)
                    if let preview {
                        Text(preview)
                            .font(.system(size: 11))
                            .foregroundStyle(WAI.textMuted)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 6)

            if session.isPinned && !isHovered {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WAI.accentBright)
                    .frame(width: 18, height: 24)
            }

            if isHovered && !isRenaming {
                Button {
                    showsMenu.toggle()
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(showsMenu ? .white : WAI.textDim)
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(showsMenu ? WAI.accentSoft : Color.white.opacity(0.035))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(showsMenu ? WAI.lineAccent : WAI.line, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showsMenu, arrowEdge: .trailing) {
                    ThreadActionsMenu(
                        isPinned: session.isPinned,
                        onRename: {
                            showsMenu = false
                            renameText = session.title
                            isRenaming = true
                        },
                        onChangeAvatar: {
                            showsMenu = false
                            onChangeAvatar()
                        },
                        onTogglePin: {
                            showsMenu = false
                            onTogglePin()
                        },
                        onDelete: {
                            showsMenu = false
                            onDelete()
                        }
                    )
                }
            } else {
                Text(timeText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(WAI.textFaint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isActive ? WAI.accentSoft.opacity(0.25)
                      : isHovered ? WAI.surfaceInset : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isRenaming, !showsMenu else { return }
            onSelect()
        }
        .contextMenu {
            Button(session.isPinned ? "Открепить" : "Закрепить") { onTogglePin() }
            Button("Переименовать") {
                renameText = session.title
                isRenaming = true
            }
            Button("Изменить аватар") { onChangeAvatar() }
            Divider()
            Button("Удалить", role: .destructive) { onDelete() }
        }
        .onHover { inside in
            withAnimation(.easeOut(duration: 0.12)) { isHovered = inside }
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

private struct AgentAvatarTarget: Identifiable {
    let id: String
    let name: String
}

private struct ThreadActionsMenu: View {
    let isPinned: Bool
    let onRename: () -> Void
    let onChangeAvatar: () -> Void
    let onTogglePin: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            action("pencil", "Переименовать", action: onRename)
            action("photo", "Изменить аватар", action: onChangeAvatar)
            action(
                isPinned ? "pin.slash.fill" : "pin.fill",
                isPinned ? "Открепить" : "Закрепить",
                detail: isPinned ? "Чат закреплён" : nil,
                accent: true,
                action: onTogglePin
            )

            Rectangle()
                .fill(WAI.line)
                .frame(height: 1)
                .padding(.vertical, 2)

            action("trash", "Удалить", destructive: true, action: onDelete)
        }
        .padding(6)
        .frame(width: 204)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(WAI.surfaceStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WAI.lineAccent, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.38), radius: 18, y: 8)
    }

    private func action(
        _ icon: String,
        _ title: String,
        detail: String? = nil,
        accent: Bool = false,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(
                        destructive ? WAI.danger : (accent ? WAI.accentBright : WAI.textDim)
                    )
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(destructive ? WAI.danger : WAI.text)
                    if let detail {
                        Text(detail)
                            .font(.system(size: 9.5))
                            .foregroundStyle(WAI.accentBright)
                    }
                }
                Spacer()
                if accent && isPinned {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(WAI.accentBright)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: detail == nil ? 34 : 42)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(accent && isPinned ? WAI.accentSoft : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

    private func doActivateAgent(_ id: String) {
        store.newChat(agentId: id)
        agentsOpen = false
        sidebarOpen = false
        store.showSettings = false
        expandedAgentIDs.insert(id)
    }
}
