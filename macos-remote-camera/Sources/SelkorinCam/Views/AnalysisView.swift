import SwiftUI

struct AnalysisView: View {
    @EnvironmentObject var analyzer: PacketAnalyzer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuthorizationGateView(authorized: Binding(
                get: { analyzer.authorized },
                set: { analyzer.authorized = $0 }),
                featureName: "Passive traffic analysis")

            Text("""
            Read-only flow summary of camera-related traffic on an interface you \
            own. Headers only — payloads are never decoded or stored. Requires \
            BPF access (run the app with sufficient privileges, same as Wireshark).
            """)
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("Interface", text: Binding(
                    get: { analyzer.interfaceName },
                    set: { analyzer.interfaceName = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                TextField("BPF filter", text: Binding(
                    get: { analyzer.bpfFilter },
                    set: { analyzer.bpfFilter = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
                Button(analyzer.isCapturing ? "Stop" : "Start") {
                    analyzer.isCapturing ? analyzer.stop() : analyzer.start()
                }
                .disabled(!analyzer.authorized)
                .keyboardShortcut(.defaultAction)
            }

            Label(analyzer.statusText, systemImage: "info.circle").font(.callout)

            flowTable
        }
        .padding(16)
        .navigationTitle("Traffic Analysis")
    }

    private var flowTable: some View {
        Table(analyzer.flows) {
            TableColumn("Source") { Text("\($0.sourceIP):\($0.sourcePort)").font(.system(.caption, design: .monospaced)) }
            TableColumn("Destination") { Text("\($0.destIP):\($0.destPort)").font(.system(.caption, design: .monospaced)) }
            TableColumn("Proto") { Text($0.appProtocol).font(.caption) }
            TableColumn("Packets") { Text("\($0.packetCount)").font(.system(.caption, design: .monospaced)) }
            TableColumn("Bytes") { Text(byteString($0.byteCount)).font(.system(.caption, design: .monospaced)) }
        }
    }

    private func byteString(_ n: Int) -> String {
        let units = ["B", "KB", "MB", "GB"]
        var value = Double(n)
        var idx = 0
        while value >= 1024 && idx < units.count - 1 { value /= 1024; idx += 1 }
        return String(format: "%.1f %@", value, units[idx])
    }
}
