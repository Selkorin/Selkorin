import SwiftUI
import UniformTypeIdentifiers

struct KnowledgeSettingsView: View {
    @ObservedObject private var store = KnowledgeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if store.docs.isEmpty {
                emptyState
            } else {
                docsList
            }
            addButton
            hint
        }
    }

    // ── Header ────────────────────────────────────────────

    private var header: some View {
        HStack(spacing: 8) {
            Text("База знаний")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WAI.text)
            Spacer()
            if !store.docs.isEmpty {
                Text("\(store.docs.count) доков")
                    .font(.system(size: 11))
                    .foregroundStyle(WAI.textFaint)
            }
            Button("Обновить") { store.reload() }
                .buttonStyle(.plain)
                .foregroundStyle(WAI.accentBright)
                .font(.system(size: 13))
        }
    }

    // ── Empty state ───────────────────────────────────────

    private var emptyState: some View {
        Text("Нет документов. Нажмите «+ Добавить» или положите .md файлы в папку.")
            .font(.system(size: 13))
            .foregroundStyle(WAI.textMuted)
            .padding(.vertical, 4)
    }

    // ── Docs list ─────────────────────────────────────────

    private var docsList: some View {
        VStack(spacing: 4) {
            ForEach(store.docs) { doc in
                docRow(doc)
            }
        }
    }

    private func docRow(_ doc: KnowledgeDoc) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(WAI.text)
                HStack(spacing: 6) {
                    Text("\(doc.id).md")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textFaint)
                    Text("·")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textFaint)
                    Text("\(doc.charCount) симв.")
                        .font(.system(size: 11))
                        .foregroundStyle(
                            doc.charCount > KnowledgeStore.perDocLimit
                                ? WAI.textMuted : WAI.textFaint
                        )
                }
            }
            Spacer()
            Button {
                store.delete(doc: doc)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(WAI.textMuted)
                    .frame(width: 20, height: 20)
                    .background(WAI.surfaceInset)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(WAI.surfaceInset)
        .overlay(RoundedRectangle(cornerRadius: WAI.rMd).stroke(WAI.line))
        .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
    }

    // ── Add ───────────────────────────────────────────────

    private var addButton: some View {
        Button("+ Добавить документы…") { openFilePicker() }
            .buttonStyle(.plain)
            .foregroundStyle(WAI.accentBright)
            .font(.system(size: 13))
            .padding(.top, 4)
    }

    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.message = "Выберите .md файлы для базы знаний"
        panel.prompt = "Добавить"
        guard panel.runModal() == .OK else { return }
        store.addFiles(urls: panel.urls)
    }

    // ── Hint ──────────────────────────────────────────────

    private var hint: some View {
        Text("Файлы хранятся в ~/Library/Application Support/Alakeya/Knowledge/")
            .font(.system(size: 11))
            .foregroundStyle(WAI.textFaint)
    }
}
