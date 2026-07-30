import XCTest
@testable import TeststripCore
@testable import TeststripApp

// SP-C: the warm-set planner is pure priority ordering — the staged burst
// radiating outward (forward first), then the next stacks' landing frames,
// then one landing back. The driver turns this into gated queue requests.
final class CullPrefetchPlannerTests: XCTestCase {
    private func id(_ raw: String) -> AssetID { AssetID(rawValue: raw) }
    private func stack(_ raws: [String]) -> AssetStack { AssetStack(assetIDs: raws.map(id)) }

    // stops: [x] [a b c d e] [f g] [h] [i j] with staged = c
    private var stops: [AssetStack] {
        [stack(["x"]), stack(["a", "b", "c", "d", "e"]), stack(["f", "g"]), stack(["h"]), stack(["i", "j"])]
    }

    func testRadiatesOutwardFromStagedFrameForwardFirst() {
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("c"),
            landingAssetID: { $0.assetIDs.first }
        )
        // Burst first: staged, then following in rail order, then earlier nearest-first.
        XCTAssertEqual(Array(warm.prefix(5)), [id("c"), id("d"), id("e"), id("b"), id("a")])
    }

    func testAppendsNextThreeLandingsThenPreviousLanding() {
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("c"),
            landingAssetID: { $0.assetIDs.first }
        )
        XCTAssertEqual(Array(warm.suffix(4)), [id("f"), id("h"), id("i"), id("x")])
    }

    func testFirstStopHasNoPreviousEntry() {
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("x"),
            landingAssetID: { $0.assetIDs.first }
        )
        XCTAssertEqual(warm, [id("x"), id("a"), id("f"), id("h")])
    }

    func testLastStopHasNoNextEntries() {
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("j"),
            landingAssetID: { $0.assetIDs.first }
        )
        XCTAssertEqual(warm, [id("j"), id("i"), id("h")])
    }

    func testStagedAssetOutsideEveryStopReturnsEmpty() {
        XCTAssertEqual(
            CullPrefetchPlanner.warmAssetIDs(
                stops: stops,
                stagedAssetID: id("nope"),
                landingAssetID: { $0.assetIDs.first }
            ),
            []
        )
    }

    func testNilLandingsAreSkippedAndDuplicatesDeduped() {
        // Landing resolver that punts on "h" and (artificially) lands "i j"
        // on the staged frame — the planner must skip the nil and dedup the
        // repeat instead of double-queuing.
        let warm = CullPrefetchPlanner.warmAssetIDs(
            stops: stops,
            stagedAssetID: id("c"),
            landingAssetID: { s in
                if s.assetIDs.contains(self.id("h")) { return nil }
                if s.assetIDs.contains(self.id("i")) { return self.id("c") }
                return s.assetIDs.first
            }
        )
        XCTAssertEqual(warm, [id("c"), id("d"), id("e"), id("b"), id("a"), id("f"), id("x")])
    }
}
