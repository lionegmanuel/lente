import AVFoundation
import Foundation
import Network
import os

/// Listens on 127.0.0.1:27183 (loopback only: never reachable over Wi-Fi),
/// opens one session per video connection (LNTE), and streams the camera in
/// the scrcpy 4.1 format. All network state lives on `net`.
final class StreamServer: ObservableObject {
    enum State: Equatable {
        case stopped
        case waiting
        case configuring
        case streaming(String)
        case failed(String)
    }

    static let port: NWEndpoint.Port = 27183

    @Published private(set) var state: State = .stopped
    @Published private(set) var framesSent = 0

    private let log = Logger(subsystem: "digital.velinex.lente", category: "net")
    private let net = DispatchQueue(label: "lente.net", qos: .userInteractive)
    private let cameraQueue = DispatchQueue(label: "lente.session", qos: .userInitiated)
    private let camera = CameraController()

    private var listener: NWListener?
    private var video: NWConnection?
    private var control: NWConnection?
    private var params: SessionParams?
    private var encoder: Encoder?
    private var sessionId: UInt64 = 0
    private var streaming = false
    private var pending = 0
    private var waitingKeyFrame = false
    private var sent = 0
    private var dropped = 0

    func start() {
        net.async { self.startListener() }
    }

    func stop() {
        net.async {
            self.teardown()
            self.listener?.cancel()
            self.listener = nil
            self.publish(.stopped)
        }
    }

    // MARK: Listener

    private func startListener() {
        guard listener == nil else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcp)
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: Self.port)
        parameters.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
            listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
            listener.start(queue: net)
            self.listener = listener
        } catch {
            publish(.failed("listener: \(error)"))
        }
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if video == nil { publish(.waiting) }
        case .failed(let error):
            publish(.failed("listener: \(error)"))
            listener?.cancel()
            listener = nil
        default:
            break
        }
    }

    // MARK: Opening

    private func accept(_ connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            guard let self, let connection else { return }
            switch state {
            case .failed, .cancelled:
                self.closed(connection)
            default:
                break
            }
        }
        connection.start(queue: net)
        receive(connection, LNTE.headerSize) { [weak self] data in
            guard let self else { return }
            guard let data else {
                connection.cancel()
                return
            }
            if let id = LNTE.parseControl(data) {
                self.openControl(connection, session: id)
                return
            }
            do {
                let header = try LNTE.parseHeader(data)
                self.openVideo(connection, header: header)
            } catch {
                connection.cancel()
            }
        }
    }

    private func openVideo(_ connection: NWConnection, header: LNTE.Header) {
        guard header.version == LNTE.version else {
            reply(connection, .incompatibleVersion, "this app speaks LNTE version \(LNTE.version)")
            return
        }
        guard video == nil else {
            reply(connection, .busy, "another session is active")
            return
        }
        receive(connection, Int(header.length)) { [weak self] data in
            guard let self else { return }
            guard let data else {
                connection.cancel()
                return
            }
            switch SessionParams.parse(String(decoding: data, as: UTF8.self)) {
            case .failure(let error):
                self.reply(connection, .invalidParameter, error.message)
            case .success(let params):
                self.begin(connection, params)
            }
        }
    }

    private func begin(_ connection: NWConnection, _ params: SessionParams) {
        guard video == nil else {
            reply(connection, .busy, "another session is active")
            return
        }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            reply(connection, .permissionDenied, "camera permission denied")
            return
        }
        video = connection
        self.params = params
        sessionId = UInt64.random(in: 1...UInt64.max)
        publish(.configuring)

        cameraQueue.async { [weak self] in
            guard let self else { return }
            do {
                let size = try self.camera.configure(params)
                let encoder = try Encoder(
                    codec: params.codec, width: size.width, height: size.height, fps: params.fps,
                    bitRate: params.bitRate, keyFrameInterval: params.keyFrameInterval
                ) { [weak self] frame in
                    self?.net.async { self?.send(frame) }
                }
                self.camera.setFrameHandler { [weak encoder] sample in encoder?.encode(sample) }
                self.net.async { self.started(connection, params, encoder, size) }
            } catch {
                self.camera.stop()
                self.net.async { self.failedStart(connection, params, error) }
            }
        }
    }

    private func started(_ connection: NWConnection, _ params: SessionParams, _ encoder: Encoder,
                         _ size: (width: Int, height: Int)) {
        guard video === connection else {
            encoder.invalidate()
            cameraQueue.async { self.camera.stop() }
            return
        }
        self.encoder = encoder

        var opening = Data()
        if !params.rawStream {
            opening.append(LNTE.response(status: .ok, session: sessionId, message: "ok"))
            if params.sendDeviceMeta { opening.append(ScrcpyPacket.deviceMeta(name: DeviceInfo.modelName)) }
            if params.sendStreamMeta { opening.append(ScrcpyPacket.streamMeta(codec: params.codec)) }
            if params.sendFrameMeta { opening.append(ScrcpyPacket.session(width: size.width, height: size.height)) }
        }
        if !opening.isEmpty {
            connection.send(content: opening, completion: .contentProcessed { _ in })
        }
        streaming = true
        sent = 0
        dropped = 0
        let codecName = params.codec == .h264 ? "H.264" : "HEVC"
        publish(.streaming("\(size.width)x\(size.height) · \(params.fps) cuadros · \(codecName) · \(params.bitRate / 1_000_000) Mbps"))
        log.info("session started \(size.width)x\(size.height)@\(params.fps) raw=\(params.rawStream)")
        cameraQueue.async { self.camera.start() }
    }

    private func failedStart(_ connection: NWConnection, _ params: SessionParams, _ error: Error) {
        log.error("session failed: \(String(describing: error), privacy: .public)")
        guard video === connection else { return }
        video = nil
        self.params = nil
        if params.rawStream {
            connection.cancel()
        } else {
            reply(connection, .cameraUnavailable, String(describing: error))
        }
        publish(.failed(String(describing: error)))
    }

    private func openControl(_ connection: NWConnection, session id: UInt64) {
        guard video != nil, id == sessionId, control == nil, params?.control == true else {
            connection.cancel()
            return
        }
        control = connection
        drain(connection)
    }

    /// Phase 1 accepts the control connection and ignores its messages.
    private func drain(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] _, _, isComplete, error in
            if isComplete || error != nil {
                connection.cancel()
                return
            }
            self?.drain(connection)
        }
    }

    // MARK: Streaming

    private func send(_ frame: EncodedFrame) {
        guard streaming, let connection = video, let params else { return }
        if !frame.keyFrame, waitingKeyFrame || pending > 2 {
            if !waitingKeyFrame {
                waitingKeyFrame = true
                encoder?.requestKeyFrame()
            }
            dropped += 1
            return
        }
        if frame.keyFrame { waitingKeyFrame = false }

        let framed = params.sendFrameMeta && !params.rawStream
        var out = Data()
        if let config = frame.config {
            if framed {
                out.append(ScrcpyPacket.mediaHeader(ptsMicros: 0, config: true, keyFrame: false, size: config.count))
            }
            out.append(config)
        }
        if framed {
            out.append(ScrcpyPacket.mediaHeader(ptsMicros: frame.ptsMicros, config: false,
                                                keyFrame: frame.keyFrame, size: frame.data.count))
        }
        out.append(frame.data)

        pending += 1
        connection.send(content: out, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            self.pending = max(0, self.pending - 1)
            if error != nil { connection.cancel() }
        })
        sent += 1
        if sent % 30 == 0 {
            let count = sent
            DispatchQueue.main.async { self.framesSent = count }
        }
    }

    // MARK: Closing

    private func closed(_ connection: NWConnection) {
        if connection === video {
            log.info("session ended: \(self.sent) frames sent, \(self.dropped) dropped")
            teardown()
        } else if connection === control {
            control = nil
        }
    }

    private func teardown() {
        let connection = video
        video = nil
        control?.cancel()
        control = nil
        params = nil
        streaming = false
        pending = 0
        waitingKeyFrame = false
        let encoder = self.encoder
        self.encoder = nil
        cameraQueue.async {
            self.camera.stop()
            encoder?.invalidate()
        }
        connection?.cancel()
        if listener != nil { publish(.waiting) }
    }

    // MARK: Helpers

    private func reply(_ connection: NWConnection, _ status: LNTE.Status, _ message: String) {
        let data = LNTE.response(status: status, session: 0, message: message)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private func receive(_ connection: NWConnection, _ count: Int, _ done: @escaping (Data?) -> Void) {
        guard count > 0 else {
            done(Data())
            return
        }
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, _ in
            if let data, data.count == count { done(data) } else { done(nil) }
        }
    }

    private func publish(_ state: State) {
        DispatchQueue.main.async {
            self.state = state
            if case .streaming = state {} else { self.framesSent = 0 }
        }
    }
}

enum DeviceInfo {
    /// Model name for the scrcpy device meta. Never the personal device name.
    static let modelName: String = {
        var info = utsname()
        uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        let names = [
            "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus",
            "iPhone16,1": "iPhone 15 Pro", "iPhone16,2": "iPhone 15 Pro Max",
            "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus",
            "iPhone17,1": "iPhone 16 Pro", "iPhone17,2": "iPhone 16 Pro Max",
        ]
        return names[machine] ?? "iPhone (\(machine))"
    }()
}
