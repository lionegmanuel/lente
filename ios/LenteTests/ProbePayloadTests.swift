import XCTest
@testable import Lente

final class ProbePayloadTests: XCTestCase {
    func testFirstChunk() {
        let chunk = ProbePayload.chunk(index: 0)
        XCTAssertEqual(chunk.count, ProbePayload.size)
        XCTAssertEqual(Array(chunk.prefix(8)), Array("LENTE-F0".utf8))
        XCTAssertEqual(Array(chunk.suffix(4)), [0, 0, 0, 0])
    }

    func testCounterIsBigEndian() {
        let chunk = ProbePayload.chunk(index: 0x0102_0304)
        XCTAssertEqual(Array(chunk.suffix(4)), [1, 2, 3, 4])
    }
}
