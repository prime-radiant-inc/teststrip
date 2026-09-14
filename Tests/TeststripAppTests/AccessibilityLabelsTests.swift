import XCTest
import TeststripCore
@testable import TeststripApp

/// The accessible names and automation identifiers introduced for the
/// accessibility/copy pass: the import sheet's container and controls, the
/// Library grid's icon-only chrome, the tentative AI marker, and the People
/// suggestion cards' distinguishing names. A live AX pass is not available in
/// unit tests, so these pin the strings the views apply.
final class AccessibilityLabelsTests: XCTestCase {
    // MARK: - Import sheet (item 1)

    func testImportSheetHasANamedContainerAndUniqueIdentifiers() {
        XCTAssertEqual(ImportSheetAccessibility.sheetLabel, "Import Photos")

        let identifiers = [
            ImportSheetAccessibility.sheetIdentifier,
            ImportSheetAccessibility.filterIdentifier,
            ImportSheetAccessibility.countIdentifier,
            ImportSheetAccessibility.gridIdentifier,
            ImportSheetAccessibility.selectAllIdentifier,
            ImportSheetAccessibility.selectNoneIdentifier,
            ImportSheetAccessibility.cancelIdentifier,
            ImportSheetAccessibility.importIdentifier
        ]
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "identifiers must be unique")
        XCTAssertFalse(identifiers.contains(where: \.isEmpty))
    }

    func testImportCountSummaryNamesSelectedOfTotal() {
        XCTAssertEqual(
            ImportSheetAccessibility.countSummaryLabel(selectedCount: 3, totalCount: 5),
            "3 of 5 selected"
        )
    }

    func testImportCellValueDistinguishesSelectionAndDuplicates() {
        XCTAssertEqual(
            ImportSheetAccessibility.cellValue(isSelected: true, isDuplicate: false),
            "Selected"
        )
        XCTAssertEqual(
            ImportSheetAccessibility.cellValue(isSelected: false, isDuplicate: false),
            "Not selected"
        )
        XCTAssertEqual(
            ImportSheetAccessibility.cellValue(isSelected: false, isDuplicate: true),
            "Not selected, Duplicate"
        )
    }

    func testImportCellLabelIsTheFilename() {
        XCTAssertEqual(ImportSheetAccessibility.cellLabel(filename: "IMG_0001.jpg"), "IMG_0001.jpg")
        XCTAssertEqual(
            ImportSheetAccessibility.cellIdentifier(filename: "IMG_0001.jpg"),
            "importSelection.cell.IMG_0001.jpg"
        )
    }

    func testImportButtonLabelCountsTheSelection() {
        XCTAssertEqual(ImportSheetAccessibility.importButtonLabel(selectedCount: 4), "Import 4 Photos")
    }

    // MARK: - Grid chrome (items 2, 5, 6, 8)

    // The live AX probe matched the "Clear filters" help text to an element
    // described only as "Close" (the raw `xmark.circle` symbol). The label
    // must say what the control does, not reuse the symbol name.
    func testClearFiltersIsNamedByItsActionNotTheSymbol() {
        XCTAssertEqual(GridChromeAccessibility.clearFiltersLabel, "Clear filters")
        XCTAssertNotEqual(GridChromeAccessibility.clearFiltersLabel, "Close")
    }

    func testIconOnlyChromeCarriesRealNames() {
        XCTAssertEqual(GridChromeAccessibility.thumbnailSizeLabel, "Thumbnail size")
        XCTAssertEqual(GridChromeAccessibility.refreshSourceStatusLabel, "Refresh source status")
        XCTAssertEqual(GridChromeAccessibility.retryMetadataSyncLabel, "Retry pending metadata sync")
        for label in [
            GridChromeAccessibility.thumbnailSizeLabel,
            GridChromeAccessibility.refreshSourceStatusLabel,
            GridChromeAccessibility.retryMetadataSyncLabel
        ] {
            XCTAssertFalse(label.contains("."), "a name must not be a raw SF Symbol (\(label))")
        }
    }

    func testSmartCollectionFieldsAreNamed() {
        XCTAssertEqual(GridChromeAccessibility.smartCollectionNameLabel, "Smart Collection name")
        XCTAssertEqual(GridChromeAccessibility.smartCollectionRuleLabel, "Smart Collection rule")
    }

    // Suggestion chips and active-filter chips must speak one vocabulary:
    // "Add filter X" / "Remove filter X", name and help agreeing.
    func testChipLabelsShareAddRemoveFilterVocabulary() {
        XCTAssertEqual(GridChromeAccessibility.filterChipAddLabel(for: "Rating >= 4"), "Add filter Rating >= 4")
        XCTAssertEqual(GridChromeAccessibility.filterChipRemoveLabel(for: "Rating >= 4"), "Remove filter Rating >= 4")
    }

    // MARK: - Tentative AI provenance (item 3)

    func testUnconfirmedAIMarkerIsNamedTentative() {
        XCTAssertEqual(AITentativeAccessibility.unconfirmedMarkerLabel, "AI-suggested, unconfirmed")
    }

    func testUnconfirmedAIValueNamesBothTheValueAndTheTentativeState() {
        XCTAssertEqual(
            AITentativeAccessibility.unconfirmedValueLabel("sunset"),
            "sunset, AI-suggested, unconfirmed"
        )
    }

    // MARK: - People suggestion cards (item 7)

    func testSuggestionCardsWithTheSameCopyGetDistinctAccessibleNames() {
        let first = suggestionCard(id: "group-a")
        let second = suggestionCard(id: "group-b")

        let firstName = PeopleFaceSuggestionCard.accessibleLabel(for: first, index: 0, total: 2)
        let secondName = PeopleFaceSuggestionCard.accessibleLabel(for: second, index: 1, total: 2)

        XCTAssertTrue(firstName.contains("Who is this?"), "the card's own copy must stay readable")
        XCTAssertTrue(firstName.contains("1 face · 1 photo"))
        XCTAssertTrue(secondName.contains("group 2 of 2"))
        XCTAssertNotEqual(firstName, secondName, "identical cards must not share an AX name")
    }

    private func suggestionCard(id: String) -> PeopleFaceSuggestionCard {
        let suggestion = PeopleFaceSuggestion(
            id: id,
            kind: .newPerson,
            faceIDs: [FaceID(assetID: AssetID(rawValue: id), faceIndex: 0)],
            representativeFace: FaceID(assetID: AssetID(rawValue: id), faceIndex: 0),
            representativeBoundingBox: FaceBoundingBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            assetIDs: [AssetID(rawValue: id)]
        )
        return PeopleFaceSuggestionCard(
            id: id,
            title: "Who is this?",
            countText: "1 face · 1 photo",
            confirmActionTitle: "Name…",
            isOneTapConfirm: false,
            suggestion: suggestion
        )
    }
}
