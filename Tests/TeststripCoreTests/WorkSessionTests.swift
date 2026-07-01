import XCTest
@testable import TeststripCore

final class WorkSessionTests: XCTestCase {
    func testWorkSessionReferencesSetsInsteadOfOwningMembership() {
        let input = AssetSetID(rawValue: "input")
        let output = AssetSetID(rawValue: "accepted")
        let session = WorkSession(
            id: WorkSessionID(rawValue: "session-1"),
            kind: .culling,
            intent: "one hero per burst",
            status: .running,
            inputSetIDs: [input],
            outputSetIDs: [output],
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 11)
        )

        XCTAssertEqual(session.inputSetIDs, [input])
        XCTAssertEqual(session.outputSetIDs, [output])
        XCTAssertEqual(session.intent, "one hero per burst")
    }
}
