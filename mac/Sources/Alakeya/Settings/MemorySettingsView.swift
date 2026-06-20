import SwiftUI

struct MemorySettingsView: View {
    @ObservedObject private var memory = MemoryStore.shared

    @State private var isAdding = false
    @State private var newKey   = ""
    @State private var newValue = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            if memory.entries.isEmpty {
                emptyState
            } else {
                entriesList
            }
            if isAdding { addForm }
        }
    }

    // ── Header ────────────────────────────────────────────

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text("Память")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WAI.text)
            Spacer()
            Text("\(memory.entries.count)/50")
                .font(.system(size: 11))
                .foregroundStyle(WAI.textFaint)
            if !memory.entries.isEmpty {
                Button("Очистить всё") { memory.deleteAll() }
                    .buttonStyle(.plain)
                    .foregroundStyle(WAI.danger)
                    .font(.system(size: 12))
            }
            Button(isAdding ? "Отмена" : "+ Добавить") {
                withAnimation(.easeOut(duration: WAI.durFast)) { isAdding.toggle() }
                newKey = ""; newValue = ""
            }
            .buttonStyle(.plain)
            .foregroundStyle(isAdding ? WAI.textMuted : WAI.accentBright)
            .font(.system(size: 13))
        }
    }

    // ── Empty state ───────────────────────────────────────

    private var emptyState: some View {
        Text("Пока ничего не сохранено.\nНапиши в чате: «Запомни: ...»")
            .font(.system(size: 13))
            .foregroundStyle(WAI.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
    }

    // ── Entries list ──────────────────────────────────────

    private var entriesList: some View {
        VStack(spacing: 4) {
            ForEach(memory.entries) { entry in
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.key)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(WAI.accentBright)
                        Text(entry.value)
                            .font(.system(size: 13))
                            .foregroundStyle(WAI.text)
                            .lineLimit(3)
                    }
                    Spacer()
                    Button {
                        memory.delete(id: entry.id)
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
        }
    }

    // ── Add form ──────────────────────────────────────────

    private var addForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $newKey) {
                Text("Выбери категорию…").tag("")
                ForEach(["name", "project", "preference", "goal", "note"], id: \.self) {
                    Text($0).tag($0)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            TextField("Значение…", text: $newValue)
                .textFieldStyle(.roundedBorder)

            Button("Сохранить") {
                guard !newKey.isEmpty, !newValue.isEmpty else { return }
                memory.upsert(key: newKey, value: newValue)
                withAnimation { isAdding = false }
                newKey = ""; newValue = ""
            }
            .buttonStyle(.borderedProminent)
            .tint(WAI.accent)
            .disabled(newKey.isEmpty || newValue.isEmpty)
        }
        .padding(12)
        .background(WAI.surfaceInset)
        .overlay(RoundedRectangle(cornerRadius: WAI.rMd).stroke(WAI.line))
        .clipShape(RoundedRectangle(cornerRadius: WAI.rMd))
    }
}
