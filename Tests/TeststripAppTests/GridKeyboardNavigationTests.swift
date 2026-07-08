import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class GridKeyboardNavigationTests: XCTestCase {
    // MARK: - Selection movement

    func testMovingRightAdvancesOneAsset() {
        let next = GridSelectionMovement.nextIndex(from: 2, direction: .right, count: 10, columns: 4)
        XCTAssertEqual(next, 3)
    }

    func testMovingRightClampsAtLastAsset() {
        let next = GridSelectionMovement.nextIndex(from: 9, direction: .right, count: 10, columns: 4)
        XCTAssertEqual(next, 9)
    }

    func testMovingLeftClampsAtFirstAsset() {
        let next = GridSelectionMovement.nextIndex(from: 0, direction: .left, count: 10, columns: 4)
        XCTAssertEqual(next, 0)
    }

    func testMovingDownAdvancesByColumnCount() {
        let next = GridSelectionMovement.nextIndex(from: 1, direction: .down, count: 10, columns: 4)
        XCTAssertEqual(next, 5)
    }

    func testMovingDownStaysWhenNoRowBelow() {
        let next = GridSelectionMovement.nextIndex(from: 8, direction: .down, count: 10, columns: 4)
        XCTAssertEqual(next, 8)
    }

    func testMovingUpRetreatsByColumnCount() {
        let next = GridSelectionMovement.nextIndex(from: 5, direction: .up, count: 10, columns: 4)
        XCTAssertEqual(next, 1)
    }

    func testMovingUpStaysWhenNoRowAbove() {
        let next = GridSelectionMovement.nextIndex(from: 2, direction: .up, count: 10, columns: 4)
        XCTAssertEqual(next, 2)
    }

    func testHomeSelectsFirstAndEndSelectsLast() {
        XCTAssertEqual(GridSelectionMovement.nextIndex(from: 5, direction: .home, count: 10, columns: 4), 0)
        XCTAssertEqual(GridSelectionMovement.nextIndex(from: 5, direction: .end, count: 10, columns: 4), 9)
    }

    func testWalkingRightReachesEveryAssetInOnePressEach() {
        // A straight-line rightward walk must visit every asset exactly once,
        // with no skipping (the double-step regression skipped every other one).
        let count = 24
        let columns = 5
        var index = 0
        var visited = [0]
        for _ in 0..<(count - 1) {
            index = GridSelectionMovement.nextIndex(
                from: index,
                direction: .right,
                count: count,
                columns: columns
            )!
            visited.append(index)
        }
        XCTAssertEqual(visited, Array(0..<count))
        XCTAssertEqual(Set(visited).count, count)
    }

    func testUpThenDownReturnsToSameAssetByColumnCount() {
        let count = 24
        let columns = 5
        let start = 12
        let down = GridSelectionMovement.nextIndex(from: start, direction: .down, count: count, columns: columns)!
        XCTAssertEqual(down, start + columns)
        let up = GridSelectionMovement.nextIndex(from: down, direction: .up, count: count, columns: columns)!
        XCTAssertEqual(up, start)
    }

    func testMovementReturnsNilForEmptyGrid() {
        XCTAssertNil(GridSelectionMovement.nextIndex(from: 0, direction: .right, count: 0, columns: 4))
    }

    func testMovementTreatsColumnCountBelowOneAsSingleColumn() {
        let next = GridSelectionMovement.nextIndex(from: 1, direction: .down, count: 10, columns: 0)
        XCTAssertEqual(next, 2)
    }

    // MARK: - Column count

    func testColumnCountFitsWholeItemsAcrossAvailableWidth() {
        let columns = LibraryGridColumnCount.columns(availableWidth: 640, minimumItemWidth: 140, spacing: 11)
        XCTAssertEqual(columns, 4)
    }

    func testColumnCountIsAtLeastOne() {
        let columns = LibraryGridColumnCount.columns(availableWidth: 20, minimumItemWidth: 140, spacing: 11)
        XCTAssertEqual(columns, 1)
    }

    // MARK: - Key decoding

    func testArrowKeysDecodeToMovementCommands() {
        XCTAssertEqual(GridKeyCommand(input: .leftArrow), .move(.left))
        XCTAssertEqual(GridKeyCommand(input: .rightArrow), .move(.right))
        XCTAssertEqual(GridKeyCommand(input: .upArrow), .move(.up))
        XCTAssertEqual(GridKeyCommand(input: .downArrow), .move(.down))
        XCTAssertEqual(GridKeyCommand(input: .home), .move(.home))
        XCTAssertEqual(GridKeyCommand(input: .end), .move(.end))
    }

    func testRatingAndFlagKeysDecodeToMetadataCommands() {
        XCTAssertEqual(GridKeyCommand(input: .character("0")), .rating(0))
        XCTAssertEqual(GridKeyCommand(input: .character("3")), .rating(3))
        XCTAssertEqual(GridKeyCommand(input: .character("5")), .rating(5))
        XCTAssertEqual(GridKeyCommand(input: .character("P")), .pick)
        XCTAssertEqual(GridKeyCommand(input: .character("x")), .reject)
        XCTAssertEqual(GridKeyCommand(input: .character("u")), .clearFlag)
        XCTAssertNil(GridKeyCommand(input: .character("q")))
    }

    func testEnterOpensLoupeAndEscapeReturnsToGrid() {
        XCTAssertEqual(GridKeyCommand(input: .returnKey), .openLoupe)
        XCTAssertEqual(GridKeyCommand(input: .escape), .returnToGrid)
    }

    func testCommandAvailabilityDependsOnMode() {
        XCTAssertTrue(GridKeyCommand.move(.right).isAllowed(in: .grid))
        XCTAssertTrue(GridKeyCommand.rating(3).isAllowed(in: .grid))
        XCTAssertTrue(GridKeyCommand.openLoupe.isAllowed(in: .grid))
        XCTAssertFalse(GridKeyCommand.returnToGrid.isAllowed(in: .grid))

        XCTAssertTrue(GridKeyCommand.returnToGrid.isAllowed(in: .loupe))
        XCTAssertFalse(GridKeyCommand.move(.right).isAllowed(in: .loupe))

        XCTAssertFalse(GridKeyCommand.move(.right).isAllowed(in: .compare))
    }

    // MARK: - Model routing

    func testMoveGridSelectionSelectsHorizontalNeighbor() {
        let assets = (0..<8).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: assets)
        model.select(assets[2].id)

        model.moveGridSelection(.right, columns: 4)

        XCTAssertEqual(model.selectedAssetID, assets[3].id)
    }

    func testMoveGridSelectionSelectsAssetOneRowDown() {
        let assets = (0..<8).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: assets)
        model.select(assets[1].id)

        model.moveGridSelection(.down, columns: 4)

        XCTAssertEqual(model.selectedAssetID, assets[5].id)
    }

    func testApplyGridKeyCommandOpenLoupeSwitchesView() throws {
        let assets = (0..<4).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: assets)
        model.select(assets[2].id)

        try model.applyGridKeyCommand(.openLoupe, columns: 4)

        XCTAssertEqual(model.selectedView, .loupe)
        XCTAssertEqual(model.selectedAssetID, assets[2].id)
    }

    func testApplyGridKeyCommandReturnToGridSwitchesView() throws {
        let assets = (0..<4).map { makeAsset(id: "asset-\($0)", size: Int64($0 + 1)) }
        let model = AppModel(sidebarSections: [], selectedView: .loupe, assets: assets)

        try model.applyGridKeyCommand(.returnToGrid, columns: 4)

        XCTAssertEqual(model.selectedView, .grid)
    }

    private func makeAsset(id: String, size: Int64) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: size, modificationDate: Date(timeIntervalSince1970: TimeInterval(size))),
            availability: .online,
            metadata: AssetMetadata()
        )
    }
}
