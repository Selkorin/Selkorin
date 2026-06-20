import AppKit
import Foundation
import UniformTypeIdentifiers

enum VectorizationError: LocalizedError {
    case unsupportedFormat
    case inputMissing
    case invalidImage
    case vtracerMissing
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Поддерживаются PNG, JPG и JPEG."
        case .inputMissing:
            return "Исходный файл не найден или недоступен."
        case .invalidImage:
            return "Файл повреждён или не является читаемым изображением."
        case .vtracerMissing:
            return "VTracer не найден. Установите его командой: cargo install vtracer"
        case .conversionFailed(let detail):
            return detail.isEmpty ? "VTracer не смог создать SVG." : detail
        }
    }
}

enum VectorizationProfile: String, CaseIterable, Identifiable {
    case logo = "Логотип"
    case illustration = "Иллюстрация"
    case maximumDetail = "Макс. детали"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .logo:
            return "Чистые контуры и компактный файл"
        case .illustration:
            return "Больше оттенков и деталей"
        case .maximumDetail:
            return "Максимум мелких областей, большой SVG"
        }
    }

    var arguments: [String] {
        switch self {
        case .logo:
            return [
                "--preset", "poster",
                "--filter_speckle", "8",
                "--color_precision", "6",
                "--path_precision", "4"
            ]
        case .illustration:
            return [
                "--preset", "photo",
                "--filter_speckle", "2",
                "--color_precision", "8",
                "--gradient_step", "8",
                "--segment_length", "3.5",
                "--path_precision", "6"
            ]
        case .maximumDetail:
            return [
                "--colormode", "color",
                "--hierarchical", "stacked",
                "--mode", "spline",
                "--filter_speckle", "0",
                "--color_precision", "8",
                "--gradient_step", "3",
                "--corner_threshold", "30",
                "--segment_length", "3.5",
                "--splice_threshold", "20",
                "--path_precision", "8"
            ]
        }
    }
}

struct VectorizationService {
    static let supportedExtensions: Set<String> = ["png", "jpg", "jpeg"]

    static func isSupported(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    static func isVectorizable(_ url: URL) -> Bool {
        isSupported(url)
            && FileManager.default.isReadableFile(atPath: url.path)
            && NSImage(contentsOf: url) != nil
    }

    static func suggestedOutputURL(for inputURL: URL) -> URL {
        inputURL.deletingPathExtension().appendingPathExtension("svg")
    }

    func chooseImage() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Выберите изображение для векторизации"
        panel.prompt = "Выбрать"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg]
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseOutputURL(for inputURL: URL) -> URL? {
        let panel = NSSavePanel()
        panel.title = "Сохранить векторный файл"
        panel.prompt = "Сохранить SVG"
        panel.allowedContentTypes = [.svg]
        panel.nameFieldStringValue = Self.suggestedOutputURL(for: inputURL).lastPathComponent
        return panel.runModal() == .OK ? panel.url : nil
    }

    func convert(
        inputURL: URL,
        outputURL: URL,
        profile: VectorizationProfile = .illustration
    ) async throws {
        guard Self.isSupported(inputURL) else {
            throw VectorizationError.unsupportedFormat
        }
        guard FileManager.default.isReadableFile(atPath: inputURL.path) else {
            throw VectorizationError.inputMissing
        }
        guard NSImage(contentsOf: inputURL) != nil else {
            throw VectorizationError.invalidImage
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let executableURL = try locateVTracer()
        let result = try await run(executableURL, arguments: [
            "--input", inputURL.path,
            "--output", outputURL.path
        ] + profile.arguments)

        guard result.status == 0, FileManager.default.fileExists(atPath: outputURL.path) else {
            throw VectorizationError.conversionFailed(result.error)
        }
    }

    func convertToExports(
        inputURL: URL,
        profile: VectorizationProfile = .maximumDetail
    ) async throws -> ExportedFileAttachment {
        guard Self.isSupported(inputURL) else {
            throw VectorizationError.unsupportedFormat
        }
        let directory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Alakeya/Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let base = inputURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "[^a-zA-Zа-яА-Я0-9_-]+", with: "-", options: .regularExpression)
        let safeBase = base.isEmpty ? "image" : base
        let stamp = String(Int(Date().timeIntervalSince1970 * 1000))
        let outputURL = directory.appendingPathComponent("\(safeBase)-vector-\(stamp).svg")
        try await convert(inputURL: inputURL, outputURL: outputURL, profile: profile)
        let size = (try? outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize)
            .map(Int64.init) ?? 0
        return ExportedFileAttachment(
            filename: outputURL.lastPathComponent,
            filePath: outputURL.path,
            format: "svg",
            fileSize: size,
            sourceTool: "vectorize_image"
        )
    }

    private func locateVTracer() throws -> URL {
        let environmentPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let pathCandidates = environmentPath
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("vtracer") }
        let fixedCandidates = [
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".cargo/bin/vtracer"),
            URL(fileURLWithPath: "/opt/homebrew/bin/vtracer"),
            URL(fileURLWithPath: "/usr/local/bin/vtracer")
        ]

        guard let executable = (pathCandidates + fixedCandidates).first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw VectorizationError.vtracerMissing
        }
        return executable
    }

    private func run(_ executableURL: URL, arguments: [String]) async throws
        -> (status: Int32, error: String)
    {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardError = errorPipe
            process.terminationHandler = { process in
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (
                    process.terminationStatus,
                    String(data: data, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
