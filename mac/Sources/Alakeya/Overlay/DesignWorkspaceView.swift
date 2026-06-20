import AppKit
import SwiftUI

struct DesignTurn: Identifiable {
    let id = UUID()
    let idea: String
    let finalPrompt: String
    let imageData: Data?
    let files: [ExportedFileAttachment]
    let error: String?
    let warning: String?
}

@MainActor
final class DesignWorkspaceModel: ObservableObject {
    @Published var turns: [DesignTurn] = []
}

struct DesignWorkspaceView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var model: DesignWorkspaceModel
    var onClose: () -> Void

    @State private var prompt = ""
    @State private var outputFormat: DesignOutputFormat = .png
    @State private var vectorProfile: VectorizationProfile = .maximumDetail
    @State private var inputURL: URL?
    @State private var preview: NSImage?
    @State private var isDropTargeted = false
    @State private var isWorking = false
    @FocusState private var promptFocused: Bool

    private let generator = ImageGenerationService()
    private let vectorizer = VectorizationService()

    var body: some View {
        VStack(spacing: 0) {
            header
            GeometryReader { geometry in
                if geometry.size.width >= 900 {
                    HStack(spacing: 0) {
                        studioControls
                            .frame(width: min(410, max(360, geometry.size.width * 0.37)))
                        Rectangle().fill(WAI.line).frame(width: 1)
                        studioResult
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            studioControls
                            Rectangle().fill(WAI.line).frame(height: 1)
                            studioResult
                                .frame(minHeight: 460)
                        }
                    }
                }
            }
        }
        .background(WAI.canvas)
        .onAppear { promptFocused = true }
    }

    private var studioControls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                controlSection("Промпт") {
                    ZStack(alignment: .topLeading) {
                        if prompt.isEmpty {
                            Text("Опишите изображение: постер для кофейни, тёплый свет, минимализм…")
                                .font(.system(size: 13))
                                .foregroundStyle(WAI.textMuted)
                                .padding(12)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $prompt)
                            .font(.system(size: 13.5))
                            .foregroundStyle(WAI.text)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 92, maxHeight: 130)
                            .padding(6)
                    }
                    .background(RoundedRectangle(cornerRadius: 12).fill(WAI.control))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(WAI.lineStrong))
                }

                controlSection("Формат вывода") {
                    Picker("Формат", selection: $outputFormat) {
                        ForEach(DesignOutputFormat.allCases) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 220)
                    .disabled(isWorking)
                }

                Button(action: generate) {
                    HStack(spacing: 8) {
                        if isWorking {
                            ProgressView().controlSize(.small)
                        }
                        Text(isWorking ? "Создаю…" : "Сгенерировать")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 10).fill(canGenerate ? WAI.accent : WAI.surfaceInset))
                }
                .buttonStyle(.plain)
                .disabled(!canGenerate)

                Rectangle().fill(WAI.line).frame(height: 1)

                vectorTool
            }
            .padding(24)
        }
        .background(WAI.sidebar)
    }

    private func controlSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(WAI.textDim)
            content()
        }
    }

    private var studioResult: some View {
        VStack(spacing: 0) {
            Group {
                if let latest = model.turns.last {
                    ScrollView {
                        turnView(latest)
                            .frame(maxWidth: 760)
                            .padding(28)
                            .frame(maxWidth: .infinity)
                    }
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.turns.count > 1 {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Недавние результаты")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(WAI.textMuted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(model.turns.dropLast().suffix(6)) { turn in
                                if let data = turn.imageData, let image = NSImage(data: data) {
                                    Image(nsImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 78, height: 78)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .background(WAI.sidebar)
                .overlay(Rectangle().fill(WAI.line).frame(height: 1), alignment: .top)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Генерация изображения")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(WAI.text)
                Text("GPT Image · PNG и SVG")
                    .font(.system(size: 11))
                    .foregroundStyle(WAI.textMuted)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(WAI.surfaceInset))
                    .overlay(Circle().stroke(WAI.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Закрыть раздел изображений")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(WAI.sidebar)
        .overlay(Rectangle().fill(WAI.line).frame(height: 1), alignment: .bottom)
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    if model.turns.isEmpty {
                        emptyState
                    }
                    ForEach(model.turns) { turn in
                        turnView(turn)
                            .id(turn.id)
                    }
                    vectorTool
                    Color.clear.frame(height: 1).id("design-bottom")
                }
                .frame(maxWidth: 760)
                .padding(22)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.turns.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("design-bottom", anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            OrbView(
                state: isWorking ? .generating : .idle,
                size: 82,
                showsStatus: isWorking
            )
            .frame(width: 130, height: isWorking ? 150 : 120)

            if !isWorking {
                Text("Результат появится здесь")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(WAI.textDim)
                Text("Опишите идею и нажмите «Сгенерировать».")
                    .font(.system(size: 12.5))
                    .foregroundStyle(WAI.textMuted)
                    .multilineTextAlignment(.center)
            }

            if !isWorking {
                HStack(spacing: 8) {
                    suggestion("Логотип кофейни")
                    suggestion("Винтажный постер")
                    suggestion("Цветочный орнамент")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .padding(24)
    }

    private func suggestion(_ text: String) -> some View {
        Button {
            prompt = text
            promptFocused = true
        } label: {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(WAI.textDim)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 10).fill(WAI.surfaceInset))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(WAI.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func turnView(_ turn: DesignTurn) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Spacer(minLength: 60)
                Text(turn.idea)
                    .font(.system(size: 13))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 15).fill(Color(hex: 0x1A1A28)))
            }

            if let error = turn.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(WAI.danger)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(WAI.danger.opacity(0.08)))
            } else {
                if let data = turn.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 430)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
                }

                DisclosureGroup {
                    Text(turn.finalPrompt)
                        .font(.system(size: 12))
                        .foregroundStyle(WAI.textDim)
                        .textSelection(.enabled)
                        .padding(.top, 7)
                } label: {
                    Label("Промпт Алакеи", systemImage: "wand.and.stars")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WAI.accentBright)
                }

                ForEach(turn.files) { file in
                    CompactFileAttachmentView(attachment: file)
                }
                if let warning = turn.warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.warning)
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(WAI.warning.opacity(0.08)))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var vectorTool: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("PNG в вектор", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WAI.text)
                Spacer()
                Text("Локально · VTracer")
                    .font(.system(size: 10))
                    .foregroundStyle(WAI.textMuted)
            }

            Picker("Профиль", selection: $vectorProfile) {
                ForEach(VectorizationProfile.allCases) { profile in
                    Text(profile.rawValue).tag(profile)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: .infinity)
            Text(vectorProfile.description)
                .font(.system(size: 10.5))
                .foregroundStyle(WAI.textMuted)

            HStack(spacing: 14) {
                if let preview {
                    Image(nsImage: preview)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 58, height: 58)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 24))
                        .foregroundStyle(WAI.accentBright)
                        .frame(width: 58, height: 58)
                        .background(RoundedRectangle(cornerRadius: 10).fill(WAI.accentSoft))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(inputURL?.lastPathComponent ?? "Перетащите PNG или JPG")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WAI.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(inputURL == nil ? "или нажмите для выбора" : "Файл готов к конвертации")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                .contentShape(Rectangle())
                .onTapGesture(perform: chooseImage)
                if inputURL != nil {
                    Button("В SVG", action: vectorizeSelected)
                        .buttonStyle(.borderedProminent)
                        .tint(WAI.accent)
                        .disabled(isWorking)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(
                isDropTargeted ? WAI.accentSoft : WAI.surfaceInset
            ))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(
                isDropTargeted ? WAI.accentBright : WAI.lineStrong,
                style: StrokeStyle(lineWidth: 1, dash: [6, 5])
            ))
            .onDrop(of: ["public.file-url"], isTargeted: $isDropTargeted, perform: handleDrop)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(WAI.control))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(WAI.line, lineWidth: 1))
    }

    private var composer: some View {
        VStack(spacing: 10) {
            if isWorking {
                HStack(spacing: 8) {
                    OrbView(
                        state: outputFormat == .svg ? .vectorizing : .generating,
                        size: 26
                    )
                    .frame(width: 34, height: 34)
                    Text(outputFormat == .svg
                         ? "Улучшаю промпт → генерирую PNG → создаю SVG…"
                         : "Улучшаю промпт → генерирую PNG…")
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textMuted)
                    Spacer()
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Например: минималистичный логотип пекарни…", text: $prompt, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(WAI.text)
                    .lineLimit(1...5)
                    .focused($promptFocused)
                    .onSubmit(generate)

                Button(action: generate) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(canGenerate ? WAI.bg : WAI.textMuted)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(canGenerate ? WAI.accentBright : WAI.surfaceInset))
                }
                .buttonStyle(.plain)
                .disabled(!canGenerate)
                .help("Сгенерировать \(outputFormat.rawValue)")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: 0x1A1A22, alpha: 0.96)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(WAI.lineStrong, lineWidth: 1))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(WAI.sidebar)
        .overlay(Rectangle().fill(WAI.line).frame(height: 1), alignment: .top)
    }

    private var canGenerate: Bool {
        !isWorking && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func generate() {
        let idea = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !idea.isEmpty, !isWorking else { return }
        prompt = ""
        isWorking = true
        let selectedFormat = outputFormat

        Task {
            do {
                let result = try await generator.generate(
                    idea: idea,
                    format: selectedFormat,
                    settings: store.settings
                )
                await MainActor.run {
                    model.turns.append(DesignTurn(
                        idea: idea,
                        finalPrompt: result.prompt,
                        imageData: result.imageData,
                        files: result.files,
                        error: nil,
                        warning: result.warning
                    ))
                    isWorking = false
                    promptFocused = true
                }
            } catch {
                await MainActor.run {
                    model.turns.append(DesignTurn(
                        idea: idea,
                        finalPrompt: "",
                        imageData: nil,
                        files: [],
                        error: error.localizedDescription,
                        warning: nil
                    ))
                    isWorking = false
                }
            }
        }
    }

    private func chooseImage() {
        guard let url = vectorizer.chooseImage() else { return }
        select(url)
    }

    private func select(_ url: URL) {
        guard VectorizationService.isVectorizable(url) else {
            model.turns.append(DesignTurn(
                idea: "Добавить изображение для векторизации",
                finalPrompt: "",
                imageData: nil,
                files: [],
                error: "Выберите читаемый PNG, JPG или JPEG.",
                warning: nil
            ))
            return
        }
        inputURL = url
        preview = NSImage(contentsOf: url)
    }

    private func vectorizeSelected() {
        guard let inputURL, !isWorking else { return }
        isWorking = true
        Task {
            do {
                let file = try await vectorizer.convertToExports(
                    inputURL: inputURL,
                    profile: vectorProfile
                )
                let data = try? Data(contentsOf: inputURL)
                await MainActor.run {
                    model.turns.append(DesignTurn(
                        idea: "Сконвертируй \(inputURL.lastPathComponent) в вектор",
                        finalPrompt: "Локальная трассировка цветного изображения через VTracer.",
                        imageData: data,
                        files: [file],
                        error: nil,
                        warning: nil
                    ))
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    model.turns.append(DesignTurn(
                        idea: "Сконвертировать изображение в SVG",
                        finalPrompt: "",
                        imageData: nil,
                        files: [],
                        error: error.localizedDescription,
                        warning: nil
                    ))
                    isWorking = false
                }
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            if let url { DispatchQueue.main.async { select(url) } }
        }
        return true
    }
}
