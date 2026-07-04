import Foundation
import Network

/// A tiny HTTP/1.1 server (Network framework) that receives JPEG frames PUSHed
/// by the bundled browser phone client. The phone captures its camera with
/// getUserMedia and POSTs each frame to `POST /frame`; this server hands the
/// bytes to whoever set `onJPEGFrame`.
///
/// It is intentionally minimal: it speaks just enough HTTP to accept frame
/// uploads and answer a health check. It binds on all interfaces so a phone on
/// the same LAN can reach it.
final class StreamServer {

    /// Called on a background queue with each received JPEG frame's bytes.
    var onJPEGFrame: ((Data) -> Void)?
    /// Called when the listener state changes (ready / failed) with a message.
    var onStatus: ((String) -> Void)?

    private var listener: NWListener?
    private let port: UInt16
    private let queue = DispatchQueue(label: "com.selkorin.streamserver")
    private(set) var frameCount = 0

    init(port: UInt16) {
        self.port = port
    }

    func start() throws {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw NSError(domain: "StreamServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }
        let listener = try NWListener(using: params, on: nwPort)
        self.listener = listener

        listener.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.onStatus?("Listening on :\(self?.port ?? 0)")
                log(.info, "StreamServer ready on :\(self?.port ?? 0)")
            case .failed(let err):
                self?.onStatus?("Failed: \(err.localizedDescription)")
                log(.error, "StreamServer failed: \(err.localizedDescription)")
            case .cancelled:
                self?.onStatus?("Stopped")
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] conn in
            self?.handle(connection: conn)
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(connection: NWConnection) {
        let handler = ConnectionHandler(connection: connection, queue: queue) { [weak self] jpeg in
            self?.frameCount += 1
            self?.onJPEGFrame?(jpeg)
        }
        handler.start()
    }
}

/// Parses (possibly pipelined) HTTP requests on a single keep-alive connection.
private final class ConnectionHandler {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let onFrame: (Data) -> Void
    private var buffer = Data()

    init(connection: NWConnection, queue: DispatchQueue, onFrame: @escaping (Data) -> Void) {
        self.connection = connection
        self.queue = queue
        self.onFrame = onFrame
    }

    func start() {
        connection.start(queue: queue)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainRequests()
            }
            if isComplete || error != nil {
                self.connection.cancel()
            } else {
                self.receive()
            }
        }
    }

    /// Parse as many complete requests as the buffer currently holds.
    private func drainRequests() {
        while let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) {
            let headerData = buffer.subdata(in: buffer.startIndex..<headerEnd.lowerBound)
            guard let headerText = String(data: headerData, encoding: .utf8) else {
                connection.cancel(); return
            }
            let lines = headerText.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else { connection.cancel(); return }
            let tokens = requestLine.split(separator: " ")
            guard tokens.count >= 2 else { connection.cancel(); return }
            let method = String(tokens[0])
            let path = String(tokens[1])

            var contentLength = 0
            for line in lines.dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2, parts[0].lowercased() == "content-length" {
                    contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                }
            }

            let bodyStart = headerEnd.upperBound
            let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
            if available < contentLength {
                // Body not fully arrived yet; wait for more bytes.
                return
            }
            let bodyEnd = buffer.index(bodyStart, offsetBy: contentLength)
            let body = buffer.subdata(in: bodyStart..<bodyEnd)
            buffer.removeSubrange(buffer.startIndex..<bodyEnd)

            route(method: method, path: path, body: body)
        }
    }

    private func route(method: String, path: String, body: Data) {
        switch (method, path) {
        case ("OPTIONS", _):
            respond(status: "204 No Content", extraHeaders: corsHeaders)
        case ("POST", "/frame"):
            if !body.isEmpty { onFrame(body) }
            respond(status: "204 No Content", extraHeaders: corsHeaders)
        case ("GET", "/"), ("GET", "/health"):
            let payload = Data("SelkorinCam stream server OK\n".utf8)
            respond(status: "200 OK",
                    extraHeaders: corsHeaders + ["Content-Type: text/plain"],
                    body: payload)
        default:
            respond(status: "404 Not Found", extraHeaders: corsHeaders)
        }
    }

    private var corsHeaders: [String] {
        [
            "Access-Control-Allow-Origin: *",
            "Access-Control-Allow-Methods: GET, POST, OPTIONS",
            "Access-Control-Allow-Headers: Content-Type"
        ]
    }

    private func respond(status: String, extraHeaders: [String] = [], body: Data = Data()) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Connection: keep-alive\r\n"
        head += "Content-Length: \(body.count)\r\n"
        for h in extraHeaders { head += h + "\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        connection.send(content: out, completion: .contentProcessed { _ in })
    }
}
