import SwiftUI

struct AvatarEditorView: View {
    @ObservedObject var store: AgentStore
    let title: String
    let initialImage: NSImage?
    let onSave: (Data) throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var generatedData: Data?
    @State private var isGenerating = false
    @State private var error: String?

    private let generator = ImageGenerationService()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(WAI.text)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").foregroundStyle(WAI.textDim)
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 18) {
                avatarPreview
                VStack(alignment: .leading, spacing: 8) {
                    Text("Опишите персонажа")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WAI.textDim)
                    TextEditor(text: $description)
                        .font(.system(size: 13))
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 112)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(WAI.control))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WAI.lineStrong))
                    Text("Будет создан квадратный портрет без текста.")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textMuted)
                }
            }

            if let error {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(WAI.danger)
            }

            HStack {
                Spacer()
                Button("Отмена") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(WAI.textDim)
                Button(isGenerating ? "Генерирую…" : "Сгенерировать") {
                    generateAvatar()
                }
                .buttonStyle(.plain)
                .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                .foregroundStyle(WAI.accentBright)
                if generatedData != nil {
                    Button("Сохранить") {
                        guard let generatedData else { return }
                        do {
                            try onSave(generatedData)
                            dismiss()
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(WAI.bg)
                    .padding(.horizontal, 15)
                    .frame(height: 38)
                    .background(RoundedRectangle(cornerRadius: 10).fill(WAI.accent))
                }
            }
        }
        .padding(24)
        .frame(width: 600)
        .background(WAI.surfaceStrong)
    }

    private var avatarPreview: some View {
        Group {
            if let generatedData, let image = NSImage(data: generatedData) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let initialImage {
                Image(nsImage: initialImage).resizable().aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(WAI.textMuted)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 132, height: 132)
        .background(RoundedRectangle(cornerRadius: 28).fill(WAI.surfaceInset))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(WAI.lineStrong))
    }

    private func generateAvatar() {
        let idea = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty else { return }
        isGenerating = true
        error = nil
        Task {
            do {
                generatedData = try await generator.generateAvatar(
                    description: idea,
                    settings: store.settings
                )
                isGenerating = false
            } catch {
                self.error = error.localizedDescription
                isGenerating = false
            }
        }
    }
}
