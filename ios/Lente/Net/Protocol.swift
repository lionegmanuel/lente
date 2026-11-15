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
    var torch = false
    var zoom: Double?
    /// Clockwise rotation of the output, in degrees: 0, 90, 180 or 270
    var rotation = 0
    var lockExposure = false
    var lockFocus = false
    var lockWhiteBalance = false

    /// Output size after the rotation
    var outputSize: Size {
        rotation == 90 || rotation == 270 ? Size(width: size.height, height: size.width) : size
    }

    /// Accepted by the parser and ignored (the iPhone has fixed lenses and sizes).
    static let reservedKeys: Set<String> = [
        "max_size", "max_fps", "camera_high_speed", "camera_ar", "list_cameras",
        "list_camera_sizes",
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
            case "camera_zoom":
                guard let v = Double(value), v > 0, v <= 100 else { return .failure(bad) }
                p.zoom = v
            case "capture_orientation":
                // scrcpy may prefix "@" (orientation lock): the iPhone app keeps it fixed anyway
                let degrees = value.hasPrefix("@") ? String(value.dropFirst()) : value
                guard let v = Int(degrees), [0, 90, 180, 270].contains(v) else { return .failure(bad) }
                p.rotation = v
            case "camera_torch", "lente_lock_exposure", "lente_lock_focus", "lente_lock_wb":
                guard let b = Bool(value) else { return .failure(bad) }
                switch key {
                case "camera_torch": p.torch = b
                case "lente_lock_exposure": p.lockExposure = b
                case "lente_lock_focus": p.lockFocus = b
                default: p.lockWhiteBalance = b
                }
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

/// Control messages from the PC (scrcpy 4.1 types plus Lente 0x60 to 0x6F).
/// The app must know the length of every scrcpy message to skip the ones it
/// does not use (keyboard, mouse, clipboard...).
enum ControlMessage: Equatable {
    case displayPower(on: Bool)
    case resetVideo
    case torch(on: Bool)
    case zoomIn
    case zoomOut
    case setLens(UInt8)
    case lock(what: UInt8, on: Bool)
    case ignored(type: UInt8)

    static let lockExposure: UInt8 = 1
    static let lockFocus: UInt8 = 2
    static let lockWhiteBalance: UInt8 = 4
}

enum ControlParser {
    enum ParseError: Error, Equatable {
        case unknownType(UInt8)
    }

    /// Next message starting at offset, with its length. nil if incomplete.
    static func next(_ b: [UInt8], at i: Int) throws -> (ControlMessage, Int)? {
        let n = b.count - i
        guard n >= 1 else { return nil }
        let type = b[i]

        func need(_ len: Int) -> Bool { n >= len }
        func u16(_ o: Int) -> Int { Int(readBE(b, at: i + o, as: UInt16.self)) }
        func u32(_ o: Int) -> Int { Int(readBE(b, at: i + o, as: UInt32.self)) }

        let len: Int
        switch type {
        case 0: len = 14 // inject keycode
        case 1: // inject text: u32 length + text
            guard need(5) else { return nil }
            len = 5 + u32(1)
        case 2: len = 32 // touch
        case 3: len = 21 // scroll
        case 4, 8, 10, 18: len = 2 // back or screen on, get clipboard, display power, torch
        case 5, 6, 7, 11, 15, 17, 19, 20: len = 1 // no payload
        case 9: // set clipboard: sequence u64, paste u8, u32 length + text
            guard need(14) else { return nil }
            len = 14 + u32(10)
        case 12: // uhid create: id, vendor, product, u8 name length + name, u16 size + descriptor
            guard need(8) else { return nil }
            let nameLen = Int(b[i + 7])
            guard need(8 + nameLen + 2) else { return nil }
            len = 8 + nameLen + 2 + u16(8 + nameLen)
        case 13: // uhid input: id u16, size u16, data
            guard need(5) else { return nil }
            len = 5 + u16(3)
        case 14: len = 3 // uhid destroy
        case 16: // start app: u8 length + name
            guard need(2) else { return nil }
            len = 2 + Int(b[i + 1])
        case 21: len = 5 // resize display
        case 22: // scan file: u32 length + path
            guard need(5) else { return nil }
            len = 5 + u32(1)
        case 0x60: len = 2 // Lente: set lens
        case 0x61: len = 3 // Lente: lock
        default:
            throw ParseError.unknownType(type)
        }
        guard need(len) else { return nil }

        let message: ControlMessage
        switch type {
        case 10: message = .displayPower(on: b[i + 1] != 0)
        case 17: message = .resetVideo
        case 18: message = .torch(on: b[i + 1] != 0)
        case 19: message = .zoomIn
        case 20: message = .zoomOut
        case 0x60: message = .setLens(b[i + 1])
        case 0x61: message = .lock(what: b[i + 1], on: b[i + 2] != 0)
        default: message = .ignored(type: type)
        }
        return (message, len)
    }
}

/// Messages from the iPhone to the PC (Lente range, 0x60 to 0x6F).
enum DeviceMessage {
    struct Telemetry: Equatable {
        var thermal: UInt8 // 0 nominal, 1 fair, 2 serious, 3 critical
        var battery: UInt8 // percent, 255 unknown
        var batteryState: UInt8 // 0 unknown, 1 unplugged, 2 charging, 3 full
        var frames: UInt32
        var dropped: UInt32
        var bitRate: UInt32
    }

    enum EventCode: UInt8 {
        case interrupted = 1
        case resumed = 2
        case lensChanged = 3
    }

    static func telemetry(_ t: Telemetry) -> Data {
        var data = Data([0x60, t.thermal, t.battery, t.batteryState])
        data.appendBE(t.frames)
        data.appendBE(t.dropped)
        data.appendBE(t.bitRate)
        return data
    }

    static func event(_ code: EventCode, _ text: String) -> Data {
        var bytes = Data(text.utf8)
        if bytes.count > Int(UInt16.max) { bytes = bytes.prefix(Int(UInt16.max)) }
        var data = Data([0x61, code.rawValue])
        data.appendBE(UInt16(bytes.count))
        data.append(bytes)
        return data
    }
}
