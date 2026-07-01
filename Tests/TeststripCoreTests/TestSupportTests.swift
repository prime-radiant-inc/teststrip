import XCTest
@testable import TeststripCore

final class TestSupportTests: XCTestCase {
    func testTemporaryDirectoryCreatesUniqueFolders() throws {
        let first = try TestDirectories.makeTemporaryDirectory(named: "support")
        let second = try TestDirectories.makeTemporaryDirectory(named: "support")

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertNotEqual(first, second)
    }

    func testTeststripErrorHasStableMessage() {
        let error = TeststripError.invalidState("catalog is closed")

        XCTAssertEqual(error.errorDescription, "catalog is closed")
    }
}
