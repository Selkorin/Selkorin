import Foundation

final class AIProviderStore {
    static let shared = AIProviderStore()

    private let keychain = KeychainService.shared

    private init() {}

    func apiKey(for providerID: String) throws -> String? {
        try keychain.read(account: providerID)
    }

    func saveAPIKey(_ apiKey: String, for providerID: String) throws {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try keychain.delete(account: providerID)
        } else {
            try keychain.save(trimmed, account: providerID)
        }
    }

    func activeConfiguration(in settings: Settings) throws -> AIProviderConfiguration {
        guard let configuration = settings.models.providers.first(where: {
            $0.id == settings.models.activeProviderID
        }) else {
            throw AIClientError.providerNotSelected
        }
        guard !configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIClientError.modelMissing
        }
        return configuration
    }
}

