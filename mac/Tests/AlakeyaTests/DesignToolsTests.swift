import Foundation
import AppKit
import Testing
@testable import Alakeya

@Test
func recognizesVectorizationCommands() {
    for text in [
        "Сконвертируй это изображение в вектор",
        "Переведи картинку в SVG",
        "Сделай svg для печати",
        "Пожалуйста, векторизуй логотип",
        "Сконвектируй файл в вектор",
        "convert to vector"
    ] {
        #expect(DesignIntent.requestsVectorization(text))
    }
}

@Test
func imageModelFallbackOnlyHandlesAvailabilityErrors() {
    #expect(ImageGenerationService.shouldTryFallbackModel(
        status: 404,
        message: "not found"
    ))
    #expect(ImageGenerationService.shouldTryFallbackModel(
        status: 400,
        message: "The model does not exist or you do not have access"
    ))
    #expect(!ImageGenerationService.shouldTryFallbackModel(
        status: 400,
        message: "Your prompt was rejected"
    ))
    #expect(!ImageGenerationService.shouldTryFallbackModel(
        status: 401,
        message: "Invalid API key"
    ))
}

@Test
func decodesBase64ImageResponse() throws {
    let original = Data([0x89, 0x50, 0x4E, 0x47])
    let response = try JSONSerialization.data(withJSONObject: [
        "data": [["b64_json": original.base64EncodedString()]]
    ])
    #expect(try ImageGenerationService.decodeImageResponse(response) == original)

    let invalid = Data(#"{"data":[]}"#.utf8)
    #expect(throws: AIClientError.self) {
        try ImageGenerationService.decodeImageResponse(invalid)
    }
}

@Test
func imageRequestUsesSupportedResponsiveDefaults() {
    let body = ImageGenerationService.imageRequestBody(
        model: "gpt-image-2",
        prompt: "Логотип"
    )
    #expect(body["model"] as? String == "gpt-image-2")
    #expect(body["quality"] as? String == "medium")
    #expect(body["output_format"] as? String == "png")
    #expect(body["size"] as? String == "1024x1024")
}

@Test
func svgFallbackPromptRemainsVectorFriendly() {
    let prompt = ImageGenerationService.fallbackPrompt(
        idea: "Лиса",
        outputFormat: .svg
    )
    #expect(prompt.contains("Лиса"))
    #expect(prompt.contains("замкнутые цветовые"))
    #expect(ImageGenerationService.fallbackPrompt(
        idea: "Лиса",
        outputFormat: .png
    ) == "Лиса")
}

@Test
func ignoresOrdinaryImageQuestions() {
    for text in [
        "Что изображено на картинке?",
        "Улучши описание логотипа",
        "Сгенерируй PNG",
        ""
    ] {
        #expect(!DesignIntent.requestsVectorization(text))
    }
}

@Test
func vectorizerAcceptsOnlySupportedReadableImages() throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("alakeya-design-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let missingPNG = temp.appendingPathComponent("missing.png")
    let textFile = temp.appendingPathComponent("fake.png")
    try Data("not an image".utf8).write(to: textFile)

    #expect(VectorizationService.isSupported(missingPNG))
    #expect(!VectorizationService.isVectorizable(missingPNG))
    #expect(!VectorizationService.isVectorizable(textFile))
    #expect(!VectorizationService.isSupported(temp.appendingPathComponent("image.webp")))
}

@Test
func generatedFileAttachmentSupportsImageFormats() {
    let svg = ExportedFileAttachment(
        filename: "logo.svg",
        filePath: "/tmp/logo.svg",
        format: "svg",
        fileSize: 1200
    )
    let png = ExportedFileAttachment(
        filename: "logo.png",
        filePath: "/tmp/logo.png",
        format: "png",
        fileSize: 2400
    )

    #expect(svg.formatIcon == "◇")
    #expect(png.formatIcon == "🖼️")
    #expect(svg.displaySize == "1 KB")
}

@Test
func vectorizationProfilesHaveDistinctQualityTradeoffs() {
    #expect(VectorizationProfile.logo.arguments.contains("poster"))
    #expect(VectorizationProfile.illustration.arguments.contains("photo"))
    #expect(VectorizationProfile.maximumDetail.arguments.contains("0"))
    #expect(VectorizationProfile.maximumDetail.arguments.contains("8"))
}

@Test
func vtracerConvertsARealPNGToSVG() async throws {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent("alakeya-vtracer-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: temp) }

    let input = temp.appendingPathComponent("source.png")
    let output = temp.appendingPathComponent("result.svg")
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 16,
        pixelsHigh: 16,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    let image = try #require(bitmap)
    let pixels = try #require(image.bitmapData)
    for index in 0..<(16 * 16) {
        let offset = index * 4
        pixels[offset] = 6
        pixels[offset + 1] = 182
        pixels[offset + 2] = 212
        pixels[offset + 3] = 255
    }
    let png = try #require(image.representation(using: .png, properties: [:]))
    try png.write(to: input)

    try await VectorizationService().convert(
        inputURL: input,
        outputURL: output,
        profile: .maximumDetail
    )
    let svg = try String(contentsOf: output, encoding: .utf8)
    #expect(svg.contains("<svg"))
    #expect(svg.contains("<path"))
}
