import XCTest
@testable import TeststripCore

final class ContentHashTests: XCTestCase {
    private func makeDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-content-hash-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testIdenticalContentUnderDifferentNamesHashesTheSame() throws {
        let root = try makeDirectory(named: "identical")
        let bytes = Data((0..<10_000).map { UInt8($0 & 0xFF) })
        let first = root.appendingPathComponent("IMG_0001.CR2")
        let second = root.appendingPathComponent("renamed.CR2")
        try bytes.write(to: first)
        try bytes.write(to: second)

        XCTAssertEqual(
            try ContentHash.compute(forFileAt: first),
            try ContentHash.compute(forFileAt: second)
        )
    }

    func testDifferentContentHashesDifferently() throws {
        let root = try makeDirectory(named: "different")
        let first = root.appendingPathComponent("a.jpg")
        let second = root.appendingPathComponent("b.jpg")
        try Data((0..<10_000).map { UInt8($0 & 0xFF) }).write(to: first)
        try Data((0..<10_000).map { UInt8(($0 &+ 1) & 0xFF) }).write(to: second)

        XCTAssertNotEqual(
            try ContentHash.compute(forFileAt: first),
            try ContentHash.compute(forFileAt: second)
        )
    }

    func testFileSmallerThanTwoChunksHashesWholeContent() throws {
        let root = try makeDirectory(named: "small")
        // When the file is no larger than two chunks the head and tail windows
        // would overlap, so the whole file is hashed. Two same-length files
        // sharing head and tail but differing only in the middle must still
        // hash differently.
        let first = root.appendingPathComponent("first.raw")
        let second = root.appendingPathComponent("second.raw")
        try Data("HEAD_M1_TAIL".utf8).write(to: first)
        try Data("HEAD_M2_TAIL".utf8).write(to: second)

        XCTAssertNotEqual(
            try ContentHash.compute(forFileAt: first, chunkByteCount: 1_000),
            try ContentHash.compute(forFileAt: second, chunkByteCount: 1_000)
        )
    }

    func testHeadDifferenceChangesHashWithBoundedChunks() throws {
        let root = try makeDirectory(named: "head")
        let first = root.appendingPathComponent("first.raw")
        let second = root.appendingPathComponent("second.raw")
        try Data("HEAD01_the_unread_middle_bytes_TAIL01".utf8).write(to: first)
        try Data("HEADXX_the_unread_middle_bytes_TAIL01".utf8).write(to: second)

        XCTAssertNotEqual(
            try ContentHash.compute(forFileAt: first, chunkByteCount: 6),
            try ContentHash.compute(forFileAt: second, chunkByteCount: 6)
        )
    }

    func testTailDifferenceChangesHashWithBoundedChunks() throws {
        let root = try makeDirectory(named: "tail")
        let first = root.appendingPathComponent("first.raw")
        let second = root.appendingPathComponent("second.raw")
        try Data("HEAD01_the_unread_middle_bytes_TAIL01".utf8).write(to: first)
        try Data("HEAD01_the_unread_middle_bytes_TAILXX".utf8).write(to: second)

        XCTAssertNotEqual(
            try ContentHash.compute(forFileAt: first, chunkByteCount: 6),
            try ContentHash.compute(forFileAt: second, chunkByteCount: 6)
        )
    }

    func testSizeDifferenceChangesHashEvenWhenHeadAndTailMatch() throws {
        let root = try makeDirectory(named: "size")
        // Both share the same head and tail chunks; only the (unread) middle
        // length differs. Folding the file size into the digest is what keeps
        // these distinct despite the head/tail-only read.
        let head = "HEAD01"
        let tail = "TAIL01"
        let first = root.appendingPathComponent("first.raw")
        let second = root.appendingPathComponent("second.raw")
        try Data((head + "MIDDLE" + tail).utf8).write(to: first)
        try Data((head + "MIDDLE_LONGER" + tail).utf8).write(to: second)

        XCTAssertNotEqual(
            try ContentHash.compute(forFileAt: first, chunkByteCount: 6),
            try ContentHash.compute(forFileAt: second, chunkByteCount: 6)
        )
    }

    func testEmptyFileHashesWithoutError() throws {
        let root = try makeDirectory(named: "empty")
        let url = root.appendingPathComponent("empty.raw")
        try Data().write(to: url)

        XCTAssertFalse(try ContentHash.compute(forFileAt: url).isEmpty)
    }

    func testMissingFileThrowsIOError() throws {
        let root = try makeDirectory(named: "missing")
        let url = root.appendingPathComponent("nope.raw")

        XCTAssertThrowsError(try ContentHash.compute(forFileAt: url)) { error in
            guard case TeststripError.io = error else {
                return XCTFail("expected IO error, got \(error)")
            }
        }
    }

    func testHashIsStableAcrossRepeatedComputation() throws {
        let root = try makeDirectory(named: "stable")
        let url = root.appendingPathComponent("photo.jpg")
        try Data((0..<200_000).map { UInt8($0 & 0xFF) }).write(to: url)

        XCTAssertEqual(
            try ContentHash.compute(forFileAt: url),
            try ContentHash.compute(forFileAt: url)
        )
    }
}
