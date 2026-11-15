import XCTest
@testable import Lente

final class FormatSelectionTests: XCTestCase {
    private func candidate(_ w: Int, _ h: Int, maxFps: Double, is420v: Bool = true, sensor: Int = 12_000_000)
        -> FormatSelection.Candidate {
        FormatSelection.Candidate(width: w, height: h, fpsRanges: [1...maxFps], is420v: is420v, sensorPixels: sensor)
    }

    func testPicksExactSizeAndFps() {
        let list = [candidate(1280, 720, maxFps: 60), candidate(1920, 1080, maxFps: 30), candidate(1920, 1080, maxFps: 60)]
        XCTAssertEqual(FormatSelection.choose(list, width: 1920, height: 1080, fps: 60), 2)
    }

    func testPrefersSmallestSensorReadout() {
        let list = [candidate(1920, 1080, maxFps: 60, sensor: 48_000_000),
                    candidate(1920, 1080, maxFps: 60, sensor: 12_000_000)]
        XCTAssertEqual(FormatSelection.choose(list, width: 1920, height: 1080, fps: 60), 1)
    }

    func testSkipsNon420vFormats() {
        let list = [candidate(1920, 1080, maxFps: 60, is420v: false)]
        XCTAssertNil(FormatSelection.choose(list, width: 1920, height: 1080, fps: 60))
    }

    func testNoMatchReturnsNil() {
        let list = [candidate(1920, 1080, maxFps: 30)]
        XCTAssertNil(FormatSelection.choose(list, width: 1920, height: 1080, fps: 60))
    }

    func testDescribeListsUniqueSizes() {
        let list = [candidate(1920, 1080, maxFps: 60), candidate(1920, 1080, maxFps: 60, sensor: 1),
                    candidate(3840, 2160, maxFps: 30), candidate(640, 480, maxFps: 30, is420v: false)]
        XCTAssertEqual(FormatSelection.describe(list), "1920x1080@60, 3840x2160@30")
    }
}
