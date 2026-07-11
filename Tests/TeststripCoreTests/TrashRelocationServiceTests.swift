import Foundation
import XCTest
@testable import TeststripCore

/// A `Recycler` fake that "trashes" files by moving them into a temp
/// directory standing in for the Trash, so tests never touch the real
/// Finder Trash.
private struct FakeRecycler: Recycler {
    let trashDirectory: URL

    func trash(_ url: URL) throws -> URL {
        try FileManager.default.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        // Mirror real Trash behavior: disambiguate name collisions rather
        // than overwrite.
        var candidate = trashDirectory.appendingPathComponent(url.lastPathComponent)
        var suffix = 2
        let baseName = (url.lastPathComponent as NSString).deletingPathExtension
        let ext = (url.lastPathComponent as NSString).pathExtension
        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(baseName) \(suffix)" : "\(baseName) \(suffix).\(ext)"
            candidate = trashDirectory.appendingPathComponent(name)
            suffix += 1
        }
        try FileManager.default.moveItem(at: url, to: candidate)
        return candidate
    }
}

/// A `Recycler` fake that always fails, for exercising abort/skip paths.
private struct FailingRecycler: Recycler {
    func trash(_ url: URL) throws -> URL {
        throw TeststripError.io("fake trash failure for \(url.path)")
    }
}

final class TrashRelocationServiceTests: XCTestCase {
    private func makeAsset(id: String, originalURL: URL) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: originalURL,
            volumeIdentifier: "TestVolume",
            fingerprint: FileFingerprint(size: 3, modificationDate: Date(timeIntervalSince1970: 0), contentHash: "abc"),
            availability: .online,
            metadata: AssetMetadata(rating: 3, colorLabel: .green, flag: .reject, keywords: ["a"])
        )
    }

    func testTrashMovesOriginalAndSidecarViaInjectedRecycler() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "trash-move-pair")
        let source = directory.appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let originalFrom = source.appendingPathComponent("frame.cr2")
        let sidecarFrom = source.appendingPathComponent("frame.cr2.xmp")
        try Data("raw".utf8).write(to: originalFrom)
        try Data("<xmp/>".utf8).write(to: sidecarFrom)
        let trashDirectory = directory.appendingPathComponent("fake-trash")
        let recycler = FakeRecycler(trashDirectory: trashDirectory)

        let result = try RejectRelocationService().trash(originalFrom: originalFrom, recycler: recycler)

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFrom.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarFrom.path))
        XCTAssertEqual(result.originalTo, trashDirectory.appendingPathComponent("frame.cr2"))
        XCTAssertEqual(result.sidecarTo, trashDirectory.appendingPathComponent("frame.cr2.xmp"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.originalTo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(result.sidecarTo).path))
    }

    func testTrashWithoutSidecarLeavesSidecarFieldsNil() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "trash-move-solo")
        let originalFrom = directory.appendingPathComponent("solo.jpg")
        try Data("jpeg".utf8).write(to: originalFrom)
        let trashDirectory = directory.appendingPathComponent("fake-trash")
        let recycler = FakeRecycler(trashDirectory: trashDirectory)

        let result = try RejectRelocationService().trash(originalFrom: originalFrom, recycler: recycler)

        XCTAssertNil(result.sidecarFrom)
        XCTAssertNil(result.sidecarTo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.originalTo.path))
    }

    func testTrashFailureLeavesSidecarUntrashed() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "trash-move-fail")
        let source = directory.appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let originalFrom = source.appendingPathComponent("frame.cr2")
        let sidecarFrom = source.appendingPathComponent("frame.cr2.xmp")
        try Data("raw".utf8).write(to: originalFrom)
        try Data("<xmp/>".utf8).write(to: sidecarFrom)

        XCTAssertThrowsError(try RejectRelocationService().trash(originalFrom: originalFrom, recycler: FailingRecycler()))

        // The failed original trash must not leave the sidecar orphaned in
        // whatever the recycler's staging area was — it stays exactly where
        // it started.
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalFrom.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecarFrom.path))
    }

    func testManifestEntryRecordsResultingTrashURLsAndAssetSnapshot() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "trash-manifest")
        let originalFrom = directory.appendingPathComponent("frame.cr2")
        try Data("raw".utf8).write(to: originalFrom)
        let trashDirectory = directory.appendingPathComponent("fake-trash")
        let recycler = FakeRecycler(trashDirectory: trashDirectory)
        let asset = makeAsset(id: "asset-1", originalURL: originalFrom)

        let result = try RejectRelocationService().trash(originalFrom: originalFrom, recycler: recycler)
        let entry = RelocationManifestEntry(
            assetID: asset.id,
            originalFrom: result.originalFrom,
            originalTo: result.originalTo,
            sidecarFrom: result.sidecarFrom,
            sidecarTo: result.sidecarTo,
            assetSnapshot: asset
        )

        XCTAssertEqual(entry.originalTo, trashDirectory.appendingPathComponent("frame.cr2"))
        XCTAssertEqual(entry.assetSnapshot, asset)
    }

    func testMoveBackFromTrashRestoresOriginalAndSidecar() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "trash-move-back")
        let trash = directory.appendingPathComponent("fake-trash")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        let originalTo = trash.appendingPathComponent("frame.cr2")
        let sidecarTo = trash.appendingPathComponent("frame.cr2.xmp")
        try Data("raw".utf8).write(to: originalTo)
        try Data("<xmp/>".utf8).write(to: sidecarTo)
        let entry = RelocationManifestEntry(
            assetID: AssetID(rawValue: "back"),
            originalFrom: directory.appendingPathComponent("shoot/frame.cr2"),
            originalTo: originalTo,
            sidecarFrom: directory.appendingPathComponent("shoot/frame.cr2.xmp"),
            sidecarTo: sidecarTo,
            assetSnapshot: makeAsset(id: "back", originalURL: directory.appendingPathComponent("shoot/frame.cr2"))
        )

        try RejectRelocationService().moveBack(entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.originalFrom.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(entry.sidecarFrom).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalTo.path))
    }

    func testMoveBackWhenTrashURLNoLongerExistsIsReportedAsUnrecoverable() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "trash-move-back-gone")
        let entry = RelocationManifestEntry(
            assetID: AssetID(rawValue: "gone"),
            originalFrom: directory.appendingPathComponent("shoot/frame.cr2"),
            originalTo: directory.appendingPathComponent("fake-trash/frame.cr2"),
            sidecarFrom: nil,
            sidecarTo: nil,
            assetSnapshot: makeAsset(id: "gone", originalURL: directory.appendingPathComponent("shoot/frame.cr2"))
        )

        // The user emptied the Trash: the resulting URL is gone. moveBack
        // must not throw — it's a no-op restoration, reported upstream (by
        // the caller comparing before/after fileExists) as unrecoverable.
        try RejectRelocationService().moveBack(entry)

        XCTAssertFalse(FileManager.default.fileExists(atPath: entry.originalFrom.path))
    }

    // Integration test against the real Trash. Skips gracefully if the temp
    // volume doesn't support trashItem (e.g. some CI sandboxes / network
    // volumes reject FSEventsD-backed trashing).
    func testRealFileManagerTrashItemIntegration() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "trash-real-integration")
        let originalFrom = directory.appendingPathComponent("real.jpg")
        try Data("jpeg".utf8).write(to: originalFrom)

        let result: RejectRelocationMoveResult
        do {
            result = try RejectRelocationService().trash(originalFrom: originalFrom, recycler: FileManagerRecycler())
        } catch {
            throw XCTSkip("volume does not support FileManager.trashItem: \(error)")
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFrom.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.originalTo.path))
        try? FileManager.default.removeItem(at: result.originalTo)
    }
}
