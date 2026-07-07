import Foundation
import TeststripCore

public struct DuplicateFixtureSeederResult: Equatable {
    public var card1FrameCount: Int
    public var sharedFrameCount: Int
    public var card2NewFrameCount: Int
    public var card2FrameCount: Int

    public init(card1FrameCount: Int, sharedFrameCount: Int, card2NewFrameCount: Int) {
        self.card1FrameCount = card1FrameCount
        self.sharedFrameCount = sharedFrameCount
        self.card2NewFrameCount = card2NewFrameCount
        self.card2FrameCount = sharedFrameCount + card2NewFrameCount
    }
}

/// Writes `card1/` and `card2/` for the `duplicate-detection-import-new-only`
/// card. `card2` holds byte-identical copies of every `card1` frame (via
/// `FileManager.copyItem`, never a re-encode, so the content hashes match) plus
/// a set of brand-new distinct frames.
public struct DuplicateFixtureSeeder {
    public var directory: URL
    public var card1FrameCount: Int
    public var newFrameCount: Int

    public init(directory: URL, card1FrameCount: Int = 4, newFrameCount: Int = 2) {
        self.directory = directory
        self.card1FrameCount = card1FrameCount
        self.newFrameCount = newFrameCount
    }

    public func run() throws -> DuplicateFixtureSeederResult {
        let card1 = directory.appendingPathComponent("card1", isDirectory: true)
        let card2 = directory.appendingPathComponent("card2", isDirectory: true)
        try FileManager.default.createDirectory(at: card1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: card2, withIntermediateDirectories: true)

        for index in 0..<card1FrameCount {
            let name = String(format: "FRAME_%04d.jpg", index)
            let source = card1.appendingPathComponent(name)
            try BenchmarkImageFixtures.writeJPEG(to: source, index: index)
            try FileManager.default.copyItem(at: source, to: card2.appendingPathComponent(name))
        }

        for offset in 0..<newFrameCount {
            let index = card1FrameCount + offset
            let name = String(format: "NEW_%04d.jpg", index)
            try BenchmarkImageFixtures.writeJPEG(to: card2.appendingPathComponent(name), index: index)
        }

        return DuplicateFixtureSeederResult(
            card1FrameCount: card1FrameCount,
            sharedFrameCount: card1FrameCount,
            card2NewFrameCount: newFrameCount
        )
    }
}
