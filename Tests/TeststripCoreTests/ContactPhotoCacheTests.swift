import XCTest
@testable import TeststripCore

final class ContactPhotoCacheTests: XCTestCase {
    func testURLIsStableAndUnderRoot() {
        let root = URL(fileURLWithPath: "/tmp/contacts")
        let cache = ContactPhotoCache(root: root)
        let a = cache.url(for: "ABC:123/xyz")
        XCTAssertEqual(a, cache.url(for: "ABC:123/xyz"))       // stable
        XCTAssertTrue(a.path.hasPrefix(root.path))             // under root
        XCTAssertTrue(a.pathExtension == "jpg")
    }

    func testDistinctIdentifiersDistinctURLs() {
        let cache = ContactPhotoCache(root: URL(fileURLWithPath: "/tmp/contacts"))
        XCTAssertNotEqual(cache.url(for: "A"), cache.url(for: "B"))
    }
}
