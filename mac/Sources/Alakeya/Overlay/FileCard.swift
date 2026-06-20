import SwiftUI
import AppKit

// ============================================================
// FileCard.swift — shown in chat after a successful file export.
// Driven by ExportedFileAttachment (structured model), not text parsing.
// ============================================================

struct FileCard: View {
    let attachment: ExportedFileAttachment
    @State private var fileExists: Bool = true
    @State private var showCopiedPath = false

    var body: some View {
        HStack(spacing: 12) {
            // Format icon
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(iconColor.opacity(0.15))
                    .frame(width: 40, height: 40)
                Text(attachment.formatIcon)
                    .font(.system(size: 20))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(attachment.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(WAI.text)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(attachment.displaySize)
                        .font(.system(size: 11))
                        .foregroundColor(WAI.textMuted)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundColor(WAI.textMuted)
                    Text(attachment.shortPath)
                        .font(.system(size: 11))
                        .foregroundColor(WAI.textMuted)
                        .lineLimit(1)
                }
                if !fileExists {
                    Text("Файл не найден")
                        .font(.system(size: 11))
                        .foregroundColor(WAI.danger)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 6) {
                FileActionButton(label: "Открыть", icon: "arrow.up.doc", enabled: fileExists) {
                    NSWorkspace.shared.open(attachment.fileURL)
                }
                FileActionButton(label: "В Finder", icon: "folder", enabled: fileExists) {
                    NSWorkspace.shared.activateFileViewerSelecting([attachment.fileURL])
                }
                FileActionButton(
                    label: showCopiedPath ? "Скопировано" : "Путь",
                    icon: showCopiedPath ? "checkmark" : "link",
                    enabled: true
                ) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(attachment.filePath, forType: .string)
                    withAnimation { showCopiedPath = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation { showCopiedPath = false }
                    }
                }
                FileActionButton(label: "Копировать файл", icon: "doc.on.doc", enabled: fileExists) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([attachment.fileURL as NSURL])
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(WAI.surfaceInset)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(iconColor.opacity(0.25), lineWidth: 1)
                )
        )
        .frame(maxWidth: 600)
        .contextMenu {
            Button("Открыть в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([attachment.fileURL])
            }
            Button("Открыть папку Exports") {
                let exportsDir = attachment.fileURL.deletingLastPathComponent()
                NSWorkspace.shared.open(exportsDir)
            }
            Divider()
            Button("Скопировать путь") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(attachment.filePath, forType: .string)
            }
            Button("Скопировать файл") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([attachment.fileURL as NSURL])
            }
        }
        .onAppear { fileExists = attachment.exists }
    }

    private var iconColor: Color {
        switch attachment.format {
        case "png", "jpg", "jpeg": return WAI.accentBright
        case "svg":                return .purple
        case "pdf":           return .red
        case "docx":          return .blue
        case "rtf":           return Color(hex: 0x5B9BD5)
        case "csv", "xlsx":   return .green
        case "md", "markdown":return .purple
        default:              return .gray
        }
    }
}

private struct FileActionButton: View {
    let label: String
    let icon: String
    let enabled: Bool
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovered ? WAI.surfaceStrong : WAI.surface)
            )
            .foregroundColor(enabled ? WAI.textDim : WAI.textFaint)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovered = $0 && enabled }
    }
}
