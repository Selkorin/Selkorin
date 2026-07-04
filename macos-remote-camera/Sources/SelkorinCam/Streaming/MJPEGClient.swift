import Foundation

/// Pulls an MJPEG (`multipart/x-mixed-replace`) stream and emits individual
/// JPEG frames. Works with typical phone "IP webcam" apps and many IP cameras
/// that expose an MJPEG endpoint, e.g. http://<phone-ip>:8080/video.
///
/// Frames are found by scanning for JPEG start (FFD8) and end (FFD9) markers,
/// which is tolerant of how a given server formats its multipart boundaries.
final class MJPEGClient: NSObject, URLSessionDataDelegate {

    var onJPEGFrame: ((Data) -> Void)?
    var onStatus: ((String) -> Void)?

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private let url: URL
    /// Optional Basic-auth credentials the user supplied for a protected camera.
    private let username: String?
    private let password: String?

    private static let soi = Data([0xFF, 0xD8]) // JPEG start of image
    private static let eoi = Data([0xFF, 0xD9]) // JPEG end of image

    init(url: URL, username: String? = nil, password: String? = nil) {
        self.url = url
        self.username = username
        self.password = password
    }

    func start() {
        var request = URLRequest(url: url, timeoutInterval: 15)
        if let username, let password {
            let token = Data("\(username):\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 0 // streaming: no overall timeout
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        self.task = task
        onStatus?("Connecting to \(url.absoluteString)…")
        log(.info, "MJPEGClient connecting to \(url.absoluteString)")
        task.resume()
    }

    func stop() {
        task?.cancel()
        session?.invalidateAndCancel()
        buffer.removeAll()
    }

    // MARK: URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 200 {
                onStatus?("Streaming")
            } else {
                onStatus?("HTTP \(http.statusCode)")
                log(.warn, "MJPEGClient got HTTP \(http.statusCode) from \(url.absoluteString)")
            }
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        buffer.append(data)
        extractFrames()
        // Guard against unbounded growth if we never see a valid frame boundary.
        if buffer.count > 8 * 1024 * 1024 {
            buffer.removeAll(keepingCapacity: true)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error, (error as NSError).code != NSURLErrorCancelled {
            onStatus?("Disconnected: \(error.localizedDescription)")
            log(.warn, "MJPEGClient disconnected: \(error.localizedDescription)")
        } else {
            onStatus?("Stopped")
        }
    }

    private func extractFrames() {
        while true {
            guard let start = buffer.range(of: MJPEGClient.soi) else { return }
            guard let end = buffer.range(of: MJPEGClient.eoi,
                                         in: start.upperBound..<buffer.endIndex) else { return }
            let frame = buffer.subdata(in: start.lowerBound..<end.upperBound)
            buffer.removeSubrange(buffer.startIndex..<end.upperBound)
            onJPEGFrame?(frame)
        }
    }
}
