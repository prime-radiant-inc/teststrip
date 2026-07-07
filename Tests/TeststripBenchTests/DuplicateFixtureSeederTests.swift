import CryptoKit
import XCTest
import TeststripCore
@testable import TeststripBench

final class DuplicateFixtureSeederTests: XCTestCase {
    func testSeedDupFixturesCommandParsesDirectory() throws {
        let command = BenchmarkCommand.parse(["TeststripBench", "seed-dup-fixtures", "/tmp/dup"])
        XCTAssertEqual(command, .seedDupFixtures(directory: URL(fileURLWithPath: "/tmp/dup")))
    }

    func testCard2SharesByteIdenticalFramesAndAddsNewOnes() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = try DuplicateFixtureSeeder(directory: directory).run()

        let card1 = directory.appendingPathComponent("card1", isDirectory: true)
        let card2 = directory.appendingPathComponent("card2", isDirectory: true)
        let card1Files = try jpegFiles(in: card1)
        let card2Files = try jpegFiles(in: card2)

        XCTAssertEqual(card1Files.count, result.card1FrameCount)
        XCTAssertEqual(card2Files.count, result.card2FrameCount)
        XCTAssertEqual(result.card2FrameCount, result.sharedFrameCount + result.card2NewFrameCount)

        let card1Hashes = try card1Files.reduce(into: [String: String]()) { table, url in
            table[url.lastPathComponent] = try sha256(of: url)
        }
        let card1HashSet = Set(card1Hashes.values)

        var shared = 0
        var brandNew = 0
        for file in card2Files {
            let hash = try sha256(of: file)
            if let card1Hash = card1Hashes[file.lastPathComponent] {
                XCTAssertEqual(hash, card1Hash, "shared frame \(file.lastPathComponent) must be byte-identical")
                shared += 1
            } else {
                XCTAssertFalse(card1HashSet.contains(hash), "new frame must not duplicate a card1 hash")
                brandNew += 1
            }
        }
        XCTAssertEqual(shared, result.sharedFrameCount)
        XCTAssertEqual(brandNew, result.card2NewFrameCount)
    }

    private func jpegFiles(in directory: URL) throws -> [URL] {
        try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func sha256(of url: URL) throws -> String {
        let digest = SHA256.hash(data: try Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-dup-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
