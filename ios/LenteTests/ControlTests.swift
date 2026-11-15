import XCTest
@testable import Lente

final class ControlTests: XCTestCase {
    private func parseAll(_ bytes: [UInt8]) throws -> [ControlMessage] {
        var offset = 0
        var out: [ControlMessage] = []
        while let parsed = try ControlParser.next(bytes, at: offset) {
            out.append(parsed.0)
            offset += parsed.1
        }
        XCTAssertEqual(offset, bytes.count, "every byte consumed")
        return out
    }

    func testCameraMessages() throws {
        let bytes: [UInt8] = [10, 0, 10, 1, 17, 18, 1, 18, 0, 19, 20, 0x60, 2, 0x61, 3, 1]
        XCTAssertEqual(try parseAll(bytes), [
            .displayPower(on: false), .displayPower(on: true), .resetVideo,
            .torch(on: true), .torch(on: false), .zoomIn, .zoomOut,
            .setLens(2), .lock(what: 3, on: true),
        ])
    }

    func testSkipsScrcpyMessagesItDoesNotUse() throws {
        var bytes: [UInt8] = [0] + [UInt8](repeating: 0, count: 13) // keycode, 14 bytes
        bytes += [1, 0, 0, 0, 3] + Array("abc".utf8) // text
        bytes += [2] + [UInt8](repeating: 0, count: 31) // touch, 32 bytes
        bytes += [3] + [UInt8](repeating: 0, count: 20) // scroll, 21 bytes
        bytes += [9] + [UInt8](repeating: 0, count: 9) + [0, 0, 0, 2] + Array("hi".utf8) // set clipboard
        bytes += [12, 0, 1, 0, 2, 0, 3, 2] + Array("kb".utf8) + [0, 2, 9, 9] // uhid create
        bytes += [13, 0, 1, 0, 3, 7, 7, 7] // uhid input
        bytes += [14, 0, 1] // uhid destroy
        bytes += [16, 3] + Array("app".utf8) // start app
        bytes += [21, 0, 1, 0, 2] // resize display
        bytes += [22, 0, 0, 0, 1, 0x2F] // scan file
        bytes += [4, 0, 5, 6, 7, 8, 1, 11, 15] // short ones
        let messages = try parseAll(bytes)
        XCTAssertEqual(messages.count, 18)
        XCTAssertTrue(messages.allSatisfy { if case .ignored = $0 { return true } else { return false } })
    }

    func testIncompleteMessageWaitsForMoreBytes() throws {
        XCTAssertNil(try ControlParser.next([], at: 0))
        XCTAssertNil(try ControlParser.next([10], at: 0))
        XCTAssertNil(try ControlParser.next([1, 0, 0, 0, 5, 0x61], at: 0))
        XCTAssertNil(try ControlParser.next([12, 0, 1, 0, 2, 0, 3, 2, 0x6B], at: 0))
    }

    func testUnknownTypeIsAnError() {
        XCTAssertThrowsError(try ControlParser.next([0x5F], at: 0)) { error in
            XCTAssertEqual(error as? ControlParser.ParseError, .unknownType(0x5F))
        }
    }

    func testTelemetryLayout() {
        let t = DeviceMessage.Telemetry(thermal: 2, battery: 87, batteryState: 2,
                                        frames: 0x0102_0304, dropped: 5, bitRate: 24_000_000)
        let data = [UInt8](DeviceMessage.telemetry(t))
        XCTAssertEqual(data.count, 16)
        XCTAssertEqual(Array(data[0..<4]), [0x60, 2, 87, 2])
        XCTAssertEqual(Array(data[4..<8]), [1, 2, 3, 4])
        XCTAssertEqual(Array(data[8..<12]), [0, 0, 0, 5])
        XCTAssertEqual(readBE(data, at: 12, as: UInt32.self), 24_000_000)
    }

    func testEventLayout() {
        let data = [UInt8](DeviceMessage.event(.lensChanged, "5x"))
        XCTAssertEqual(data, [0x61, 3, 0, 2] + Array("5x".utf8))
    }

    func testNewParameters() throws {
        let p = try SessionParams.parse(
            "capture_orientation=90\ncamera_torch=true\ncamera_zoom=2.5\nlente_lock_exposure=true\nlente_lock_wb=true"
        ).get()
        XCTAssertEqual(p.rotation, 90)
        XCTAssertEqual(p.outputSize, SessionParams.Size(width: 1080, height: 1920))
        XCTAssertTrue(p.torch)
        XCTAssertEqual(p.zoom, 2.5)
        XCTAssertTrue(p.lockExposure)
        XCTAssertFalse(p.lockFocus)
        XCTAssertTrue(p.lockWhiteBalance)

        let locked = try SessionParams.parse("capture_orientation=@180").get()
        XCTAssertEqual(locked.rotation, 180)
        XCTAssertEqual(locked.outputSize, SessionParams.Size(width: 1920, height: 1080))

        if case .success = SessionParams.parse("capture_orientation=45") { XCTFail("45 is not valid") }
        if case .success = SessionParams.parse("camera_zoom=0") { XCTFail("zoom 0 is not valid") }
    }
}
