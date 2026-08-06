import XCTest
@testable import TeststripCore

// The ghost — an AI-origin, unconfirmed flag in asset metadata — is the single
// source of truth for "the machine proposed a flag". `AutopilotGhost.kind(in:)`
// is the only place that derivation is written; every surface reads it.
final class AutopilotGhostTests: XCTestCase {
    func testGhostKindIsTheFlagValueWhenTheFlagIsAIUnconfirmed() {
        let pick = AssetMetadata(flag: .pick, aiUnconfirmedFields: [.flag])
        let reject = AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag])

        XCTAssertEqual(AutopilotGhost.kind(in: pick), .pick)
        XCTAssertEqual(AutopilotGhost.kind(in: reject), .reject)
    }

    func testUserOriginFlagIsNotAGhost() {
        let pick = AssetMetadata(flag: .pick)
        let reject = AssetMetadata(flag: .reject)

        XCTAssertNil(AutopilotGhost.kind(in: pick))
        XCTAssertNil(AutopilotGhost.kind(in: reject))
    }

    // A frame is allowed to have no status at all — that is the whole point of
    // deriving instead of storing.
    func testNoFlagIsNotAGhost() {
        XCTAssertNil(AutopilotGhost.kind(in: AssetMetadata()))
    }

    // Other unconfirmed fields are a different proposal entirely; only `.flag`
    // makes a flag ghost.
    func testUnconfirmedCaptionOrRatingAloneIsNotAFlagGhost() {
        let caption = AssetMetadata(caption: "a dog", aiUnconfirmedFields: [.caption])
        let rating = AssetMetadata(rating: 4, aiUnconfirmedFields: [.rating])

        XCTAssertNil(AutopilotGhost.kind(in: caption))
        XCTAssertNil(AutopilotGhost.kind(in: rating))
    }

    // Ambient AI keywords are invisible to flag-ghost derivation (spec
    // decision 2: keywords exit the review pipeline entirely).
    func testAmbientAIKeywordsAreInvisibleToGhostDerivation() {
        let keywordsOnly = AssetMetadata(
            keywords: ["dog", "beach"],
            aiUnconfirmedKeywords: ["dog", "beach"]
        )

        XCTAssertNil(AutopilotGhost.kind(in: keywordsOnly))
    }

    // Defensive: a marker left behind with no value is not a ghost. Nothing
    // should produce this state, and if something does, the derivation must
    // report "no status" rather than a phantom.
    func testUnconfirmedMarkerWithoutAFlagValueIsNotAGhost() {
        let orphanedMarker = AssetMetadata(flag: nil, aiUnconfirmedFields: [.flag])

        XCTAssertNil(AutopilotGhost.kind(in: orphanedMarker))
    }

    // The ghost is exactly what `confirmedProjection` filters out — these two
    // must never disagree about whether a flag is a real user decision.
    func testGhostIsExactlyWhatConfirmedProjectionDrops() {
        let ghost = AssetMetadata(flag: .reject, aiUnconfirmedFields: [.flag])
        let userFlag = AssetMetadata(flag: .reject)

        XCTAssertNil(ghost.confirmedProjection.flag)
        XCTAssertNotNil(AutopilotGhost.kind(in: ghost))
        XCTAssertNotNil(userFlag.confirmedProjection.flag)
        XCTAssertNil(AutopilotGhost.kind(in: userFlag))
    }
}
