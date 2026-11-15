import Foundation

// Wire format shared with the PC client. Everything is big endian, like the
// scrcpy protocol. See docs/plan/ARQUITECTURA_Y_PROTOCOLO.md sections 5 and 6.

extension Data {
    mutating func appendBE<T: FixedWidthInteger>(_ value: T) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }
}

func readBE<T: FixedWidthInteger>(_ bytes: [UInt8], at offset: Int, as _: T.Type) -> T {
    var value: T = 0
    for i in 0..<MemoryLayout<T>.size {
        value = (value << 8) | T(bytes[offset + i])
    }
    return value
}

enum VideoCodec: String, CaseIterable {
    case h264
    case h265

    /// scrcpy codec ids: the codec name in ASCII.
    var scrcpyId: UInt32 {
        switch self {
        case .h264: return 0x6832_3634
        case .h265: return 0x6832_3635
        }
    }
}

/// Session opening sent by the client on the video connection.
enum LNTE {
    static let magic: [UInt8] = Array("LNTE".utf8)
    static let controlMagic: [UInt8] = Array("LNTC".utf8)
    static let version: UInt16 = 1
    static let headerSize = 12
    static let controlSize = 12
    static let maxParamsLength: UInt32 = 16 * 1024

    enum Status: UInt8 {
        case ok = 0
        case incompatibleVersion = 1
        case invalidParameter = 2
        case cameraUnavailable = 3
        case busy = 4
        case permissionDenied = 5
    }

    struct Header: Equatable {
        let version: UInt16
        let flags: UInt16
        let length: UInt32
    }

    enum HeaderError: Error, Equatable {
        case badMagic
        case tooLong(UInt32)
    }

    static func parseHeader(_ data: Data) throws -> Header {
        let b = [UInt8](data)
        precondition(b.count == headerSize)
        guard Array(b[0..<4]) == magic else { throw HeaderError.badMagic }
        let header = Header(
            version: readBE(b, at: 4, as: UInt16.self),
            flags: readBE(b, at: 6, as: UInt16.self),
            length: readBE(b, at: 8, as: UInt32.self)
        )
        guard header.length <= maxParamsLength else { throw HeaderError.tooLong(header.length) }
        return header
    }

    static func request(params: String, version: UInt16 = version) -> Data {
        let text = Data(params.utf8)
        var data = Data(magic)
        data.appendBE(version)
        data.appendBE(UInt16(0))
        data.appendBE(UInt32(text.count))
        data.append(text)
        return data
    }

    static func response(status: Status, session: UInt64, message: String) -> Data {
        var text = Data(message.utf8)
        if text.count > Int(UInt16.max) { text = text.prefix(Int(UInt16.max)) }
        var data = Data(magic)
        data.appendBE(version)
        data.append(status.rawValue)
        data.appendBE(session)
        data.appendBE(UInt16(text.count))
        data.append(text)
        return data
    }

    /// Returns the session id of a control opening, or nil if it is not one.
    static func parseControl(_ data: Data) -> UInt64? {
        let b = [UInt8](data)
        guard b.count == controlSize, Array(b[0..<4]) == controlMagic else { return nil }
        return readBE(b, at: 4, as: UInt64.self)
    }
}

/// Session parameters. Keys are the scrcpy server ones (Options.java, tag
/// v4.1) plus the Lente ones with the `lente_` prefix.
struct SessionParams: Equatable {
    struct Size: Equatable {
        let width: Int
        let height: Int
    }

    enum Facing: String {
        case back
        case front
    }

    var codec: VideoCodec = .h264
    var bitRate = 16_000_000
    var cameraId: Int?
    var facing: Facing = .back
    var size = Size(width: 1920, height: 1080)
    var fps = 60
    var sendDeviceMeta = true
    var sendStreamMeta = true
    var sendFrameMeta = true
    var rawStream = false
    var control = true
    var stabilization = false
    var keyFrameInterval = 2.0

    /// Accepted by the parser, applied in later phases.
    static let reservedKeys: Set<String> = [
        "max_size", "max_fps", "camera_high_speed", "camera_ar", "camera_torch",
        "camera_zoom", "capture_orientation", "list_cameras", "list_camera_sizes",
        "lente_lock_exposure", "lente_lock_focus", "lente_lock_wb",
    ]

    enum ParseError: Error, Equatable {
        case malformedLine(String)
        case unknownKey(String)
        case invalidValue(key: String, value: String)

        var message: String {
            switch self {
            case .malformedLine(let line): return "malformed line: \(line)"
            case .unknownKey(let key): return "unknown parameter: \(key)"
            case .invalidValue(let key, let value): return "invalid value for \(key): \(value)"
            }
        }
    }

    static func parse(_ text: String) -> Result<SessionParams, ParseError> {
        var p = SessionParams()
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            guard let eq = line.firstIndex(of: "=") else { return .failure(.malformedLine(line)) }
            let key = String(line[..<eq])
            let value = String(line[line.index(after: eq)...])
            let bad = ParseError.invalidValue(key: key, value: value)
            switch key {
            case "video_codec":
                guard let c = VideoCodec(rawValue: value) else { return .failure(bad) }
                p.codec = c
            case "video_bit_rate":
                guard let v = Int(value), (100_000...200_000_000).contains(v) else { return .failure(bad) }
                p.bitRate = v
            case "camera_id":
                guard let v = Int(value), (0...3).contains(v) else { return .failure(bad) }
                p.cameraId = v
            case "camera_facing":
                guard let f = Facing(rawValue: value) else { return .failure(bad) }
                p.facing = f
            case "camera_size":
                let parts = value.split(separator: "x")
                guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else {
                    return .failure(bad)
                }
                p.size = Size(width: w, height: h)
            case "camera_fps":
                guard let v = Int(value), (1...240).contains(v) else { return .failure(bad) }
                p.fps = v
            case "send_device_meta", "send_stream_meta", "send_frame_meta", "raw_stream", "control":
                guard let b = Bool(value) else { return .failure(bad) }
                switch key {
                case "send_device_meta": p.sendDeviceMeta = b
                case "send_stream_meta": p.sendStreamMeta = b
                case "send_frame_meta": p.sendFrameMeta = b
                case "raw_stream": p.rawStream = b
                case "control": p.control = b
                default: break
                }
            case "lente_stabilization":
                switch value {
                case "off": p.stabilization = false
                case "standard": p.stabilization = true
                default: return .failure(bad)
                }
            case "lente_keyframe_interval":
                guard let v = Double(value), v > 0, v <= 60 else { return .failure(bad) }
                p.keyFrameInterval = v
            default:
                guard reservedKeys.contains(key) else { return .failure(.unknownKey(key)) }
            }
        }
        if p.rawStream {
            p.sendDeviceMeta = false
            p.sendStreamMeta = false
            p.sendFrameMeta = false
        }
        return .success(p)
    }
}

/// scrcpy 4.1 video stream framing (app/src/demuxer.c).
enum ScrcpyPacket {
    static let deviceNameLength = 64
    static let flagSession: UInt64 = 1 << 63
    static let flagConfig: UInt64 = 1 << 62
    static let flagKeyFrame: UInt64 = 1 << 61
    static let ptsMask: UInt64 = flagKeyFrame - 1

    static func deviceMeta(name: String) -> Data {
        var bytes = [UInt8](name.utf8.prefix(deviceNameLength - 1))
        bytes += [UInt8](repeating: 0, count: deviceNameLength - bytes.count)
        return Data(bytes)
    }

    static func streamMeta(codec: VideoCodec) -> Data {
        var data = Data()
        data.appendBE(codec.scrcpyId)
        return data
    }

    static func session(width: Int, height: Int) -> Data {
        var data = Data([0x80, 0, 0, 0])
        data.appendBE(UInt32(width))
        data.appendBE(UInt32(height))
        return data
    }

    static func mediaHeader(ptsMicros: UInt64, config: Bool, keyFrame: Bool, size: Int) -> Data {
        var flags: UInt64 = config ? flagConfig : (ptsMicros & ptsMask)
        if keyFrame { flags |= flagKeyFrame }
        var data = Data()
        data.appendBE(flags)
        data.appendBE(UInt32(size))
        return data
    }
}
