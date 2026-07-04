import Foundation
import os

/// Thin wrapper around os.Logger plus an in-app ring buffer so the UI can show
/// a live activity log (useful when auditing what the tool actually did on the
/// network).
@MainActor
final class AppLog: ObservableObject {
    static let shared = AppLog()

    struct Entry: Identifiable {
        let id = UUID()
        let date: Date
        let level: Level
        let message: String
    }

    enum Level: String {
        case info = "INFO"
        case warn = "WARN"
        case error = "ERROR"
    }

    @Published private(set) var entries: [Entry] = []
    private let osLog = Logger(subsystem: "com.selkorin.cam", category: "app")
    private let maxEntries = 500

    func info(_ message: String) { append(.info, message) }
    func warn(_ message: String) { append(.warn, message) }
    func error(_ message: String) { append(.error, message) }

    private func append(_ level: Level, _ message: String) {
        switch level {
        case .info: osLog.info("\(message, privacy: .public)")
        case .warn: osLog.warning("\(message, privacy: .public)")
        case .error: osLog.error("\(message, privacy: .public)")
        }
        entries.append(Entry(date: Date(), level: level, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() { entries.removeAll() }
}

/// Log from any actor/thread; hops to the main actor.
func log(_ level: AppLog.Level = .info, _ message: String) {
    Task { @MainActor in
        switch level {
        case .info: AppLog.shared.info(message)
        case .warn: AppLog.shared.warn(message)
        case .error: AppLog.shared.error(message)
        }
    }
}
