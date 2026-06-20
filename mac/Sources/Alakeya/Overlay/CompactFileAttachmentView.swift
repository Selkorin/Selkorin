import SwiftUI
import AppKit

// ============================================================
// CompactFileAttachmentView.swift
// Compact file pill shown in chat after a successful export.
// Height ~44px, click opens file, right-click for full menu.
// ============================================================

struct CompactFileAttachmentView: View {
    let attachment: ExportedFileAttachment
    @State private var hovered = false
    @State private var fileExists: Bool = true

    var body: some View {
        HStack(spacing: 10) {
            // Format icon
            Text(attachment.formatIcon)
                .font(.system(size: 22))
                .frame(width: 30)

            // Name + meta
            VStack(alignment: .leading, spacing: 1) {
                Text(attachment.filename)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(fileExists ? WAI.text : WAI.textFaint)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(metaLine)
                    .font(.system(size: 11))
                    .foregroundColor(WAI.textMuted)
            }

            Spacer(minLength: 4)

            // Open chevron / missing badge
            if fileExists {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 17))
                    .foregroundColor(iconColor.opacity(hovered ? 1.0 : 0.55))
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 14))
                    .foregroundColor(WAI.danger)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 360, minHeight: 44, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(hovered ? WAI.surfaceStrong : WAI.surfaceInset)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(iconColor.opacity(hovered ? 0.40 : 0.20), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onHover { hovered = $0 }
        .onTapGesture {
            if fileExists { NSWorkspace.shared.open(attachment.fileURL) }
        }
        .help(attachment.filePath)
        .contextMenu {
            Button("Открыть") {
                NSWorkspace.shared.open(attachment.fileURL)
            }
            .disabled(!fileExists)

            Button("Показать в Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([attachment.fileURL])
            }
            .disabled(!fileExists)

            Button("Открыть папку Exports") {
                NSWorkspace.shared.open(attachment.fileURL.deletingLastPathComponent())
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
            .disabled(!fileExists)

            Button("Поделиться...") {
                sharingPicker()
            }
            .disabled(!fileExists)
        }
        .onAppear { fileExists = attachment.exists }
        .onHover { over in
            hovered = over
            if over { fileExists = attachment.exists }
        }
        .onReceive(
            Timer.publish(every: 5, on: .main, in: .common).autoconnect()
        ) { _ in
            fileExists = attachment.exists
        }
    }

    // MARK: - Helpers

    private var metaLine: String {
        let fmt = attachment.format.uppercased()
        let size = attachment.displaySize
        return fileExists ? "\(fmt) · \(size)" : "\(fmt) · Файл не найден"
    }

    private var iconColor: Color {
        switch attachment.format {
        case "png", "jpg", "jpeg": return WAI.accentBright
        case "svg":                return .purple
        case "pdf":            return .red
        case "docx":           return .blue
        case "rtf":            return Color(hex: 0x5B9BD5)
        case "csv", "xlsx":    return .green
        case "md", "markdown": return .purple
        default:               return .gray
        }
    }

    private func sharingPicker() {
        let picker = NSSharingServicePicker(items: [attachment.fileURL])
        if let window = NSApp.keyWindow, let view = window.contentView {
            let rect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
        }
    }
}
