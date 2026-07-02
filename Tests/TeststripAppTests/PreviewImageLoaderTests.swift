import XCTest
@testable import TeststripApp

final class PreviewImageLoaderTests: XCTestCase {
    func testLoadDataReadsPreviewBytes() async throws {
        let directory = try makeTemporaryDirectory(named: "preview-loader")
        let previewURL = directory.appendingPathComponent("preview.jpg")
        let expected = Data([0x01, 0x02, 0x03])
        try expected.write(to: previewURL)

        let loaded = await PreviewImageDataLoader.loadData(from: previewURL)

        XCTAssertEqual(loaded, expected)
    }

    func testLoadDataReturnsNilForMissingPreview() async throws {
        let directory = try makeTemporaryDirectory(named: "preview-loader-missing")
        let previewURL = directory.appendingPathComponent("missing.jpg")

        let loaded = await PreviewImageDataLoader.loadData(from: previewURL)

        XCTAssertNil(loaded)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
