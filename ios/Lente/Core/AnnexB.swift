import CoreMedia
import Foundation

/// VideoToolbox gives AVCC (each NAL unit prefixed by its length); scrcpy
/// and FFmpeg expect Annex B (each NAL unit prefixed by 00 00 00 01).
enum AnnexB {
    static let startCode: [UInt8] = [0, 0, 0, 1]

    /// Converts AVCC to Annex B. Returns nil if the input is malformed.
    static func fromAVCC(_ avcc: [UInt8], lengthSize: Int = 4) -> Data? {
        guard (1...4).contains(lengthSize) else { return nil }
        var out = Data(capacity: avcc.count + 32)
        var i = 0
        while i < avcc.count {
            guard i + lengthSize <= avcc.count else { return nil }
            var length = 0
            for k in 0..<lengthSize {
                length = (length << 8) | Int(avcc[i + k])
            }
            i += lengthSize
            guard length > 0, i + length <= avcc.count else { return nil }
            out.append(contentsOf: startCode)
            out.append(contentsOf: avcc[i..<(i + length)])
            i += length
        }
        return out
    }

    /// Joins raw NAL units (parameter sets) into one Annex B buffer.
    static func join(_ nalUnits: [Data]) -> Data {
        var out = Data()
        for unit in nalUnits {
            out.append(contentsOf: startCode)
            out.append(unit)
        }
        return out
    }

    /// Parameter sets stored in a format description, in order (VPS, SPS,
    /// PPS for HEVC; SPS, PPS for H.264), plus the AVCC length size.
    static func parameterSets(_ format: CMFormatDescription, codec: VideoCodec) -> (sets: [Data], lengthSize: Int)? {
        var count = 0
        var lengthSize: Int32 = 0
        guard get(format, codec, index: 0, pointer: nil, size: nil, count: &count, lengthSize: &lengthSize) == noErr,
              count > 0 else { return nil }
        var sets: [Data] = []
        for index in 0..<count {
            var pointer: UnsafePointer<UInt8>?
            var size = 0
            guard get(format, codec, index: index, pointer: &pointer, size: &size, count: nil, lengthSize: nil) == noErr,
                  let pointer else { return nil }
            sets.append(Data(bytes: pointer, count: size))
        }
        return (sets, Int(lengthSize))
    }

    private static func get(
        _ format: CMFormatDescription,
        _ codec: VideoCodec,
        index: Int,
        pointer: UnsafeMutablePointer<UnsafePointer<UInt8>?>?,
        size: UnsafeMutablePointer<Int>?,
        count: UnsafeMutablePointer<Int>?,
        lengthSize: UnsafeMutablePointer<Int32>?
    ) -> OSStatus {
        switch codec {
        case .h264:
            return CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, parameterSetIndex: index, parameterSetPointerOut: pointer,
                parameterSetSizeOut: size, parameterSetCountOut: count, nalUnitHeaderLengthOut: lengthSize)
        case .h265:
            return CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format, parameterSetIndex: index, parameterSetPointerOut: pointer,
                parameterSetSizeOut: size, parameterSetCountOut: count, nalUnitHeaderLengthOut: lengthSize)
        }
    }
}
