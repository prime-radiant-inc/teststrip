import XCTest
import TeststripCore
@testable import TeststripApp

final class PersonAutocompletePresentationTests: XCTestCase {
    private let candidates = [
        PersonCandidate(id: "p1", name: "Ann Lee", similarityPercent: 90),
        PersonCandidate(id: "p2", name: "Bob", similarityPercent: 40),
    ]

    func testEmptyQueryReturnsAllPeopleInOrderNoCreateRow() {
        let rows = PersonAutocompletePresentation.rows(candidates: candidates, query: "")
        XCTAssertEqual(rows.map(\.kind), [.person(candidates[0]), .person(candidates[1])])
    }

    func testSubstringFilterPreservesOrderAndAddsCreateRow() {
        let rows = PersonAutocompletePresentation.rows(candidates: candidates, query: "an")
        // "an" matches "Ann Lee" only; "an" is not an exact name → a create row appears.
        XCTAssertEqual(rows, [
            PersonAutocompleteRow(kind: .person(candidates[0])),
            PersonAutocompleteRow(kind: .create(name: "an")),
        ])
    }

    func testExactExistingNameSuppressesCreateRow() {
        let rows = PersonAutocompletePresentation.rows(candidates: candidates, query: "bob")
        XCTAssertEqual(rows, [PersonAutocompleteRow(kind: .person(candidates[1]))]) // no create row
    }

    func testWhitespaceOnlyQueryReturnsAllPeopleInOrderNoCreateRow() {
        let rows = PersonAutocompletePresentation.rows(candidates: candidates, query: "   ")
        XCTAssertEqual(rows.map(\.kind), [.person(candidates[0]), .person(candidates[1])])
    }

    func testFocusIndexWraps() {
        XCTAssertEqual(PersonAutocompletePresentation.clampedFocusIndex(-1, rowCount: 3), 2)
        XCTAssertEqual(PersonAutocompletePresentation.clampedFocusIndex(3, rowCount: 3), 0)
        XCTAssertEqual(PersonAutocompletePresentation.clampedFocusIndex(5, rowCount: 0), 0)
    }
}
