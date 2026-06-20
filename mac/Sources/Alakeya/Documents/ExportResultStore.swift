import Foundation

// ============================================================
// ExportResultStore.swift — lightweight bridge that carries
// ExportedFileAttachment from Executors up to ToolRunner after
// the agentic loop completes.
// ============================================================

@MainActor
final class ExportResultStore {
    static let shared = ExportResultStore()
    private init() {}

    private var pending: [ExportedFileAttachment] = []

    func add(_ attachment: ExportedFileAttachment) {
        pending.append(attachment)
    }

    /// Drain and return all pending attachments. Clears the store.
    func drain() -> [ExportedFileAttachment] {
        let result = pending
        pending = []
        return result
    }

    func clear() { pending = [] }
}
