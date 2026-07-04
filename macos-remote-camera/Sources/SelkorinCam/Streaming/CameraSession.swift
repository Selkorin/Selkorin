import Foundation
import SwiftUI
import AppKit

/// View model for a single live camera session: owns the active stream source
/// (push server or MJPEG pull), publishes the latest frame for the UI, and
/// drives the recorder.
@MainActor
final class CameraSession: ObservableObject {

    @Published var latestImage: NSImage?
    @Published var isRunning = false
    @Published var isRecording = false
    @Published var statusText = "Idle"
    @Published var receivedFrameCount = 0
    @Published var measuredFPS: Double = 0
    @Published var lastRecordingURL: URL?

    var recordingOptions = RecordingOptions.defaultOptions()

    private var server: StreamServer?
    private var mjpeg: MJPEGClient?
    private var recorder: FrameRecorder?

    // FPS measurement
    private var fpsWindowStart = Date()
    private var fpsWindowCount = 0

    func start(source: StreamSource) {
        stop()
        statusText = "Starting…"
        isRunning = true
        receivedFrameCount = 0

        switch source {
        case .pushServer(let port):
            let server = StreamServer(port: port)
            server.onStatus = { [weak self] text in
                Task { @MainActor in self?.statusText = text }
            }
            server.onJPEGFrame = { [weak self] data in
                Task { @MainActor in self?.ingest(jpeg: data) }
            }
            do {
                try server.start()
                self.server = server
            } catch {
                statusText = "Server error: \(error.localizedDescription)"
                isRunning = false
            }

        case .mjpegPull(let url):
            let client = MJPEGClient(url: url)
            client.onStatus = { [weak self] text in
                Task { @MainActor in self?.statusText = text }
            }
            client.onJPEGFrame = { [weak self] data in
                Task { @MainActor in self?.ingest(jpeg: data) }
            }
            client.start()
            self.mjpeg = client
        }
    }

    func stop() {
        if isRecording { stopRecording() }
        server?.stop(); server = nil
        mjpeg?.stop(); mjpeg = nil
        isRunning = false
        statusText = "Idle"
    }

    func toggleRecording() {
        isRecording ? stopRecording() : startRecordingPending()
    }

    // MARK: - Frame ingestion

    private var pendingRecordingStart = false

    private func startRecordingPending() {
        // Recording begins on the next frame (we need its dimensions).
        pendingRecordingStart = true
        statusText = "Recording will start on next frame…"
    }

    private func ingest(jpeg: Data) {
        receivedFrameCount += 1
        updateFPS()

        if let image = NSImage(data: jpeg) {
            latestImage = image
        }

        if pendingRecordingStart {
            pendingRecordingStart = false
            let recorder = FrameRecorder(options: recordingOptions)
            do {
                try recorder.start(firstFrame: jpeg)
                self.recorder = recorder
                isRecording = true
                statusText = "Recording"
            } catch {
                statusText = "Record error: \(error.localizedDescription)"
                log(.error, "Record start failed: \(error.localizedDescription)")
            }
            return
        }

        recorder?.append(jpeg)
    }

    private func stopRecording() {
        recorder?.stop { [weak self] url in
            Task { @MainActor in
                self?.lastRecordingURL = url
                self?.isRecording = false
                self?.statusText = self?.isRunning == true ? "Live" : "Idle"
            }
        }
        recorder = nil
    }

    private func updateFPS() {
        fpsWindowCount += 1
        let elapsed = Date().timeIntervalSince(fpsWindowStart)
        if elapsed >= 1.0 {
            measuredFPS = Double(fpsWindowCount) / elapsed
            fpsWindowCount = 0
            fpsWindowStart = Date()
        }
    }
}
