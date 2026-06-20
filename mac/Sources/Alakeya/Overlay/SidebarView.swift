import SwiftUI

// ============================================================
// SidebarView.swift — chat history panel (240pt).
// Lives in HStack between the rail and the chat column.
// ============================================================

struct SidebarView: View {
    @ObservedObject var store: AgentStore
    @Binding var isOpen: Bool
    @State private var sessionToDelete: UUID? = nil

    private var sorted: [ChatSession] {
        store.sessions.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().background(WAI.line)
            sessionList
        }
        .frame(width: 240)
        .frame(maxHeight: .infinity)
        .overlay(
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1),
            alignment: .trailing
        )
        .alert("Удалить чат?", isPresented: Binding(
            get: { sessionToDelete != nil },
            set: { if !$0 { sessionToDelete = nil } }
        )) {
            Button("Удалить", role: .destructive) {
                if let id = sessionToDelete {
                    store.deleteSession(id: id)
                    sessionToDelete = nil
                }
            }
            Button("Отмена", role: .cancel) {
                sessionToDelete = nil
            }
        } message: {
            Text("История этого чата будет удалена без возможности восстановления.")
        }
    }

    // ── Header ────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 8) {
            Text("Чаты")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(WAI.text)

            Spacer()

            Button {
                store.newChat(agentId: store.settings.models.activeSkillID)
                withAnimation(.easeInOut(duration: 0.22)) { isOpen = false }
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(WAI.textDim)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(WAI.surfaceInset))
                    .overlay(Circle().stroke(WAI.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // ── Session list ──────────────────────────────────────

    private var sessionList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(sorted) { session in
                    SessionRow(
                        session: session,
                        isActive: session.id == store.activeSessionID,
                        onTogglePin: { store.togglePinnedSession(id: session.id) },
                        onDelete: { sessionToDelete = session.id }
                    )
                    .onTapGesture {
                        store.switchSession(id: session.id)
                        withAnimation(.easeInOut(duration: 0.22)) { isOpen = false }
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }
}

// ── Single session row ────────────────────────────────────────

private struct SessionRow: View {
    let session: ChatSession
    let isActive: Bool
    var onTogglePin: () -> Void
    var onDelete: () -> Void

    private var timeLabel: String {
        let diff = Date().timeIntervalSince(session.updatedAt)
        if diff < 86_400 {
            let df = DateFormatter()
            df.timeStyle = .short
            df.dateStyle = .none
            return df.string(from: session.updatedAt)
        } else {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .none
            return df.string(from: session.updatedAt)
        }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(.system(size: 13, weight: isActive ? .medium : .regular))
                    .foregroundStyle(isActive ? WAI.text : WAI.textDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(timeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(WAI.textMuted)
            }
            Spacer()
            if session.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WAI.accentBright)
                    .padding(.trailing, 8)
            }
            if isActive {
                Circle()
                    .fill(WAI.accentBright)
                    .frame(width: 5, height: 5)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isActive ? WAI.accentSoft : Color.clear)
        )
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .contextMenu {
            Button(action: onTogglePin) {
                Label(
                    session.isPinned ? "Открепить" : "Закрепить",
                    systemImage: session.isPinned ? "pin.slash" : "pin"
                )
            }
            Button(role: .destructive, action: onDelete) {
                Label("Удалить", systemImage: "trash")
            }
        }
    }
}
