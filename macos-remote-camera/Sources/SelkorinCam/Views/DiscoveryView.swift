import SwiftUI
import AppKit

struct DiscoveryView: View {
    @EnvironmentObject var discovery: DiscoveryCoordinator
    @State private var selected: DiscoveredCamera?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AuthorizationGateView(authorized: Binding(
                get: { discovery.authorized },
                set: { discovery.authorized = $0 }),
                featureName: "Camera discovery (ONVIF, Bonjour, port probe)")

            HStack {
                TextField("Subnet (a.b.c.0/24)", text: Binding(
                    get: { discovery.subnetCIDR },
                    set: { discovery.subnetCIDR = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 200)

                Button(discovery.isScanning ? "Stop" : "Scan") {
                    discovery.isScanning ? discovery.stopScan() : discovery.startScan()
                }
                .disabled(!discovery.authorized)
                .keyboardShortcut(.defaultAction)

                if discovery.isScanning { ProgressView().controlSize(.small) }
                Spacer()
                Text(discovery.progressText).font(.callout).foregroundStyle(.secondary)
            }

            HSplitView {
                cameraList
                    .frame(minWidth: 280)
                detail
                    .frame(minWidth: 300)
            }
        }
        .padding(16)
        .navigationTitle("Camera Discovery")
    }

    private var cameraList: some View {
        List {
            ForEach(discovery.cameras) { cam in
                HStack(spacing: 10) {
                    Image(systemName: CameraFingerprint.looksLikeCamera(openPorts: cam.openPorts)
                          ? "video.fill" : "network")
                        .foregroundStyle(CameraFingerprint.looksLikeCamera(openPorts: cam.openPorts)
                                         ? .green : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cam.displayName).font(.body.weight(.medium))
                        Text("\(cam.ipAddress) · \(cam.source.rawValue)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(cam.openPorts.count) ports")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
                .listRowBackground(selected == cam
                                   ? Color.accentColor.opacity(0.15) : Color.clear)
                .onTapGesture { selected = cam }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let cam = selected ?? discovery.cameras.first {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(cam.displayName).font(.title2.bold())
                    labeled("IP address", cam.ipAddress)
                    if let host = cam.hostname { labeled("Hostname", host) }
                    if let vendor = cam.vendorGuess { labeled("Vendor guess", vendor) }
                    labeled("First discovered via", cam.source.rawValue)

                    if !cam.openPorts.isEmpty {
                        Text("Open ports").font(.headline).padding(.top, 4)
                        ForEach(cam.openPorts, id: \.self) { p in
                            HStack {
                                Text(String(p.port)).font(.system(.body, design: .monospaced)).frame(width: 60, alignment: .leading)
                                Text(p.service).foregroundStyle(.secondary)
                                Spacer()
                            }
                            if let banner = p.banner, !banner.isEmpty {
                                Text(banner)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(3)
                            }
                        }
                    }

                    if !cam.serviceURLs.isEmpty {
                        Text("Service URLs").font(.headline).padding(.top, 4)
                        ForEach(cam.serviceURLs, id: \.self) { url in
                            HStack {
                                Text(url).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                                Spacer()
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(url, forType: .string)
                                } label: { Image(systemName: "doc.on.doc") }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    Text("""
                    To view a stream, use the camera's RTSP/ONVIF URL with the \
                    credentials **you** have for it (e.g. in VLC or the Live tab's \
                    MJPEG mode for MJPEG-capable cameras). This tool does not \
                    guess or brute-force credentials.
                    """)
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.top, 6)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(4)
            }
        } else {
            VStack {
                Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 40)).foregroundStyle(.secondary)
                Text("Run a scan to inventory cameras on your subnet.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).foregroundStyle(.secondary).frame(width: 130, alignment: .leading)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
    }
}
