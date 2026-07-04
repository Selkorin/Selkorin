import Foundation
import AVFoundation
import CoreGraphics
import ImageIO

/// Records a stream of JPEG frames to disk, either as an H.264 QuickTime movie
/// (via AVAssetWriter) or as a numbered sequence of .jpg files.
///
/// Frames arrive at an irregular cadence (network jitter), so timestamps are
/// derived from wall-clock time relative to the first frame rather than a fixed
/// frame rate.
final class FrameRecorder {

    private let options: RecordingOptions
    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: Date?
    private var frameSize: CGSize?
    private var jpegSequenceDir: URL?
    private var jpegIndex = 0
    private let timescale: Int32 = 600
    private(set) var outputURL: URL?
    private(set) var isRecording = false

    init(options: RecordingOptions) {
        self.options = options
    }

    /// Begin a new recording. `firstFrame` is used to lock in the video
    /// dimensions for the movie writer.
    func start(firstFrame jpeg: Data) throws {
        guard let image = Self.cgImage(fromJPEG: jpeg) else {
            throw NSError(domain: "FrameRecorder", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "First frame is not a decodable JPEG"])
        }
        let size = CGSize(width: image.width, height: image.height)
        frameSize = size
        startTime = Date()
        let stamp = Self.timestampString()

        switch options.container {
        case .jpegSequence:
            let dir = options.outputDirectory.appendingPathComponent("session-\(stamp)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            jpegSequenceDir = dir
            jpegIndex = 0
            outputURL = dir
            isRecording = true
            append(jpeg) // include the frame that started the session

        case .quickTimeMOV:
            let url = options.outputDirectory.appendingPathComponent("recording-\(stamp).mov")
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            let settings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(size.width),
                AVVideoHeightKey: Int(size.height)
            ]
            let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
            input.expectsMediaDataInRealTime = true
            let attrs: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(size.width),
                kCVPixelBufferHeightKey as String: Int(size.height)
            ]
            let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                                                               sourcePixelBufferAttributes: attrs)
            guard writer.canAdd(input) else {
                throw NSError(domain: "FrameRecorder", code: 11,
                              userInfo: [NSLocalizedDescriptionKey: "Cannot add video input"])
            }
            writer.add(input)
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            self.writer = writer
            self.input = input
            self.adaptor = adaptor
            outputURL = url
            isRecording = true
            append(jpeg)
        }
        log(.info, "Recording started -> \(outputURL?.lastPathComponent ?? "?")")
    }

    /// Add a frame to the current recording. No-op if not recording.
    func append(_ jpeg: Data) {
        guard isRecording, let startTime else { return }

        if let dir = jpegSequenceDir {
            let name = String(format: "frame-%06d.jpg", jpegIndex)
            jpegIndex += 1
            try? jpeg.write(to: dir.appendingPathComponent(name))
            return
        }

        guard let adaptor, let input, let frameSize,
              input.isReadyForMoreMediaData,
              let image = Self.cgImage(fromJPEG: jpeg),
              let pixelBuffer = Self.pixelBuffer(from: image, size: frameSize) else { return }

        let elapsed = Date().timeIntervalSince(startTime)
        let pts = CMTime(value: CMTimeValue(elapsed * Double(timescale)), timescale: timescale)
        adaptor.append(pixelBuffer, withPresentationTime: pts)
    }

    /// Finish the recording and flush to disk. Returns the output URL.
    func stop(completion: @escaping (URL?) -> Void) {
        guard isRecording else { completion(nil); return }
        isRecording = false

        if jpegSequenceDir != nil {
            let url = outputURL
            reset()
            log(.info, "Recording stopped (JPEG sequence)")
            completion(url)
            return
        }

        input?.markAsFinished()
        let url = outputURL
        writer?.finishWriting { [weak self] in
            log(.info, "Recording finalized -> \(url?.lastPathComponent ?? "?")")
            self?.reset()
            completion(url)
        }
    }

    private func reset() {
        writer = nil
        input = nil
        adaptor = nil
        startTime = nil
        frameSize = nil
        jpegSequenceDir = nil
        jpegIndex = 0
    }

    // MARK: - Image helpers

    static func cgImage(fromJPEG data: Data) -> CGImage? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    private static func pixelBuffer(from image: CGImage, size: CGSize) -> CVPixelBuffer? {
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                         Int(size.width), Int(size.height),
                                         kCVPixelFormatType_32BGRA,
                                         attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: base,
                                  width: Int(size.width), height: Int(size.height),
                                  bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue |
                                              CGBitmapInfo.byteOrder32Little.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(origin: .zero, size: size))
        return buffer
    }

    private static func timestampString() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd-HHmmss"
        return fmt.string(from: Date())
    }
}
