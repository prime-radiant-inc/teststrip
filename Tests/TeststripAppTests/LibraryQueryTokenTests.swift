import XCTest
@testable import TeststripCore
@testable import TeststripApp

final class LibraryQueryTokenTests: XCTestCase {
    private func makeModel() -> AppModel {
        AppModel(sidebarSections: [], selectedView: .grid, assets: [])
    }

    // MARK: - Round trip: filterState -> tokens -> filterState

    func testRatingRoundTrips() {
        let model = makeModel()
        model.minimumRatingFilter = 3

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .rating }) else {
            return XCTFail("expected a rating token")
        }
        XCTAssertEqual(token.display, "Rating >= 3")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.minimumRatingFilter, 3)
    }

    func testFlagRoundTrips() {
        let model = makeModel()
        model.flagFilter = .pick

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .flag }) else {
            return XCTFail("expected a flag token")
        }
        XCTAssertEqual(token.display, "Pick")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.flagFilter, .pick)
    }

    func testKeywordRoundTrips() {
        let model = makeModel()
        model.keywordFilterText = "portfolio"

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .keyword }) else {
            return XCTFail("expected a keyword token")
        }
        XCTAssertEqual(token.display, "Keyword: portfolio")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.keywordFilterText, "portfolio")
    }

    func testFolderRoundTrips() {
        let model = makeModel()
        model.folderFilterText = "/Volumes/Photos/2024"

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .folder }) else {
            return XCTFail("expected a folder token")
        }
        XCTAssertEqual(token.display, "Folder: 2024")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.folderFilterText, "/Volumes/Photos/2024")
    }

    func testCameraRoundTrips() {
        let model = makeModel()
        model.cameraFilterText = "Canon EOS R5"

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .camera }) else {
            return XCTFail("expected a camera token")
        }
        XCTAssertEqual(token.display, "Camera: Canon EOS R5")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.cameraFilterText, "Canon EOS R5")
    }

    func testLensRoundTrips() {
        let model = makeModel()
        model.lensFilterText = "RF50"

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .lens }) else {
            return XCTFail("expected a lens token")
        }
        XCTAssertEqual(token.display, "Lens: RF50")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.lensFilterText, "RF50")
    }

    func testISORoundTrips() {
        let model = makeModel()
        model.minimumISOFilter = 800

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .iso }) else {
            return XCTFail("expected an iso token")
        }
        XCTAssertEqual(token.display, "ISO >= 800")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.minimumISOFilter, 800)
    }

    func testDateRangeRoundTrips() {
        let model = makeModel()
        let start = date(2024, 1, 1)
        let end = date(2024, 2, 1)
        model.captureDateStartFilter = start
        model.captureDateEndFilter = end

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let fromToken = tokens.first(where: { $0.field == .dateFrom }) else {
            return XCTFail("expected a dateFrom token")
        }
        guard let beforeToken = tokens.first(where: { $0.field == .dateBefore }) else {
            return XCTFail("expected a dateBefore token")
        }

        let restored = makeModel()
        LibraryQueryToken.apply(fromToken, to: restored)
        LibraryQueryToken.apply(beforeToken, to: restored)
        XCTAssertEqual(restored.captureDateStartFilter, start)
        XCTAssertEqual(restored.captureDateEndFilter, end)
    }

    func testColorRoundTrips() {
        let model = makeModel()
        model.colorLabelFilter = .red

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .color }) else {
            return XCTFail("expected a color token")
        }
        XCTAssertEqual(token.display, "Red Label")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.colorLabelFilter, .red)
    }

    func testSourceRoundTrips() {
        let model = makeModel()
        model.availabilityFilter = .online

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .source }) else {
            return XCTFail("expected a source token")
        }
        XCTAssertEqual(token.display, "Source: Online")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.availabilityFilter, .online)
    }

    func testSignalRoundTrips() {
        let model = makeModel()
        model.evaluationKindFilter = .focus

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .signal }) else {
            return XCTFail("expected a signal token")
        }

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertEqual(restored.evaluationKindFilter, .focus)
    }

    func testXMPPendingRoundTrips() {
        let model = makeModel()
        model.metadataSyncPendingFilter = true

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .xmpPending }) else {
            return XCTFail("expected an xmpPending token")
        }
        XCTAssertEqual(token.display, "XMP Pending")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertTrue(restored.metadataSyncPendingFilter)
    }

    func testXMPConflictRoundTrips() {
        let model = makeModel()
        model.metadataSyncConflictFilter = true

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let token = tokens.first(where: { $0.field == .xmpConflict }) else {
            return XCTFail("expected an xmpConflict token")
        }
        XCTAssertEqual(token.display, "XMP Conflicts")

        let restored = makeModel()
        LibraryQueryToken.apply(token, to: restored)
        XCTAssertTrue(restored.metadataSyncConflictFilter)
    }

    // MARK: - Removal only clears its own filter, siblings untouched

    /// Activates every structured filter, then removes each token in turn
    /// and asserts exactly that one field cleared and all siblings survived.
    func testRemovingEachTokenClearsOnlyItsOwnFilter() {
        func fullyFilteredModel() -> AppModel {
            let model = makeModel()
            model.minimumRatingFilter = 3
            model.flagFilter = .pick
            model.keywordFilterText = "portfolio"
            model.folderFilterText = "/Volumes/Photos/2024"
            model.cameraFilterText = "Canon EOS R5"
            model.lensFilterText = "RF50"
            model.minimumISOFilter = 800
            model.captureDateStartFilter = date(2024, 1, 1)
            model.captureDateEndFilter = date(2024, 2, 1)
            model.colorLabelFilter = .red
            model.availabilityFilter = .online
            model.evaluationKindFilter = .focus
            model.metadataSyncPendingFilter = true
            model.metadataSyncConflictFilter = true
            return model
        }

        let allFields: [LibraryQueryToken.Field] = [
            .rating, .flag, .keyword, .folder, .camera, .lens, .iso,
            .dateFrom, .dateBefore, .color, .source, .signal,
            .xmpPending, .xmpConflict
        ]
        XCTAssertEqual(LibraryQueryToken.tokens(from: fullyFilteredModel()).map(\.field), allFields)

        for field in allFields {
            let model = fullyFilteredModel()
            guard let token = LibraryQueryToken.tokens(from: model).first(where: { $0.field == field }) else {
                XCTFail("expected a \(field) token")
                continue
            }

            LibraryQueryToken.remove(token, from: model)

            let remaining = LibraryQueryToken.tokens(from: model).map(\.field)
            XCTAssertEqual(
                remaining,
                allFields.filter { $0 != field },
                "removing \(field) should clear exactly that filter"
            )
        }
    }

    func testRemovingTokenClearsOnlyThatFilter() {
        let model = makeModel()
        model.minimumRatingFilter = 3
        model.flagFilter = .pick
        model.keywordFilterText = "portfolio"

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let ratingToken = tokens.first(where: { $0.field == .rating }) else {
            return XCTFail("expected a rating token")
        }

        LibraryQueryToken.remove(ratingToken, from: model)

        XCTAssertNil(model.minimumRatingFilter)
        XCTAssertEqual(model.flagFilter, .pick)
        XCTAssertEqual(model.keywordFilterText, "portfolio")
    }

    func testRemovingFlagTokenLeavesRatingAndKeywordIntact() {
        let model = makeModel()
        model.minimumRatingFilter = 3
        model.flagFilter = .pick
        model.keywordFilterText = "portfolio"

        let tokens = LibraryQueryToken.tokens(from: model)
        guard let flagToken = tokens.first(where: { $0.field == .flag }) else {
            return XCTFail("expected a flag token")
        }

        LibraryQueryToken.remove(flagToken, from: model)

        XCTAssertNil(model.flagFilter)
        XCTAssertEqual(model.minimumRatingFilter, 3)
        XCTAssertEqual(model.keywordFilterText, "portfolio")
    }

    // MARK: - Mixed free text parse

    func testMixedFreeTextParsesToTwoTokensAndResidual() {
        let model = makeModel()
        let result = LibraryQueryToken.parse("person:\"Maya\" rating:3 golden hour", applyingTo: model)

        XCTAssertEqual(result.recognizedTokens.count, 2)
        XCTAssertEqual(result.freeText, "golden hour")
        XCTAssertEqual(model.minimumRatingFilter, 3)
        // person: has no structured AppModel property; it stays inside librarySearchText.
        XCTAssertTrue(model.librarySearchText.contains("person:Maya"))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
}
