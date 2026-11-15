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
    /// Current camera and parameters (camera queue of the server)
    private(set) var device: AVCaptureDevice?
    private(set) var params: SessionParams?

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
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
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
            Self.applyRotation(params.rotation, to: connection)
        }

        self.device = device
        self.params = params
        applyInitialControls(params)
        let out = params.outputSize
        log.info("camera \(device.localizedName, privacy: .public) \(out.width)x\(out.height)@\(params.fps) rot \(params.rotation)")
        return (out.width, out.height)
    }

    /// The data output delivers landscape buffers (sensor orientation, 0 degrees).
    /// Rotating here makes every output (window, V4L2, recording) come out straight.
    private static func applyRotation(_ degrees: Int, to connection: AVCaptureConnection) {
        guard degrees != 0 else { return }
        if #available(iOS 17.0, *) {
            let angle = CGFloat(degrees)
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
        } else if connection.isVideoOrientationSupported {
            switch degrees {
            case 90: connection.videoOrientation = .portrait
            case 180: connection.videoOrientation = .landscapeLeft
            case 270: connection.videoOrientation = .portraitUpsideDown
            default: break
            }
        }
    }

    private func applyInitialControls(_ params: SessionParams) {
        if params.torch { setTorch(true) }
        if let zoom = params.zoom { setZoom(zoom) }
        if params.lockExposure { setLock(ControlMessage.lockExposure, on: true) }
        if params.lockFocus { setLock(ControlMessage.lockFocus, on: true) }
        if params.lockWhiteBalance { setLock(ControlMessage.lockWhiteBalance, on: true) }
    }

    // MARK: Controls (call them on the camera queue of the server)

    private func withLock(_ body: (AVCaptureDevice) -> Void) {
        guard let device else { return }
        do {
            try device.lockForConfiguration()
            body(device)
            device.unlockForConfiguration()
        } catch {
            log.error("lock failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setTorch(_ on: Bool) {
        withLock { d in
            guard d.hasTorch else { return }
            if on, d.isTorchModeSupported(.on) {
                try? d.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else if d.isTorchModeSupported(.off) {
                d.torchMode = .off
            }
        }
    }

    /// Zoom factor clamped to what the lens allows (digital zoom up to 10x)
    func setZoom(_ factor: Double) {
        withLock { d in
            let maxZoom = min(d.maxAvailableVideoZoomFactor, 10)
            let value = max(d.minAvailableVideoZoomFactor, min(CGFloat(factor), maxZoom))
            d.ramp(toVideoZoomFactor: value, withRate: 8)
        }
    }

    func zoom(in zoomIn: Bool) {
        guard let device else { return }
        setZoom(Double(device.videoZoomFactor) * (zoomIn ? 1.1 : 1 / 1.1))
    }

    func setLock(_ what: UInt8, on: Bool) {
        withLock { d in
            if what & ControlMessage.lockExposure != 0 {
                let mode: AVCaptureDevice.ExposureMode = on ? .locked : .continuousAutoExposure
                if d.isExposureModeSupported(mode) { d.exposureMode = mode }
            }
            if what & ControlMessage.lockFocus != 0 {
                let mode: AVCaptureDevice.FocusMode = on ? .locked : .continuousAutoFocus
                if d.isFocusModeSupported(mode) { d.focusMode = mode }
            }
            if what & ControlMessage.lockWhiteBalance != 0 {
                let mode: AVCaptureDevice.WhiteBalanceMode = on ? .locked : .continuousAutoWhiteBalance
                if d.isWhiteBalanceModeSupported(mode) { d.whiteBalanceMode = mode }
            }
        }
    }

    static let lensNames = ["0.5x", "1x", "5x", "frontal"]

    /// Switch to another lens keeping the session (same size and frame rate).
    /// Returns the output size, or throws and keeps the current lens.
    func switchLens(_ id: Int) throws -> (width: Int, height: Int) {
        guard var params, (0...3).contains(id) else {
            throw CameraError.noDevice("lens \(id)")
        }
        params.cameraId = id
        guard let next = Self.device(for: params) else {
            throw CameraError.noDevice("lens \(id) (\(Self.lensNames[id]))")
        }
        let candidates = Self.candidates(next)
        guard FormatSelection.choose(candidates, width: params.size.width, height: params.size.height,
                                     fps: params.fps) != nil else {
            throw CameraError.noFormat(FormatSelection.describe(candidates))
        }
        // Initial controls of the session (torch, zoom, locks) do not carry over
        params.torch = false
        params.zoom = nil
        return try configure(params)
    }

    /// Blocking: call it off the main thread.
    func start() {
        if !session.isRunning { session.startRunning() }
    }

    /// Blocking: call it off the main thread. After a runtime error.
    func restart() {
        if session.isRunning { session.stopRunning() }
        session.startRunning()
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
