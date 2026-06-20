import SwiftUI
import AppKit

// ============================================================
// MessageBubbleView.swift
// User: right-aligned bubble with accent border.
// Assistant: flat ChatGPT-style text + copy/like/dislike/more.
// ============================================================

struct MessageBubbleView: View {
    let message: ChatMessage
    /// Total chat panel width (rail + sidebar + content). Used for compact-mode layout.
    var chatWidth: CGFloat = 800
    var userName: String = "Вы"
    var userAvatar: NSImage? = nil
    var assistantName: String = "Алакея"
    var assistantAvatar: NSImage? = nil
    var onTapImage: (NSImage) -> Void = { _ in }

    @State private var activeRating: String? = nil

    private var isUser:    Bool { message.role == .user }
    private var hasText:   Bool { !message.content.isEmpty }
    private var hasImages: Bool { !message.images.isEmpty }
    /// Compact: reduce padding and remove left spacer when chat panel is narrow.
    private var isCompact: Bool { chatWidth < 460 }

    var body: some View {
        if isUser {
            userRow
        } else {
            assistantRow
        }
    }

    // ── User: right-aligned bubble ────────────────────────────

    private var userRow: some View {
        HStack(alignment: .bottom, spacing: 10) {
            Spacer(minLength: isCompact ? 0 : 72)
            VStack(alignment: .trailing, spacing: 6) {
                Text(userName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(WAI.textDim)
                if hasImages { imageGrid }
                if hasText   { userBubble }
            }
            avatar(userAvatar, fallback: "person.fill", accent: true)
        }
        .padding(.vertical, 1)
    }

    private var userBubble: some View {
        Text(message.content)
            .font(.system(size: 14.5, weight: .regular))
            .foregroundStyle(WAI.text)
            .multilineTextAlignment(.leading)
            .lineSpacing(3)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(userBubbleBG)
            .clipShape(BubbleShape())
            .contextMenu { copyMenuItem }
    }

    // ── Assistant: flat text + sources + actions ─────────────

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 11) {
            avatar(assistantAvatar, fallback: "sparkles", accent: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(assistantName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(WAI.text)
                    .padding(.bottom, 7)
                if hasImages { imageGrid.padding(.bottom, 8) }
                if hasText   { assistantContent }
                if !message.sources.isEmpty {
                    MessageSourcesView(sources: message.sources) { urlStr in
                        AlakeyaBrowser.shared.open(urlStr)
                    }
                    .padding(.top, 4)
                }
                if !message.fileAttachments.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(message.fileAttachments) { attachment in
                            CompactFileAttachmentView(attachment: attachment)
                        }
                    }
                    .padding(.top, 6)
                }
                assistantActions.padding(.top, 10)
            }
            .frame(maxWidth: 670, alignment: .leading)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(.vertical, 2)
        .onAppear {
            activeRating = FeedbackStore.shared.rating(for: message.id)
        }
    }

    private var assistantContent: some View {
        MarkdownRenderer(source: message.content) { url in
            AlakeyaBrowser.shared.open(url.absoluteString)
        }
        .textSelection(.enabled)
        .contextMenu { copyMenuItem }
    }

    private var assistantActions: some View {
        HStack(spacing: 12) {
            AssistantActionButton(icon: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            }
            AssistantActionButton(
                icon: "hand.thumbsup",
                isActive: activeRating == "good",
                activeColor: WAI.accentBright
            ) { toggleRating("good") }
            AssistantActionButton(
                icon: "hand.thumbsdown",
                isActive: activeRating == "bad",
                activeColor: .orange
            ) { toggleRating("bad") }
            moreMenu
        }
    }

    private func toggleRating(_ rating: String) {
        if activeRating == rating {
            activeRating = nil
            FeedbackStore.shared.clearRating(for: message.id)
        } else {
            activeRating = rating
            FeedbackStore.shared.setRating(rating, for: message.id)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message.content, forType: .string)
            } label: {
                Label("Копировать", systemImage: "doc.on.doc")
            }
            Divider()
            Button(action: {}) {
                Label("Посмотреть источники", systemImage: "doc.text.magnifyingglass")
            }.disabled(true)
            Button(action: {}) {
                Label("Ветка в новом чате", systemImage: "arrow.branch")
            }.disabled(true)
            Button(action: {}) {
                Label("Прочесть вслух", systemImage: "speaker.wave.2")
            }.disabled(true)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12))
                .foregroundStyle(Color.white.opacity(0.45))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    // ── Shared ────────────────────────────────────────────────

    @ViewBuilder
    private var copyMenuItem: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(message.content, forType: .string)
        } label: {
            Label("Копировать", systemImage: "doc.on.doc")
        }
    }

    // ── Image grid ────────────────────────────────────────────

    @ViewBuilder
    private var imageGrid: some View {
        let imgs = message.images.compactMap { NSImage(data: $0) }
        if imgs.count == 1 {
            imageTile(imgs[0], size: 140, overlayText: nil)
                .onTapGesture { onTapImage(imgs[0]) }
        } else if !imgs.isEmpty {
            multiImageGrid(imgs)
        }
    }

    private func imageTile(_ img: NSImage, size: CGFloat, overlayText: String?) -> some View {
        ZStack {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipped()
            if let t = overlayText {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.55))
                Text(t)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: overlayText != nil ? 10 : 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
    }

    private func multiImageGrid(_ imgs: [NSImage]) -> some View {
        let cell: CGFloat = 100
        let gap:  CGFloat = 4
        let shown   = Array(imgs.prefix(4))
        let extra   = max(0, imgs.count - 4)

        return LazyVGrid(
            columns: [GridItem(.fixed(cell), spacing: gap),
                      GridItem(.fixed(cell), spacing: gap)],
            spacing: gap
        ) {
            ForEach(Array(shown.enumerated()), id: \.offset) { i, img in
                let isOverflow = (i == shown.count - 1 && extra > 0)
                imageTile(img, size: cell, overlayText: isOverflow ? "+\(extra + 1)" : nil)
                    .onTapGesture { if !isOverflow { onTapImage(img) } }
            }
        }
        .frame(width: cell * 2 + gap)
    }

    // ── User bubble background ────────────────────────────────

    private var userBubbleBG: some View {
        WAI.accent.opacity(0.075)
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(WAI.accentBright.opacity(0.48), lineWidth: 1)
            )
    }

    private func avatar(_ image: NSImage?, fallback: String, accent: Bool) -> some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: fallback)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(accent ? WAI.accentBright : WAI.textDim)
            }
        }
        .frame(width: 36, height: 36)
        .background(Circle().fill(WAI.surfaceInset))
        .clipShape(Circle())
        .overlay(Circle().stroke(accent ? WAI.lineAccent : WAI.line, lineWidth: 1))
    }
}

// ── Bubble shape ───────────────────────────────────────────────

private struct BubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRoundedRect(in: rect, cornerSize: CGSize(width: 14, height: 14))
        return p
    }
}

// ── Assistant action button ────────────────────────────────────

private struct AssistantActionButton: View {
    let icon: String
    var isActive: Bool = false
    var activeColor: Color = WAI.accentBright
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(
                    isActive ? activeColor : Color.white.opacity(hovered ? 0.9 : 0.45)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
