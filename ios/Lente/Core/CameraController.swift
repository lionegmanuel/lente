import AVFoundation
import Foundation
import os

/// Pure format selection, testable without a camera.
enum FormatSelection {
    struct Candidate: Equatable {
        let width: Int
        let height: Int
        let fpsRanges: [ClosedRange<Double>]
        let is420v: Bool
        /// Sensor size proxy: the largest still image the format can take.
        let sensorPixels: Int
    }

    /// Index of the best candidate: exact size, 8 bit 4:2:0 video range,
    /// a frame rate range that includes fps, and the smallest sensor
    /// readout among those (less power). nil if none fits.
    static func choose(_ candidates: [Candidate], width: Int, height: Int, fps: Int) -> Int? {
        var best: Int?
        for (index, c) in candidates.enumerated() {
            guard c.is420v, c.width == width, c.height == height,
                  c.fpsRanges.contains(where: { $0.contains(Double(fps)) }) else { continue }
            if let b = best, candidates[b].sensorPixels <= c.sensorPixels { continue }
            best = index
        }
        return best
    }

    /// Human readable list of what a device supports, for error messages.
    static func describe(_ candidates: [Candidate]) -> String {
        var seen = Set<String>()
        var out: [String] = []
        for c in candidates where c.is420v {
            let maxFps = Int(c.fpsRanges.map(\.upperBound).max() ?? 0)
            let text = "\(c.width)x\(c.height)@\(maxFps)"
            if seen.insert(text).inserted { out.append(text) }
        }
        return out.joined(separator: ", ")
    }
}

/// Capture from one physical camera (never a virtual multi-lens device, so
/// the lens never switches by itself). See docs/plan/APP_IOS.md section 5.
final class CameraController: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    enum CameraError: Error, CustomStringConvertible {
        case noDevice(String)
        case noFormat(String)
        case configuration(String)

        var description: String {
            switch self {
            case .noDevice(let detail): return "camera not available: \(detail)"
            case .noFormat(let detail): return "format not supported, valid: \(detail)"
            case .configuration(let detail): return "camera configuration failed: \(detail)"
            }
        }
    }

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "lente.camera", qos: .userInteractive)
    private let log = Logger(subsystem: "digital.velinex.lente", category: "camera")
    private let frameLock = NSLock()
    private var frameHandler: ((CMSampleBuffer) -> Void)?

    func setFrameHandler(_ handler: ((CMSampleBuffer) -> Void)?) {
        frameLock.lock()
        frameHandler = handler
        frameLock.unlock()
    }

    static func device(for params: SessionParams) -> AVCaptureDevice? {
        let id = params.cameraId ?? (params.facing == .front ? 3 : 1)
        switch id {
        case 0: return AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
        case 2: return AVCaptureDevice.default(.builtInTelephotoCamera, for: .video, position: .back)
        case 3: return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        default: return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        }
    }

    static func candidates(_ device: AVCaptureDevice) -> [FormatSelection.Candidate] {
        device.formats.map { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let subtype = CMFormatDescriptionGetMediaSubType(format.formatDescription)
            let still = format.highResolutionStillImageDimensions
            return FormatSelection.Candidate(
                width: Int(dims.width),
                height: Int(dims.height),
                fpsRanges: format.videoSupportedFrameRateRanges.map { $0.minFrameRate...$0.maxFrameRate },
                is420v: subtype == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                sensorPixels: Int(still.width) * Int(still.height)
            )
        }
    }

    /// Configures the session for the requested camera, size and frame rate.
    /// Blocking: call it off the main thread. Returns the output size.
    func configure(_ params: SessionParams) throws -> (width: Int, height: Int) {
        guard let device = Self.device(for: params) else {
            throw CameraError.noDevice("camera_id \(params.cameraId ?? -1)")
        }
        let candidates = Self.candidates(device)
        guard let index = FormatSelection.choose(
            candidates, width: params.size.width, height: params.size.height, fps: params.fps) else {
            throw CameraError.noFormat(FormatSelection.describe(candidates))
        }
        let format = device.formats[index]

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .inputPriority
        session.automaticallyConfiguresCaptureDeviceWideColor = false
        for input in session.inputs { session.removeInput(input) }
        for output in session.outputs { session.removeOutput(output) }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraError.configuration("input: \(error.localizedDescription)")
        }
        guard session.canAddInput(input) else { throw CameraError.configuration("cannot add input") }
        session.addInput(input)

        do {
            try device.lockForConfiguration()
        } catch {
            throw CameraError.configuration("lock: \(error.localizedDescription)")
        }
        device.activeFormat = format
        let duration = CMTime(value: 1, timescale: CMTimeScale(params.fps))
        device.activeVideoMinFrameDuration = duration
        device.activeVideoMaxFrameDuration = duration
        if format.isVideoHDRSupported {
            device.automaticallyAdjustsVideoHDREnabled = false
            device.isVideoHDREnabled = false
        }
        if format.supportedColorSpaces.contains(.sRGB) {
            device.activeColorSpace = .sRGB
        }
        device.unlockForConfiguration()

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.configuration("cannot add output") }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoStabilizationSupported {
                connection.preferredVideoStabilizationMode = params.stabilization ? .standard : .off
            }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = false
            }
        }

        log.info("camera \(device.localizedName, privacy: .public) \(params.size.width)x\(params.size.height)@\(params.fps)")
        return (params.size.width, params.size.height)
    }

    /// Blocking: call it off the main thread.
    func start() {
        if !session.isRunning { session.startRunning() }
    }

    /// Blocking: call it off the main thread.
    func stop() {
        if session.isRunning { session.stopRunning() }
        setFrameHandler(nil)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameLock.lock()
        let handler = frameHandler
        frameLock.unlock()
        handler?(sampleBuffer)
    }
}
