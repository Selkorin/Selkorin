import SwiftUI

struct ContentView: View {
    @State private var selection: Tab? = .live

    enum Tab: String, CaseIterable, Identifiable {
        case live = "Live Camera"
        case discovery = "Camera Discovery"
        case analysis = "Traffic Analysis"
        case log = "Activity Log"
        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .live: return "video.fill"
            case .discovery: return "dot.radiowaves.left.and.right"
            case .analysis: return "waveform.path.ecg"
            case .log: return "list.bullet.rectangle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Tab.allCases, id: \.self, selection: $selection) { tab in
                Label(tab.rawValue, systemImage: tab.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
            .listStyle(.sidebar)
        } detail: {
            switch selection ?? .live {
            case .live:
                LiveCameraView()
            case .discovery:
                DiscoveryView()
            case .analysis:
                AnalysisView()
            case .log:
                ActivityLogView()
            }
        }
    }
}
