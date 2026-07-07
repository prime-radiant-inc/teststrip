import Foundation
import XCTest
@testable import TeststripCore

final class RejectRelocationServiceTests: XCTestCase {
    func testPlannerPreservesStructureBeneathCommonAncestor() throws {
        let planner = RejectRelocationPlanner(destinationRoot: URL(fileURLWithPath: "/Rejects"))
        let plans = planner.plan(originals: [
            URL(fileURLWithPath: "/Shoot/Day1/a.cr2"),
            URL(fileURLWithPath: "/Shoot/Day2/b.cr2")
        ])
        XCTAssertEqual(plans, [
            RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/Day1/a.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/Day1/a.cr2")
            ),
            RejectRelocationPlan(
                originalFrom: URL(fileURLWithPath: "/Shoot/Day2/b.cr2"),
                originalTo: URL(fileURLWithPath: "/Rejects/Day2/b.cr2")
            )
        ])
    }

    func testPlannerSingleFolderIsEffectivelyFlat() throws {
        let planner = RejectRelocationPlanner(destinationRoot: URL(fileURLWithPath: "/Rejects"))
        let plans = planner.plan(originals: [
            URL(fileURLWithPath: "/Shoot/a.cr2"),
            URL(fileURLWithPath: "/Shoot/b.cr2")
        ])
        XCTAssertEqual(plans.map(\.originalTo), [
            URL(fileURLWithPath: "/Rejects/a.cr2"),
            URL(fileURLWithPath: "/Rejects/b.cr2")
        ])
    }

    func testPlannerDisambiguatesCollidingBasenames() throws {
        let planner = RejectRelocationPlanner(destinationRoot: URL(fileURLWithPath: "/Rejects"))
        // Both share the common ancestor /Shoot, so both flatten to the same basename.
        let plans = planner.plan(originals: [
            URL(fileURLWithPath: "/Shoot/x.cr2"),
            URL(fileURLWithPath: "/Shoot/x.cr2")
        ])
        XCTAssertEqual(plans.map(\.originalTo), [
            URL(fileURLWithPath: "/Rejects/x.cr2"),
            URL(fileURLWithPath: "/Rejects/x-2.cr2")
        ])
    }

    func testMoveRelocatesOriginalAndSidecarTogether() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "reject-move-pair")
        let source = directory.appendingPathComponent("shoot")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let originalFrom = source.appendingPathComponent("frame.cr2")
        let sidecarFrom = source.appendingPathComponent("frame.cr2.xmp")
        try Data("raw".utf8).write(to: originalFrom)
        try Data("<xmp/>".utf8).write(to: sidecarFrom)
        let originalTo = directory.appendingPathComponent("rejects/frame.cr2")

        let result = try RejectRelocationService().move(originalFrom: originalFrom, originalTo: originalTo)

        XCTAssertFalse(FileManager.default.fileExists(atPath: originalFrom.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecarFrom.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalTo.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.sidecarTo?.path ?? "/missing"))
        XCTAssertEqual(result.originalFrom, originalFrom)
        XCTAssertEqual(result.originalTo, originalTo)
        XCTAssertEqual(result.sidecarFrom, sidecarFrom)
    }

    func testMoveWithoutSidecarLeavesSidecarFieldsNil() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "reject-move-solo")
        let originalFrom = directory.appendingPathComponent("solo.jpg")
        try Data("jpeg".utf8).write(to: originalFrom)
        let originalTo = directory.appendingPathComponent("rejects/solo.jpg")

        let result = try RejectRelocationService().move(originalFrom: originalFrom, originalTo: originalTo)

        XCTAssertNil(result.sidecarFrom)
        XCTAssertNil(result.sidecarTo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalTo.path))
    }

    func testMoveBackRestoresBothFiles() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "reject-move-back")
        let rejects = directory.appendingPathComponent("rejects")
        try FileManager.default.createDirectory(at: rejects, withIntermediateDirectories: true)
        let originalTo = rejects.appendingPathComponent("frame.cr2")
        let sidecarTo = rejects.appendingPathComponent("frame.cr2.xmp")
        try Data("raw".utf8).write(to: originalTo)
        try Data("<xmp/>".utf8).write(to: sidecarTo)
        let entry = RelocationManifestEntry(
            assetID: AssetID(rawValue: "back"),
            originalFrom: directory.appendingPathComponent("shoot/frame.cr2"),
            originalTo: originalTo,
            sidecarFrom: directory.appendingPathComponent("shoot/frame.cr2.xmp"),
            sidecarTo: sidecarTo
        )

        try RejectRelocationService().moveBack(entry)

        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.originalFrom.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(entry.sidecarFrom).path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalTo.path))
    }
}
