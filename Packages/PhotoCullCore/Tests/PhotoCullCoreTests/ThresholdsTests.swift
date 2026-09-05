import XCTest
@testable import PhotoCullCore

final class ThresholdsTests: XCTestCase {
    func testRoundTrip() throws {
        var t = Thresholds()
        t.similarityDistanceMax = 0.42
        XCTAssertEqual(Thresholds.default.similarityDistanceMax, 0.05)
        let data = try JSONEncoder().encode(t)
        XCTAssertEqual(try JSONDecoder().decode(Thresholds.self, from: data), t)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let data = Data(#"{"similarityDistanceMax": 0.3}"#.utf8)
        let t = try JSONDecoder().decode(Thresholds.self, from: data)
        XCTAssertEqual(t.similarityDistanceMax, 0.3)
        XCTAssertEqual(t.groupTimeGapSeconds, 120)
        XCTAssertEqual(t.whatsAppAlbumName, "WhatsApp")
    }
}
