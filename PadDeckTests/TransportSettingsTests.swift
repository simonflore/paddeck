import XCTest
@testable import PadDeck

final class TransportSettingsTests: XCTestCase {
    func testDefaults() {
        let s = TransportSettings()
        XCTAssertEqual(s.globalQuantize, .bar)
        XCTAssertEqual(s.timeSignature, TimeSignature())
        XCTAssertTrue(s.followExternalClock)
        XCTAssertFalse(s.ignoreStartStop)
        XCTAssertEqual(s.latencyOffsetMs, 0, accuracy: 0.0001)
        XCTAssertEqual(s.manualBPM, 120, accuracy: 0.0001)
        XCTAssertNil(s.clockSourceName)
        XCTAssertFalse(s.stopImmediately)
    }

    func testRoundTrips() throws {
        var s = TransportSettings()
        s.globalQuantize = .twoBars
        s.ignoreStartStop = true
        s.latencyOffsetMs = -12
        s.clockSourceName = "IAC Driver Bus 1"
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(TransportSettings.self, from: data)
        XCTAssertEqual(decoded.globalQuantize, .twoBars)
        XCTAssertTrue(decoded.ignoreStartStop)
        XCTAssertEqual(decoded.latencyOffsetMs, -12, accuracy: 0.0001)
        XCTAssertEqual(decoded.clockSourceName, "IAC Driver Bus 1")
    }

    func testPartialJSONUsesDefaults() throws {
        // Older JSON missing newer keys still decodes.
        let json = "{\"globalQuantize\":\"half\"}".data(using: .utf8)!
        let decoded = try JSONDecoder().decode(TransportSettings.self, from: json)
        XCTAssertEqual(decoded.globalQuantize, .half)
        XCTAssertTrue(decoded.followExternalClock) // default preserved
    }
}
