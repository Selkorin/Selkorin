import Foundation
import ScreenCaptureKit
import CoreGraphics

// ============================================================
// ScreenReader.swift — ScreenCaptureKit grounding for visual
// verification / VLM fallback (DOC1 §"Screen Recording + grounding").
// Requires the Screen Recording TCC permission.
// ============================================================

@available(macOS 14.0, *)
final class ScreenReader {

    /// Capture the main display as a CGImage for verification or a VLM pass.
    func captureMainDisplay() async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false,
                                                                           onScreenWindowsOnly: true)
        guard let display = content.displays.first else {
            throw NSError(domain: "Alakeya.ScreenReader", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Нет доступного дисплея"])
        }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        return try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                          configuration: config)
    }

    /// Lightweight description hook — point a VLM here in production.
    func describeScreen() async -> String {
        if (try? await captureMainDisplay()) != nil {
            return "Снимок экрана получен (грундинг доступен)."
        }
        return "Снимок недоступен — проверь разрешение Screen Recording."
    }
}
