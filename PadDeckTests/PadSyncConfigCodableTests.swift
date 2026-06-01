import XCTest
@testable import PadDeck

final class PadSyncConfigCodableTests: XCTestCase {
    func testOldPadJSONDecodesWithNilSyncConfig() throws {
        // A pad encoded before syncConfig existed (no syncConfig key).
        let json = """
        {"position":{"row":0,"column":0},"color":{"r":0,"g":0,"b":0},
         "playMode":"loop","volume":1.0}
        """.data(using: .utf8)!
        let pad = try JSONDecoder().decode(PadConfiguration.self, from: json)
        XCTAssertNil(pad.syncConfig)
        XCTAssertFalse(pad.isSynced)
    }

    func testSyncConfigRoundTrips() throws {
        var pad = PadConfiguration(position: GridPosition(row: 1, column: 2))
        pad.syncConfig = PadSyncConfig(
            loopLength: MusicalLength(bars: 2, beats: 0),
            quantizeOverride: .half,
            timeStretchEnabled: false
        )
        let data = try JSONEncoder().encode(pad)
        let decoded = try JSONDecoder().decode(PadConfiguration.self, from: data)
        XCTAssertEqual(decoded.syncConfig?.loopLength, MusicalLength(bars: 2, beats: 0))
        XCTAssertEqual(decoded.syncConfig?.quantizeOverride, .half)
        XCTAssertTrue(decoded.isSynced)
    }

    func testSwapPadsCarriesSyncAndInstrumentConfig() {
        var project = Project(name: "T")
        let a = GridPosition(row: 0, column: 0)
        let b = GridPosition(row: 0, column: 1)
        var padA = project.pad(at: a)
        padA.syncConfig = PadSyncConfig(loopLength: MusicalLength(bars: 1, beats: 0))
        project.setPad(padA, at: a)

        project.swapPads(a, b)
        XCTAssertNotNil(project.pad(at: b).syncConfig)
        XCTAssertNil(project.pad(at: a).syncConfig)
    }
}
