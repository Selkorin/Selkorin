import SwiftUI

@main
struct SelkorinCamApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.cameraSession)
                .environmentObject(appState.discovery)
                .environmentObject(appState.analyzer)
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
    }
}

/// App-wide state shared across tabs.
@MainActor
final class AppState: ObservableObject {
    /// User acknowledgement of the authorized-use notice. Network-facing
    /// features (discovery, packet analysis) stay disabled until this is set.
    @Published var authorizedForNetworkOps = false

    /// Default port the push stream server listens on.
    @Published var pushPort: UInt16 = 8099

    let cameraSession = CameraSession()
    let discovery = DiscoveryCoordinator()
    let analyzer = PacketAnalyzer()

    /// IPv4 address a phone on the same LAN should point its stream at.
    var macLANAddress: String {
        LocalNetwork.interfaceIPv4Addresses().first ?? "your-mac-ip"
    }
}
