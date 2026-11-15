import CoreMedia
import Foundation
import os
import VideoToolbox

/// One encoded frame, already in Annex B.
struct EncodedFrame {
    let data: Data
    let ptsMicros: UInt64
    let keyFrame: Bool
    /// Parameter sets (Annex B) when they are new or changed; sent first as
    /// a scrcpy config packet.
    let config: Data?
}

/// Hardware encoder tuned for latency: real time, no B frames, low latency
/// rate control. See docs/plan/APP_IOS.md section 6.
final class Encoder {
    enum EncoderError: Error, CustomStringConvertible {
        case create(OSStatus)

        var description: String {
            switch self {
            case .create(let status): return "encoder creation failed (\(status))"
            }
        }
    }

    let codec: VideoCodec
    private let log = Logger(subsystem: "digital.velinex.lente", category: "encoder")
    private var session: VTCompressionSession?
    private let output: (EncodedFrame) -> Void
    private let lock = NSLock()
    private var forceKeyFrame = true
    private var lastConfig: Data?
    private var firstPts: CMTime?
    private(set) var lowLatency = false

    init(codec: VideoCodec, width: Int, height: Int, fps: Int, bitRate: Int,
         keyFrameInterval: Double, output: @escaping (EncodedFrame) -> Void) throws {
        self.codec = codec
        self.output = output

        let codecType = codec == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
        let lowLatencySpec = [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true] as CFDictionary
        var created: VTCompressionSession?
        var status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height), codecType: codecType,
            encoderSpecification: lowLatencySpec, imageBufferAttributes: nil,
            compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
            compressionSessionOut: &created)
        if status == noErr {
            lowLatency = true
        } else {
            log.info("low latency rate control unavailable for \(codec.rawValue, privacy: .public) (\(status)), using default")
            status = VTCompressionSessionCreate(
                allocator: nil, width: Int32(width), height: Int32(height), codecType: codecType,
                encoderSpecification: nil, imageBufferAttributes: nil,
                compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                compressionSessionOut: &created)
        }
        guard status == noErr, let created else { throw EncoderError.create(status) }
        session = created

        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
        set(kVTCompressionPropertyKey_ProfileLevel,
            codec == .h264 ? kVTProfileLevel_H264_High_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: bitRate))
        let bytesPerSecond = Double(bitRate) / 8 * 1.5
        set(kVTCompressionPropertyKey_DataRateLimits, [NSNumber(value: bytesPerSecond), NSNumber(value: 1.0)] as CFArray)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: fps))
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: keyFrameInterval))
        if codec == .h264 {
            set(kVTCompressionPropertyKey_H264EntropyMode, kVTH264EntropyMode_CABAC)
        }
        set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_ITU_R_709_2)
        set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
        set(kVTCompressionPropertyKey_MaximizePowerEfficiency, kCFBooleanFalse)
        VTCompressionSessionPrepareToEncodeFrames(created)
    }

    deinit {
        invalidate()
    }

    func invalidate() {
        lock.lock()
        let current = session
        session = nil
        lock.unlock()
        if let current {
            VTCompressionSessionInvalidate(current)
        }
    }

    func requestKeyFrame() {
        lock.lock()
        forceKeyFrame = true
        lock.unlock()
    }

    /// Called on the camera queue for every captured frame.
    func encode(_ sample: CMSampleBuffer) {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { return }
        lock.lock()
        let current = session
        let force = forceKeyFrame
        forceKeyFrame = false
        lock.unlock()
        guard let current else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        let properties = force ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let status = VTCompressionSessionEncodeFrame(
            current, imageBuffer: image, presentationTimeStamp: pts, duration: .invalid,
            frameProperties: properties, infoFlagsOut: nil
        ) { [weak self] status, _, encoded in
            self?.handle(status: status, sample: encoded)
        }
        if status != noErr {
            log.error("encode failed (\(status))")
            if force { requestKeyFrame() }
        }
    }

    private func handle(status: OSStatus, sample: CMSampleBuffer?) {
        guard status == noErr, let sample, CMSampleBufferDataIsReady(sample),
              let block = CMSampleBufferGetDataBuffer(sample) else {
            log.error("encoder output dropped (\(status))")
            return
        }

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let notSync = (attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool) ?? false
        let keyFrame = !notSync

        var lengthSize = 4
        var config: Data?
        if let format = CMSampleBufferGetFormatDescription(sample),
           let sets = AnnexB.parameterSets(format, codec: codec) {
            lengthSize = sets.lengthSize
            let joined = AnnexB.join(sets.sets)
            if keyFrame, joined != lastConfig {
                config = joined
                lastConfig = joined
            }
        }

        let length = CMBlockBufferGetDataLength(block)
        var avcc = [UInt8](repeating: 0, count: length)
        guard CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &avcc) == noErr,
              let annexB = AnnexB.fromAVCC(avcc, lengthSize: lengthSize) else {
            log.error("could not convert encoded frame")
            return
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sample)
        if firstPts == nil { firstPts = pts }
        var micros: UInt64 = 0
        if let firstPts, pts.isValid {
            let seconds = CMTimeGetSeconds(CMTimeSubtract(pts, firstPts))
            if seconds > 0 { micros = UInt64(seconds * 1_000_000) }
        }

        output(EncodedFrame(data: annexB, ptsMicros: micros, keyFrame: keyFrame, config: config))
    }

    private func set(_ key: CFString, _ value: CFTypeRef) {
        guard let session else { return }
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            log.info("property \(key as String, privacy: .public) not applied (\(status))")
        }
    }
}
