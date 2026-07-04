import SwiftUI
import AppKit

struct LiveCameraView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var session: CameraSession
    @State private var mode: Mode = .pushFromPhone
    @State private var mjpegURLText = "http://192.168.1.50:8080/video"

    enum Mode: String, CaseIterable, Identifiable {
        case pushFromPhone = "Phone pushes to Mac"
        case pullMJPEG = "Mac pulls MJPEG/IP-webcam"
        var id: String { rawValue }
    }

    var body: some View {
        HSplitView {
            preview
                .frame(minWidth: 420)
            controls
                .frame(width: 340)
        }
        .navigationTitle("Live Camera")
    }

    private var preview: some View {
        ZStack {
            Color.black
            if let image = session.latestImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 44))
                        .foregroundStyle(.secondary)
                    Text(session.isRunning ? "Waiting for frames…" : "Not connected")
                        .foregroundStyle(.secondary)
                }
            }
            if session.isRecording {
                VStack {
                    HStack {
                        Circle().fill(.red).frame(width: 10, height: 10)
                        Text("REC").font(.caption.monospaced().bold()).foregroundStyle(.red)
                        Spacer()
                    }
                    .padding(10)
                    Spacer()
                }
            }
        }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Source", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .pushFromPhone: pushInstructions
                case .pullMJPEG: pullControls
                }

                Divider()
                statusBlock
                Divider()
                recordingControls
            }
            .padding(16)
        }
    }

    private var pushInstructions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Stream from your phone").font(.headline)
            Text("On the same Wi-Fi, open the bundled `PhoneClient/index.html` in your phone's browser and set the target to:")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("http://\(appState.macLANAddress):\(appState.pushPort)")
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))

            HStack {
                Button(session.isRunning ? "Stop server" : "Start server") {
                    if session.isRunning {
                        session.stop()
                    } else {
                        session.start(source: .pushServer(port: appState.pushPort))
                    }
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
        }
    }

    private var pullControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pull an MJPEG stream").font(.headline)
            Text("Works with phone IP-webcam apps and cameras exposing an MJPEG endpoint (multipart/x-mixed-replace).")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextField("http://<phone-ip>:8080/video", text: $mjpegURLText)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
            HStack {
                Button(session.isRunning ? "Disconnect" : "Connect") {
                    if session.isRunning {
                        session.stop()
                    } else if let url = URL(string: mjpegURLText) {
                        session.start(source: .mjpegPull(url: url))
                    }
                }
                .keyboardShortcut(.defaultAction)
                Spacer()
            }
        }
    }

    private var statusBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(session.statusText, systemImage: "info.circle")
                .font(.callout)
            HStack(spacing: 16) {
                stat("Frames", "\(session.receivedFrameCount)")
                stat("FPS", String(format: "%.1f", session.measuredFPS))
            }
        }
    }

    private var recordingControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recording").font(.headline)
            Picker("Format", selection: Binding(
                get: { session.recordingOptions.container },
                set: { session.recordingOptions.container = $0 })) {
                ForEach(RecordingOptions.Container.allCases) { Text($0.rawValue).tag($0) }
            }
            Button(session.isRecording ? "Stop recording" : "Start recording") {
                session.toggleRecording()
            }
            .disabled(!session.isRunning)
            .tint(session.isRecording ? .red : .accentColor)

            if let url = session.lastRecordingURL {
                HStack {
                    Text("Saved:").foregroundStyle(.secondary)
                    Button(url.lastPathComponent) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)
            }
            Text("Output: \(session.recordingOptions.outputDirectory.path)")
                .font(.caption).foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading) {
            Text(value).font(.title3.monospacedDigit().bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}
