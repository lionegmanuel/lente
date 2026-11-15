import CoreMedia
import XCTest
@testable import Lente

final class AnnexBTests: XCTestCase {
    func testConvertsTwoNalUnits() {
        let avcc: [UInt8] = [0, 0, 0, 2, 0x65, 0xAA, 0, 0, 0, 3, 0x41, 0xBB, 0xCC]
        let out = AnnexB.fromAVCC(avcc)
        XCTAssertEqual(out.map(Array.init), [0, 0, 0, 1, 0x65, 0xAA, 0, 0, 0, 1, 0x41, 0xBB, 0xCC])
    }

    func testShortLengthSize() {
        let avcc: [UInt8] = [0, 1, 0x09]
        XCTAssertEqual(AnnexB.fromAVCC(avcc, lengthSize: 2).map(Array.init), [0, 0, 0, 1, 0x09])
    }

    func testRejectsTruncatedUnit() {
        XCTAssertNil(AnnexB.fromAVCC([0, 0, 0, 5, 0x65, 0xAA]))
    }

    func testRejectsTruncatedLength() {
        XCTAssertNil(AnnexB.fromAVCC([0, 0, 0]))
    }

    func testRejectsZeroLength() {
        XCTAssertNil(AnnexB.fromAVCC([0, 0, 0, 0]))
    }

    func testEmptyInputGivesEmptyOutput() {
        XCTAssertEqual(AnnexB.fromAVCC([]), Data())
    }

    func testJoinParameterSets() {
        let sps = Data([0x67, 0x64, 0x00, 0x28])
        let pps = Data([0x68, 0xEE, 0x3C, 0x80])
        XCTAssertEqual(Array(AnnexB.join([sps, pps])),
                       [0, 0, 0, 1, 0x67, 0x64, 0x00, 0x28, 0, 0, 0, 1, 0x68, 0xEE, 0x3C, 0x80])
    }

    func testParameterSetsFromH264FormatDescription() throws {
        let sps: [UInt8] = [0x67, 0x64, 0x00, 0x2A, 0xAC, 0xD9, 0x40, 0x78, 0x02, 0x27, 0xE5, 0xC0, 0x44, 0x00, 0x00, 0x03, 0x00, 0x04, 0x00, 0x00, 0x03, 0x01, 0xE0, 0x3C, 0x60, 0xC6, 0x58]
        let pps: [UInt8] = [0x68, 0xEB, 0xE3, 0xCB, 0x22, 0xC0]
        var format: CMFormatDescription?
        let status = sps.withUnsafeBufferPointer { spsPtr in
            pps.withUnsafeBufferPointer { ppsPtr in
                let pointers = [spsPtr.baseAddress!, ppsPtr.baseAddress!]
                let sizes = [sps.count, pps.count]
                return CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2, parameterSetPointers: pointers,
                    parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &format)
            }
        }
        XCTAssertEqual(status, noErr)
        let result = try XCTUnwrap(AnnexB.parameterSets(XCTUnwrap(format), codec: .h264))
        XCTAssertEqual(result.lengthSize, 4)
        XCTAssertEqual(result.sets.map(Array.init), [sps, pps])
    }
}
