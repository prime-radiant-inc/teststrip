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

    func testColonIsEscapedOutOfTheFileName() {
        let cache = ContactPhotoCache(root: URL(fileURLWithPath: "/tmp/contacts"))
        let name = cache.url(for: "A:B").lastPathComponent

        // An unescaped implementation would produce the literal file name
        // "A:B.jpg", which contains the raw ":" — this goes red against that.
        XCTAssertFalse(name.contains(":"))
    }

    func testSlashDoesNotSplitIntoExtraPathComponents() {
        let root = URL(fileURLWithPath: "/tmp/contacts")
        let cache = ContactPhotoCache(root: root)
        let url = cache.url(for: "A/B")

        // An unescaped implementation would pass "A/B.jpg" straight to
        // appendingPathComponent, which treats "/" as a separator and
        // creates two extra components ("A", "B.jpg") instead of one.
        XCTAssertEqual(url.pathComponents.count, root.pathComponents.count + 1)
    }

    func testDistinctRawCharactersThatCollideWhenEscapingIsNaiveProduceDistinctURLs() {
        let cache = ContactPhotoCache(root: URL(fileURLWithPath: "/tmp/contacts"))

        // A naive scheme that maps every disallowed character to the same
        // placeholder (e.g. ":" -> "_") would make these collide.
        XCTAssertNotEqual(
            cache.url(for: "A:B").lastPathComponent,
            cache.url(for: "A_B").lastPathComponent
        )
    }
}
