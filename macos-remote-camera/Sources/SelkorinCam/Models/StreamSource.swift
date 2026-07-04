import Foundation

/// Where the macOS app gets live video from.
enum StreamSource: Hashable {
    /// The Mac runs an HTTP endpoint and the phone PUSHes JPEG frames to it.
    /// Used by the bundled browser phone client (PhoneClient/index.html).
    case pushServer(port: UInt16)

    /// The Mac PULLs an existing MJPEG stream, e.g. from a phone "IP webcam"
    /// app or an IP camera. URL points at a multipart/x-mixed-replace stream.
    case mjpegPull(url: URL)

    var label: String {
        switch self {
        case .pushServer(let port):
            return "Push server on :\(port)"
        case .mjpegPull(let url):
            return "MJPEG pull \(url.host ?? url.absoluteString)"
        }
    }
}

/// Recording configuration for a live session.
struct RecordingOptions {
    enum Container: String, CaseIterable, Identifiable {
        case quickTimeMOV = "MOV (H.264)"
        case jpegSequence = "JPEG frames"
        var id: String { rawValue }
    }

    var container: Container = .quickTimeMOV
    var frameRate: Int = 15
    /// Directory recordings are written into.
    var outputDirectory: URL

    static func defaultOptions() -> RecordingOptions {
        let base = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let dir = base.appendingPathComponent("SelkorinCam", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return RecordingOptions(outputDirectory: dir)
    }
}
