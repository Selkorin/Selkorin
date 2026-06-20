import SwiftUI

struct ModelsSettingsView: View {
    @ObservedObject var store: AgentStore

    @State private var selectedProviderID = AIProviderKind.openAI.rawValue
    @State private var displayName = ""
    @State private var baseURL = ""
    @State private var modelName = ""
    @State private var apiKey = ""
    @State private var statusMessage = ""
    @State private var isTesting = false

    private var selectedKind: AIProviderKind {
        store.settings.models.providers.first(where: { $0.id == selectedProviderID })?.kind
            ?? .openAI
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Models")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(WAI.text)

            settingRow("Active Provider") {
                Picker("", selection: $selectedProviderID) {
                    ForEach(store.settings.models.providers) { provider in
                        Text(provider.displayName).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(width: 240)
                .onChange(of: selectedProviderID) { _, _ in loadDraft() }
            }

            if selectedKind == .custom {
                settingRow("Provider name") {
                    textField("My Provider", text: $displayName)
                }
                settingRow("Base URL") {
                    textField("https://example.com/v1", text: $baseURL)
                }
            }

            settingRow("API Key") {
                SecureField("sk-…", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 280)
            }

            settingRow("Model name") {
                textField(selectedKind.defaultModel, text: $modelName)
            }

            HStack(spacing: 14) {
                Button(isTesting ? "Testing…" : "Test connection") {
                    Task { await testConnection() }
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)

                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(WAI.accent)

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(
                            statusMessage.hasPrefix("Готово") ? WAI.success : WAI.textMuted
                        )
                }
            }
        }
        .onAppear {
            selectedProviderID = store.settings.models.activeProviderID
            loadDraft()
        }
    }

    private func textField(_ prompt: String, text: Binding<String>) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
    }

    private func settingRow(_ title: String, @ViewBuilder control: () -> some View) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(WAI.textDim)
            Spacer()
            control()
        }
    }

    private func loadDraft() {
        guard let provider = store.settings.models.providers.first(where: {
            $0.id == selectedProviderID
        }) else { return }

        displayName = provider.displayName
        baseURL = provider.baseURL
        modelName = provider.modelName
        apiKey = (try? AIProviderStore.shared.apiKey(for: provider.id)) ?? ""
        statusMessage = ""
    }

    private func draftConfiguration() -> AIProviderConfiguration? {
        guard let existing = store.settings.models.providers.first(where: {
            $0.id == selectedProviderID
        }) else { return nil }

        return AIProviderConfiguration(
            id: existing.id,
            kind: existing.kind,
            displayName: selectedKind == .custom
                ? displayName.trimmingCharacters(in: .whitespacesAndNewlines)
                : existing.displayName,
            baseURL: selectedKind == .custom
                ? baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                : existing.baseURL,
            modelName: modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func save() {
        guard let configuration = draftConfiguration() else { return }
        guard !configuration.modelName.isEmpty else {
            statusMessage = AIClientError.modelMissing.localizedDescription
            return
        }
        if selectedKind == .custom,
           configuration.displayName.isEmpty || URL(string: configuration.baseURL) == nil {
            statusMessage = AIClientError.invalidBaseURL.localizedDescription
            return
        }

        do {
            try AIProviderStore.shared.saveAPIKey(apiKey, for: configuration.id)
            guard let index = store.settings.models.providers.firstIndex(where: {
                $0.id == configuration.id
            }) else { return }
            store.settings.models.providers[index] = configuration
            store.settings.models.activeProviderID = configuration.id
            store.settings.save()
            statusMessage = "Готово. Настройки сохранены."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func testConnection() async {
        guard let configuration = draftConfiguration() else { return }
        isTesting = true
        statusMessage = ""
        defer { isTesting = false }

        do {
            let client = try AIClient(configuration: configuration, apiKey: apiKey)
            _ = try await client.sendMessage(userText: "Ответь одним словом: OK", history: [])
            statusMessage = "Готово. Соединение работает."
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

