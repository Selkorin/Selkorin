import Foundation
import AppKit

// TODO: Sparkle integration
// When Sparkle 2 is added to Package.swift and Sparkle.framework is embedded in
// Contents/Frameworks, replace this class body with an SPUStandardUpdaterController
// wrapper. See scripts/make_release.sh for the EdDSA signing workflow.
//
// Package.swift addition:
//   .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0")
//   target dependency: .product(name: "Sparkle", package: "Sparkle")
// Info.plist additions: SUPublicEDKey, SUFeedURL, SUEnableAutomaticChecks

enum UpdateState: Equatable {
    case idle
    case checking
    case updateAvailable(UpdateInfo)
    case downloading(Double)
    case installing
    case upToDate
    case failed(String)

    static func == (lhs: UpdateState, rhs: UpdateState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.checking, .checking),
             (.installing, .installing), (.upToDate, .upToDate):
            return true
        case (.updateAvailable(let a), .updateAvailable(let b)):
            return a.version == b.version
        case (.downloading(let a), .downloading(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }

    var statusLabel: String {
        switch self {
        case .idle:               return ""
        case .checking:           return "Проверка обновлений…"
        case .updateAvailable(let i): return "Доступна версия \(i.version)"
        case .downloading(let p): return "Загрузка… \(Int(p * 100))%"
        case .installing:         return "Установка…"
        case .upToDate:           return "Установлена последняя версия"
        case .failed(let e):      return "Ошибка: \(e)"
        }
    }
}

@MainActor
final class UpdateManager: ObservableObject {
    @Published var state: UpdateState = .idle
    @Published var showPrompt = false
    @Published var pendingUpdate: UpdateInfo? = nil
    @Published private(set) var lastChecked: Date?

    var channel: UpdateChannel = .stable
    var autoCheck: Bool = true
    var skippedVersion: String?

    private var downloadTask: URLSessionDownloadTask?
    private var progressObservation: NSKeyValueObservation?

    init() {}

    func initialize(settings: Settings.Updates) {
        channel       = settings.channel
        autoCheck     = settings.autoCheck
        skippedVersion = settings.skippedVersion
        lastChecked   = settings.lastChecked
    }

    func exportSettings() -> Settings.Updates {
        Settings.Updates(
            autoCheck: autoCheck,
            channel: channel,
            lastChecked: lastChecked,
            skippedVersion: skippedVersion
        )
    }

    // Called 3 s after launch if autoCheck is enabled
    func checkOnLaunchIfEnabled() async {
        guard autoCheck else { return }
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await checkForUpdates(quiet: true)
    }

    func checkForUpdates(quiet: Bool = false) async {
        guard !isBusy else { return }
        state = .checking

        do {
            let info = try await fetchLatestInfo()
            lastChecked = Date()
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            if info.isNewerThan(current), info.version != skippedVersion {
                pendingUpdate = info
                state = .updateAvailable(info)
                showPrompt = true
            } else {
                pendingUpdate = nil
                state = .upToDate
                // In quiet mode don't reset to .idle so the settings tab can show "up to date"
                if quiet { DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                    if self.state == .upToDate { self.state = .idle }
                }}
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func dismissPrompt() {
        showPrompt = false
        if case .updateAvailable(_) = state { /* keep state so settings tab shows it */ }
        else { state = .idle }
    }

    func skipVersion(_ version: String) {
        skippedVersion = version
        showPrompt = false
        state = .idle
    }

    func downloadAndInstall(_ info: UpdateInfo) {
        guard let url = URL(string: info.downloadURL) else {
            state = .failed("Некорректный URL обновления")
            return
        }
        showPrompt = false
        state = .downloading(0)

        // TODO: verify EdDSA signature (sparkle:edSignature) before installing
        let task = URLSession.shared.downloadTask(with: url) { [weak self] localURL, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.progressObservation?.invalidate()
                self.progressObservation = nil

                if let error {
                    self.state = .failed(error.localizedDescription)
                    return
                }
                guard let localURL else {
                    self.state = .failed("Файл не загружен")
                    return
                }
                self.runInstall(from: localURL, info: info)
            }
        }

        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] prog, _ in
            Task { @MainActor [weak self] in
                self?.state = .downloading(prog.fractionCompleted)
            }
        }

        downloadTask = task
        task.resume()
    }

    func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        progressObservation?.invalidate()
        progressObservation = nil
        state = .idle
    }

    // MARK: - Private

    private func runInstall(from zipURL: URL, info: UpdateInfo) {
        state = .installing

        // TODO: Full auto-install requires:
        //   1. Extract zip to tmp
        //   2. Verify bundle signature
        //   3. Quit app, run installer shell script, relaunch
        //   With Sparkle all of this is handled automatically.
        //
        // MVP: move the zip next to the app so the user can install manually.
        let dest = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Downloads")
            .appendingPathComponent("Alakeya-\(info.version).zip")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: zipURL, to: dest)
            NSWorkspace.shared.activateFileViewerSelecting([dest])
            state = .idle
        } catch {
            // If move fails, just open the tmp file location
            NSWorkspace.shared.activateFileViewerSelecting([zipURL])
            state = .idle
        }
    }

    private func fetchLatestInfo() async throws -> UpdateInfo {
        guard let url = URL(string: channel.feedURL) else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(UpdateInfo.self, from: data)
    }

    private var isBusy: Bool {
        switch state {
        case .checking, .downloading(_), .installing: return true
        default: return false
        }
    }
}
