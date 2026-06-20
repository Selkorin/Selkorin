import SwiftUI

struct BrowserAssistantMessage: Identifiable, Equatable {
    enum Role { case user, assistant, system }
    let id = UUID()
    let role: Role
    var text: String
    var createdAt: Date = Date()
}

struct BrowserAssistantPanel: View {
    let messages: [BrowserAssistantMessage]
    @Binding var input: String
    let isThinking: Bool
    let onSend: (String) -> Void
    let onClose: () -> Void
    let onExitFullFrame: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.18)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty && !isThinking { emptyState }
                    ForEach(messages) { messageBubble($0) }
                    if isThinking { thinkingBubble }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            inputArea
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.96))
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.white.opacity(0.10)).frame(width: 1)
        }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles").foregroundStyle(.blue)
            Text("Алакея").font(.system(size: 18, weight: .semibold))
            Spacer()
            Button { onExitFullFrame() } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
            }.buttonStyle(.plain).help("Вернуть чат")
            Button { onClose() } label: {
                Image(systemName: "xmark")
            }.buttonStyle(.plain).help("Скрыть панель")
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Чем помочь на этой странице?").font(.system(size: 17, weight: .semibold))
            Text("Могу объяснить страницу, найти нужную информацию, подготовить текст или помочь с действием в браузере.")
                .font(.system(size: 14)).foregroundStyle(.secondary).lineSpacing(3)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func messageBubble(_ message: BrowserAssistantMessage) -> some View {
        let isUser = message.role == .user
        return HStack {
            if isUser { Spacer(minLength: 30) }
            Text(message.text)
                .font(.system(size: 14.5)).lineSpacing(3)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(isUser ? Color.blue.opacity(0.22) : Color.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            if !isUser { Spacer(minLength: 30) }
        }
    }

    private var thinkingBubble: some View {
        HStack(spacing: 8) {
            ProgressView().scaleEffect(0.72)
            Text("Думаю...").font(.system(size: 14)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Спросите по странице...", text: $input, axis: .vertical)
                .textFieldStyle(.plain).focused($focused).lineLimit(1...5)
                .onSubmit { submit() }
            Button { submit() } label: {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
            }
            .buttonStyle(.plain)
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .padding(.horizontal, 18).padding(.bottom, 18).padding(.top, 10)
    }

    private func submit() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        onSend(text)
    }
}
