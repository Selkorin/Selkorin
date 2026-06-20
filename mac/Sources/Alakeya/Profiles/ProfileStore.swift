import AppKit
import Foundation

struct PersonProfile: Codable, Equatable {
    var name: String
    var avatarPath: String?
}

@MainActor
final class ProfileStore: ObservableObject {
    static let shared = ProfileStore()

    @Published private(set) var user: PersonProfile
    @Published private(set) var agentAvatars: [String: String]

    private let directory: URL
    private let metadataURL: URL

    private struct Metadata: Codable {
        var user: PersonProfile
        var agentAvatars: [String: String]
    }

    private init() {
        directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Alakeya/Profiles", isDirectory: true)
        metadataURL = directory.appendingPathComponent("profiles.json")
        let loaded = Self.load(from: metadataURL)
        user = loaded?.user ?? PersonProfile(name: NSFullUserName(), avatarPath: nil)
        agentAvatars = loaded?.agentAvatars ?? [:]
    }

    func updateUser(name: String, avatarData: Data?) throws {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { throw ProfileStoreError.emptyName }
        var path = user.avatarPath
        if let avatarData {
            path = try saveAvatar(avatarData, filename: "user-avatar.jpg").path
        }
        user = PersonProfile(name: cleanName, avatarPath: path)
        try persist()
    }

    func setAgentAvatar(_ data: Data, agentID: String) throws {
        let url = try saveAvatar(data, filename: "\(agentID)-avatar.jpg")
        agentAvatars[agentID] = url.path
        try persist()
    }

    func userAvatar() -> NSImage? {
        image(at: user.avatarPath)
    }

    func agentAvatar(for id: String) -> NSImage? {
        image(at: agentAvatars[id])
    }

    private func image(at path: String?) -> NSImage? {
        guard let path else { return nil }
        return NSImage(contentsOfFile: path)
    }

    private func saveAvatar(_ data: Data, filename: String) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func persist() throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(
            Metadata(user: user, agentAvatars: agentAvatars)
        )
        try data.write(to: metadataURL, options: .atomic)
    }

    private static func load(from url: URL) -> Metadata? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Metadata.self, from: data)
    }
}

enum ProfileStoreError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        "Введите имя профиля."
    }
}
