import SwiftUI
import AppKit

// ============================================================
// MessageSourcesView.swift — source chips below assistant messages.
// Shows compact domain chips. Click opens URL in AlakeyaBrowser.
// Only rendered when message.sources is non-empty.
// ============================================================

struct MessageSourcesView: View {
    let sources: [SourceReference]
    var onOpenURL: ((String) -> Void)? = nil

    @State private var showAll = false

    private var visible: [SourceReference] {
        showAll ? sources : Array(sources.prefix(4))
    }
    private var overflow: Int { max(0, sources.count - 4) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Divider + label
            HStack(spacing: 6) {
                Rectangle()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 1)
                    .frame(maxWidth: 28)
                Text("Источники")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.35))
                    .kerning(0.4)
            }

            // Chips row
            HStack(spacing: 6) {
                ForEach(visible) { src in
                    SourceChip(source: src) {
                        open(src.url)
                    }
                }
                if !showAll && overflow > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showAll = true }
                    } label: {
                        Text("+\(overflow)")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.5))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 6)
    }

    private func open(_ url: String) {
        if let handler = onOpenURL {
            handler(url)
        } else if let u = URL(string: url) {
            NSWorkspace.shared.open(u)
        }
    }
}

// MARK: - SourceChip

private struct SourceChip: View {
    let source: SourceReference
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                Image(systemName: source.sourceType.icon)
                    .font(.system(size: 9))
                    .foregroundStyle(Color.white.opacity(0.55))
                Text(source.domain)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.white.opacity(hovered ? 0.9 : 0.65))
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.white.opacity(hovered ? 0.10 : 0.06))
                    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(source.url, forType: .string)
            } label: {
                Label("Копировать ссылку", systemImage: "doc.on.doc")
            }
            Divider()
            Button {
                AlakeyaBrowser.shared.open(source.url)
            } label: {
                Label("Открыть в браузере Алакеи", systemImage: "safari")
            }
            Button {
                if let u = URL(string: source.url) { NSWorkspace.shared.open(u) }
            } label: {
                Label("Открыть в системном браузере", systemImage: "globe")
            }
        }
        .help(source.title.isEmpty ? source.url : "\(source.title)\n\(source.url)")
    }
}
