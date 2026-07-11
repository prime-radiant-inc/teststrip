import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TeststripCore
@testable import TeststripApp

// Jesse's ruling (2026-07-11): before writing, the export flow detects
// filename collisions in the destination and asks ONCE per batch —
// Replace All / Keep Both / Cancel. These tests cover the AppModel plumbing
// (detection over catalog assets, resolution threaded to ExportService) and
// the prompt presentation text.
final class ExportCollisionPromptTests: XCTestCase {
    @MainActor
    func testExportCollisionFilenamesReportsPlannedOutputsAlreadyInDestination() throws {
        let directory = try makeTemporaryDirectory(named: "collision-detect")
        let colliding = makeAsset(id: "col-1", path: "/Photos/Job/photo.cr2")
        let fresh = makeAsset(id: "col-2", path: "/Photos/Job/fresh.cr2")
        let (model, _) = try makeModelWithCatalogAssets(
            directory: directory,
            assets: [colliding, fresh]
        )
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        // Extension comes from the export format, so photo.cr2 -> photo.jpg.
        try Data("existing".utf8).write(to: destination.appendingPathComponent("photo.jpg"))

        let collisions = try model.exportCollisionFilenames(
            assetIDs: [colliding.id, fresh.id],
            format: .jpeg,
            destinationFolder: destination
        )

        XCTAssertEqual(collisions, ["photo.jpg"])
    }

    @MainActor
    func testExportVisibleAssetsWithReplaceAllOverwritesCollidingFile() async throws {
        let directory = try makeTemporaryDirectory(named: "collision-replace")
        let sourceURL = directory.appendingPathComponent("photo.jpg")
        try Self.writeJPEG(to: sourceURL, width: 64, height: 48)
        let asset = makeAsset(id: "replace-1", path: sourceURL.path)
        let (model, _) = try makeModelWithCatalogAssets(directory: directory, assets: [asset])
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existing = destination.appendingPathComponent("photo.jpg")
        try Self.writeJPEG(to: existing, width: 8, height: 8)

        let summary = try await model.exportVisibleAssets(
            settings: ExportSettings(jpegQuality: 0.8),
            destinationFolder: destination,
            collisionResolution: .replaceAll
        )

        XCTAssertEqual(summary.exportedCount, 1)
        let names = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        XCTAssertEqual(names, ["photo.jpg"])
        let dimensions = try PreviewRenderer().dimensions(of: existing)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 64, height: 48))
    }

    func testPromptMessageNamesCountAndBothResolutions() {
        let prompt = ExportCollisionPrompt(
            destinationFolder: URL(fileURLWithPath: "/tmp/Delivery"),
            settings: ExportSettings(jpegQuality: 0.8),
            scope: .visible,
            collidingFilenames: ["a.jpg", "b.jpg"]
        )
        XCTAssertEqual(
            prompt.message,
            "2 files with the same name already exist in Delivery. Replace All overwrites them; Keep Both saves new copies with -2, -3, … names."
        )
        let single = ExportCollisionPrompt(
            destinationFolder: URL(fileURLWithPath: "/tmp/Delivery"),
            settings: ExportSettings(jpegQuality: 0.8),
            scope: .visible,
            collidingFilenames: ["a.jpg"]
        )
        XCTAssertTrue(single.message.hasPrefix("1 file with the same name already exist"))
    }

    // MARK: - Fixtures

    private func makeAsset(id: String, path: String) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 1, modificationDate: Date(timeIntervalSince1970: 1)),
            availability: .online,
            metadata: AssetMetadata()
        )
    }

    private static func writeJPEG(to url: URL, width: Int, height: Int) throws {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.4, green: 0.5, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw TeststripError.io("could not write test JPEG to \(url.path)")
        }
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func makeModelWithCatalogAssets(
        directory: URL,
        assets: [Asset]
    ) throws -> (AppModel, CatalogRepository) {
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        try repository.upsert(assets)
        let previewCache = PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
        let catalog = AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: previewCache,
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: previewCache
            )
        )
        let model = try AppModel.load(catalog: catalog)
        return (model, repository)
    }
}
