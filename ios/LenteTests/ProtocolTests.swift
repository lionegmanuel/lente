import XCTest
@testable import Lente

final class ProtocolTests: XCTestCase {
    // MARK: LNTE opening

    func testRequestHeaderRoundTrip() throws {
        let request = LNTE.request(params: "video_codec=h264\ncamera_fps=60")
        let header = try LNTE.parseHeader(request.prefix(LNTE.headerSize))
        XCTAssertEqual(header, LNTE.Header(version: 1, flags: 0, length: 30))
        XCTAssertEqual(String(decoding: request.dropFirst(LNTE.headerSize), as: UTF8.self),
                       "video_codec=h264\ncamera_fps=60")
    }

    func testHeaderRejectsBadMagic() {
        let data = Data("XXXX".utf8) + Data(repeating: 0, count: 8)
        XCTAssertThrowsError(try LNTE.parseHeader(data)) { error in
            XCTAssertEqual(error as? LNTE.HeaderError, .badMagic)
        }
    }

    func testHeaderRejectsHugeParams() {
        var data = Data(LNTE.magic)
        data.appendBE(UInt16(1))
        data.appendBE(UInt16(0))
        data.appendBE(UInt32(1_000_000))
        XCTAssertThrowsError(try LNTE.parseHeader(data)) { error in
            XCTAssertEqual(error as? LNTE.HeaderError, .tooLong(1_000_000))
        }
    }

    func testResponseLayout() {
        let data = [UInt8](LNTE.response(status: .ok, session: 0x0102_0304_0506_0708, message: "ok"))
        XCTAssertEqual(Array(data[0..<4]), Array("LNTE".utf8))
        XCTAssertEqual(Array(data[4..<6]), [0, 1])
        XCTAssertEqual(data[6], 0)
        XCTAssertEqual(Array(data[7..<15]), [1, 2, 3, 4, 5, 6, 7, 8])
        XCTAssertEqual(Array(data[15..<17]), [0, 2])
        XCTAssertEqual(Array(data[17...]), Array("ok".utf8))
    }

    func testControlOpening() {
        var data = Data(LNTE.controlMagic)
        data.appendBE(UInt64(42))
        XCTAssertEqual(LNTE.parseControl(data), 42)
        XCTAssertNil(LNTE.parseControl(LNTE.request(params: "").prefix(12)))
    }

    // MARK: Parameters

    func testDefaults() throws {
        let p = try SessionParams.parse("").get()
        XCTAssertEqual(p.codec, .h264)
        XCTAssertEqual(p.size, SessionParams.Size(width: 1920, height: 1080))
        XCTAssertEqual(p.fps, 60)
        XCTAssertEqual(p.bitRate, 16_000_000)
        XCTAssertTrue(p.sendFrameMeta)
        XCTAssertFalse(p.rawStream)
    }

    func testParsesValues() throws {
        let p = try SessionParams.parse(
            "video_codec=h265\nvideo_bit_rate=40000000\ncamera_size=3840x2160\ncamera_fps=30\ncamera_id=2\nlente_stabilization=standard\nmax_size=0\n"
        ).get()
        XCTAssertEqual(p.codec, .h265)
        XCTAssertEqual(p.bitRate, 40_000_000)
        XCTAssertEqual(p.size, SessionParams.Size(width: 3840, height: 2160))
        XCTAssertEqual(p.fps, 30)
        XCTAssertEqual(p.cameraId, 2)
        XCTAssertTrue(p.stabilization)
    }

    func testUnknownKeyFails() {
        XCTAssertEqual(SessionParams.parse("bogus=1").failure, .unknownKey("bogus"))
    }

    func testInvalidValueFails() {
        XCTAssertEqual(SessionParams.parse("camera_size=big").failure,
                       .invalidValue(key: "camera_size", value: "big"))
        XCTAssertEqual(SessionParams.parse("camera_id=7").failure,
                       .invalidValue(key: "camera_id", value: "7"))
    }

    func testMalformedLineFails() {
        XCTAssertEqual(SessionParams.parse("raw_stream").failure, .malformedLine("raw_stream"))
    }

    func testRawStreamDisablesMeta() throws {
        let p = try SessionParams.parse("raw_stream=true").get()
        XCTAssertTrue(p.rawStream)
        XCTAssertFalse(p.sendDeviceMeta)
        XCTAssertFalse(p.sendStreamMeta)
        XCTAssertFalse(p.sendFrameMeta)
    }

    // MARK: scrcpy framing

    func testDeviceMetaIs64BytesZeroPadded() {
        let data = [UInt8](ScrcpyPacket.deviceMeta(name: "iPhone 15 Pro Max"))
        XCTAssertEqual(data.count, 64)
        XCTAssertEqual(Array(data[0..<17]), Array("iPhone 15 Pro Max".utf8))
        XCTAssertTrue(data[17...].allSatisfy { $0 == 0 })
    }

    func testStreamMetaIsCodecId() {
        XCTAssertEqual(Array(ScrcpyPacket.streamMeta(codec: .h264)), Array("h264".utf8))
        XCTAssertEqual(Array(ScrcpyPacket.streamMeta(codec: .h265)), Array("h265".utf8))
    }

    func testSessionPacket() {
        XCTAssertEqual(Array(ScrcpyPacket.session(width: 1920, height: 1080)),
                       [0x80, 0, 0, 0, 0, 0, 0x07, 0x80, 0, 0, 0x04, 0x38])
    }

    func testConfigPacketHeader() {
        let data = [UInt8](ScrcpyPacket.mediaHeader(ptsMicros: 123, config: true, keyFrame: false, size: 10))
        XCTAssertEqual(data, [0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 10])
    }

    func testKeyFramePacketHeader() {
        let data = [UInt8](ScrcpyPacket.mediaHeader(ptsMicros: 0x0102, config: false, keyFrame: true, size: 0x0304))
        XCTAssertEqual(data, [0x20, 0, 0, 0, 0, 0, 0x01, 0x02, 0, 0, 0x03, 0x04])
    }

    func testPtsNeverTouchesFlagBits() {
        let data = [UInt8](ScrcpyPacket.mediaHeader(ptsMicros: UInt64.max, config: false, keyFrame: false, size: 1))
        XCTAssertEqual(data[0], 0x1F)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
