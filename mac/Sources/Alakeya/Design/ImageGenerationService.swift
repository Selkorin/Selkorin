import Foundation

enum DesignOutputFormat: String, CaseIterable, Identifiable {
    case png = "PNG"
    case svg = "SVG"

    var id: String { rawValue }
}

struct GeneratedDesign {
    let prompt: String
    let imageData: Data
    let files: [ExportedFileAttachment]
    let warning: String?
}

struct ImageGenerationService {
    private static let promptInstruction = """
    Ты — арт-директор и prompt engineer для генерации изображений.
    Преврати идею пользователя в один точный производственный промпт.
    Сохрани исходный замысел. Добавь только полезные детали: главный объект,
    композицию, ракурс, стиль, материалы, свет, цветовую палитру, фон,
    качество и ограничения. Для логотипов, печатной графики, иконок и
    декоративных элементов предпочитай чистые формы, ясные границы,
    ограниченную палитру и минимум мелких деталей, чтобы результат хорошо
    векторизовался. Не добавляй объяснений, заголовков и кавычек.
    Верни только готовый промпт на русском языке.
    """

    private let vectorizer = VectorizationService()

    func generate(
        idea: String,
        format: DesignOutputFormat,
        settings: Settings
    ) async throws -> GeneratedDesign {
        let openAI = try openAIConfiguration(in: settings)
        guard let apiKey = try AIProviderStore.shared.apiKey(for: openAI.id) else {
            throw AIClientError.apiKeyMissing
        }

        // Prompt enhancement is optional. A temporary text-model failure must
        // not prevent the image model from doing the actual requested work.
        let enhancedPrompt = await enhancedPromptOrFallback(
            idea: idea,
            outputFormat: format,
            configuration: openAI,
            apiKey: apiKey
        )
        let imageData = try await requestImage(
            prompt: enhancedPrompt,
            apiKey: apiKey,
            quality: "medium",
            outputFormat: "png"
        )
        let pngURL = try save(imageData, extension: "png", prefix: "alakeya-image")
        var files = [attachment(for: pngURL, sourceTool: "generate_image")]
        var warning: String?

        if format == .svg {
            let svgURL = pngURL.deletingPathExtension().appendingPathExtension("svg")
            do {
                try await vectorizer.convert(
                    inputURL: pngURL,
                    outputURL: svgURL,
                    profile: .illustration
                )
                files.append(attachment(for: svgURL, sourceTool: "generate_image_vector"))
            } catch {
                warning = "PNG создан, но SVG не удалось подготовить: \(error.localizedDescription)"
            }
        }

        return GeneratedDesign(
            prompt: enhancedPrompt,
            imageData: imageData,
            files: files,
            warning: warning
        )
    }

    func generateAvatar(description: String, settings: Settings) async throws -> Data {
        let openAI = try openAIConfiguration(in: settings)
        guard let apiKey = try AIProviderStore.shared.apiKey(for: openAI.id) else {
            throw AIClientError.apiKeyMissing
        }
        let prompt = """
        \(description)

        Friendly polished cartoon avatar, centered head and shoulders,
        expressive face, clean silhouette, simple dark background, square
        profile picture, no text, no logo, no border.
        """
        return try await requestImage(
            prompt: prompt,
            apiKey: apiKey,
            quality: "low",
            outputFormat: "jpeg"
        )
    }

    private func enhancePrompt(
        idea: String,
        outputFormat: DesignOutputFormat,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async throws -> String {
        let client = try AIClient(configuration: configuration, apiKey: apiKey)
        let vectorRules = outputFormat == .svg ? """

        Результат будет автоматически переводиться в SVG. Обязательно создай
        vector-friendly artwork: плоские замкнутые цветовые области, чёткие
        непрерывные контуры, не более 16 основных цветов, минимум градиентов,
        никакой фототекстуры, шума, мазков, свечения из мелких частиц и
        микродеталей. Не добавляй текст, если пользователь явно его не просил.
        Если текст нужен — крупный, простой, контрастный, без декоративной
        фактуры. Композиция должна хорошо читаться как печатный постер.
        """ : ""
        let request = "\(Self.promptInstruction)\(vectorRules)\n\nИдея пользователя:\n\(idea)"
        let result = try await client.sendMessage(userText: request)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? idea : result
    }

    private func enhancedPromptOrFallback(
        idea: String,
        outputFormat: DesignOutputFormat,
        configuration: AIProviderConfiguration,
        apiKey: String
    ) async -> String {
        do {
            return try await enhancePrompt(
                idea: idea,
                outputFormat: outputFormat,
                configuration: configuration,
                apiKey: apiKey
            )
        } catch {
            return Self.fallbackPrompt(idea: idea, outputFormat: outputFormat)
        }
    }

    static func fallbackPrompt(idea: String, outputFormat: DesignOutputFormat) -> String {
        guard outputFormat == .svg else { return idea }
        return """
        \(idea)

        Создай чистую векторную иллюстрацию для печати: замкнутые цветовые
        формы, чёткие непрерывные контуры, ограниченная палитра до 16 основных
        цветов, минимум градиентов, без фототекстуры, шума и микродеталей.
        """
    }

    private func requestImage(
        prompt: String,
        apiKey: String,
        quality: String,
        outputFormat: String
    ) async throws -> Data {
        let models = ["gpt-image-2", "gpt-image-1.5", "gpt-image-1"]
        var lastError: Error = AIClientError.invalidResponse

        for model in models {
            do {
                guard let endpoint = URL(string: "https://api.openai.com/v1/images/generations") else {
                    throw AIClientError.invalidBaseURL
                }
                var request = URLRequest(url: endpoint)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.timeoutInterval = 300
                request.httpBody = try JSONSerialization.data(
                    withJSONObject: Self.imageRequestBody(
                        model: model,
                        prompt: prompt,
                        quality: quality,
                        outputFormat: outputFormat
                    )
                )

                let data = try await AIHTTP.data(for: request)
                return try Self.decodeImageResponse(data)
            } catch AIClientError.server(let status, let message)
                where Self.shouldTryFallbackModel(status: status, message: message) {
                lastError = AIClientError.server(status: status, message: message)
            } catch {
                lastError = error
                break
            }
        }
        throw lastError
    }

    static func imageRequestBody(
        model: String,
        prompt: String,
        quality: String = "medium",
        outputFormat: String = "png"
    ) -> [String: Any] {
        [
            "model": model,
            "prompt": prompt,
            "n": 1,
            "size": "1024x1024",
            // Medium normally completes much faster and is sufficient for the
            // subsequent SVG tracing pass. High can take several minutes.
            "quality": quality,
            "output_format": outputFormat,
        ]
    }

    private func openAIConfiguration(in settings: Settings) throws -> AIProviderConfiguration {
        guard let configuration = settings.models.providers.first(where: { $0.kind == .openAI }) else {
            throw AIClientError.providerNotSelected
        }
        return configuration
    }

    static func shouldTryFallbackModel(status: Int, message: String) -> Bool {
        if status == 404 { return true }
        guard status == 400 else { return false }
        let value = message.lowercased()
        return value.contains("model")
            && (value.contains("not found")
                || value.contains("does not exist")
                || value.contains("access"))
    }

    static func decodeImageResponse(_ data: Data) throws -> Data {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["data"] as? [[String: Any]],
            let encoded = items.first?["b64_json"] as? String,
            let imageData = Data(base64Encoded: encoded),
            !imageData.isEmpty
        else {
            throw AIClientError.invalidResponse
        }
        return imageData
    }

    private func save(_ data: Data, extension ext: String, prefix: String) throws -> URL {
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Alakeya/Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stamp = Self.fileTimestamp()
        let suffix = UUID().uuidString.prefix(8).lowercased()
        let url = directory.appendingPathComponent("\(prefix)-\(stamp)-\(suffix).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func attachment(for url: URL, sourceTool: String) -> ExportedFileAttachment {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        return ExportedFileAttachment(
            filename: url.lastPathComponent,
            filePath: url.path,
            format: url.pathExtension.lowercased(),
            fileSize: size,
            sourceTool: sourceTool
        )
    }

    private static func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
