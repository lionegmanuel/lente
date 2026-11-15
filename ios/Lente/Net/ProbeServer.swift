import Foundation
import Network

/// Known byte pattern sent by the Phase 0 probe: "LENTE-F0" followed by a
/// big endian u32 counter. The PC side checks it with tools/usbmux_probe.py.
enum ProbePayload {
    static let magic: [UInt8] = Array("LENTE-F0".utf8)
    static let size = 12

    static func chunk(index: UInt32) -> Data {
        var data = Data(magic)
        data.append(UInt8(truncatingIfNeeded: index >> 24))
        data.append(UInt8(truncatingIfNeeded: index >> 16))
        data.append(UInt8(truncatingIfNeeded: index >> 8))
        data.append(UInt8(truncatingIfNeeded: index))
        return data
    }
}

/// Phase 0 risk test: listens on 127.0.0.1:27183 (loopback only, never on
/// Wi-Fi) and streams the probe payload every 50 ms to a single client.
final class ProbeServer: ObservableObject {
    enum State: Equatable {
        case stopped
        case waiting
        case connected
        case failed(String)
    }

    static let port: NWEndpoint.Port = 27183

    @Published private(set) var state: State = .stopped
    @Published private(set) var bytesSent = 0

    private let queue = DispatchQueue(label: "lente.probe", qos: .userInteractive)
    private var listener: NWListener?
    private var connection: NWConnection?
    private var timer: DispatchSourceTimer?
    private var index: UInt32 = 0
    private var sent = 0

    func start() {
        queue.async { self.startOnQueue() }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func startOnQueue() {
        guard listener == nil else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: Self.port)
        params.allowLocalEndpointReuse = true
        do {
            let listener = try NWListener(using: params)
            listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
            listener.stateUpdateHandler = { [weak self] state in self?.listenerChanged(state) }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            publish(.failed("listener: \(error)"))
        }
    }

    private func stopOnQueue() {
        dropConnection()
        listener?.cancel()
        listener = nil
        publish(.stopped)
    }

    private func listenerChanged(_ state: NWListener.State) {
        switch state {
        case .ready:
            if connection == nil { publish(.waiting) }
        case .failed(let error):
            listener?.cancel()
            listener = nil
            publish(.failed("listener: \(error)"))
        default:
            break
        }
    }

    private func accept(_ conn: NWConnection) {
        guard connection == nil else {
            // One session at a time.
            conn.cancel()
            return
        }
        connection = conn
        index = 0
        sent = 0
        conn.stateUpdateHandler = { [weak self, weak conn] state in
            guard let self, let conn, conn === self.connection else { return }
            switch state {
            case .ready:
                self.publish(.connected)
                self.startSending()
            case .failed, .cancelled:
                self.dropConnection()
                if self.listener != nil { self.publish(.waiting) }
            default:
                break
            }
        }
        conn.start(queue: queue)
    }

    private func startSending() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(50))
        timer.setEventHandler { [weak self] in self?.sendNext() }
        timer.resume()
        self.timer = timer
    }

    private func sendNext() {
        guard let conn = connection else { return }
        let data = ProbePayload.chunk(index: index)
        index &+= 1
        conn.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.dropConnection()
                if self.listener != nil { self.publish(.waiting) }
                return
            }
            self.sent += data.count
            let total = self.sent
            DispatchQueue.main.async { self.bytesSent = total }
        })
    }

    private func dropConnection() {
        timer?.cancel()
        timer = nil
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
    }

    private func publish(_ state: State) {
        DispatchQueue.main.async { self.state = state }
    }
}
