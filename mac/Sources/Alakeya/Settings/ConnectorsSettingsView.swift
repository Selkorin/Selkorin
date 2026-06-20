import SwiftUI

// ============================================================
// ConnectorsSettingsView.swift — Settings → Коннекторы
// Shows connector cards grouped by category. Connect/disconnect
// actions are stubs (TODO: real OAuth flows).
// ============================================================

struct ConnectorsSettingsView: View {
    @StateObject private var registry = ConnectorRegistry.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(WAI.line).padding(.bottom, 16)
            connectorList
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Коннекторы")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(WAI.text)
            Text("Подключи внешние сервисы. Реальные API-вызовы появятся в следующих версиях.")
                .font(.system(size: 12))
                .foregroundStyle(WAI.textMuted)
        }
        .padding(.bottom, 16)
    }

    // MARK: - List grouped by category

    private var connectorList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(ConnectorCategory.allCases, id: \.self) { category in
                    let items = registry.connectors.filter { $0.category == category }
                    if !items.isEmpty {
                        categorySection(category: category, items: items)
                    }
                }
            }
        }
    }

    private func categorySection(category: ConnectorCategory, items: [Connector]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: category.iconName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WAI.textMuted)
                Text(category.title.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WAI.textMuted)
                    .kerning(0.8)
            }
            ForEach(items) { connector in
                ConnectorCard(connector: connector, status: registry.status(for: connector.id)) {
                    registry.connect(connectorID: connector.id)
                } onDisconnect: {
                    registry.disconnect(connectorID: connector.id)
                }
            }
        }
    }
}

// MARK: - ConnectorCard

private struct ConnectorCard: View {
    let connector: Connector
    let status: ConnectorStatus
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    @State private var showPermissions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(WAI.surfaceInset)
                    Image(systemName: connector.iconName)
                        .font(.system(size: 16))
                        .foregroundStyle(WAI.text)
                }
                .frame(width: 36, height: 36)

                // Title + description
                VStack(alignment: .leading, spacing: 2) {
                    Text(connector.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(WAI.text)
                    Text(connector.description)
                        .font(.system(size: 11))
                        .foregroundStyle(WAI.textMuted)
                        .lineLimit(2)
                }

                Spacer()

                // Status badge + button
                VStack(alignment: .trailing, spacing: 4) {
                    statusBadge
                    actionButton
                }
            }
            .padding(12)

            // Expandable permissions
            if showPermissions {
                permissionsView
            }

            // Expand toggle
            if !connector.permissions.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showPermissions.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text(showPermissions ? "Скрыть разрешения" : "Разрешения (\(connector.permissions.count))")
                            .font(.system(size: 11))
                            .foregroundStyle(WAI.textMuted)
                        Image(systemName: showPermissions ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(WAI.textMuted)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(WAI.surfaceInset.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(WAI.line))
    }

    // MARK: - Sub-views

    private var statusBadge: some View {
        Text(status.title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(statusColor.opacity(0.15))
            .clipShape(Capsule())
    }

    private var actionButton: some View {
        Group {
            if status == .connected {
                Button("Отключить") { onDisconnect() }
                    .buttonStyle(SmallDestructiveButtonStyle())
            } else {
                Button("Подключить") { onConnect() }
                    .buttonStyle(SmallPrimaryButtonStyle())
            }
        }
    }

    private var permissionsView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider().overlay(WAI.line)
            ForEach(connector.permissions) { perm in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(riskColor(perm.risk))
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(perm.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WAI.text)
                        Text(perm.description)
                            .font(.system(size: 10))
                            .foregroundStyle(WAI.textMuted)
                    }
                    Spacer()
                    Text(perm.risk.title)
                        .font(.system(size: 9))
                        .foregroundStyle(riskColor(perm.risk))
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
        }
    }

    private var statusColor: Color {
        switch status {
        case .connected:    return .green
        case .needsAuth:    return .orange
        case .error:        return .red
        case .disabled:     return WAI.textMuted
        case .disconnected: return WAI.textDim
        }
    }

    private func riskColor(_ risk: PermissionRisk) -> Color {
        switch risk {
        case .low:    return .green
        case .medium: return .orange
        case .high:   return .red
        }
    }
}

// MARK: - Button styles

private struct SmallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(WAI.accent)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

private struct SmallDestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.red)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.red.opacity(0.12))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
