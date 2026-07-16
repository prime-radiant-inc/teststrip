import XCTest
@testable import TeststripCore

final class AssetBondPlannerTests: XCTestCase {
    private func input(_ id: String, _ path: String) -> AssetBondPlanner.BondInput {
        AssetBondPlanner.BondInput(id: AssetID(rawValue: id), originalURL: URL(fileURLWithPath: path))
    }

    func testBondsWorkingStillToRawBySameFolderAndStem() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("raw", "/photos/IMG_1.CR3"),
            input("jpg", "/photos/IMG_1.JPG"),
        ])
        XCTAssertEqual(bonds, [AssetID(rawValue: "jpg"): AssetID(rawValue: "raw")])
    }

    func testBondsBothWorkingStillsToTheRaw() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("raw", "/p/IMG_1.CR3"),
            input("jpg", "/p/IMG_1.JPG"),
            input("heic", "/p/IMG_1.HEIC"),
        ])
        XCTAssertEqual(bonds, [
            AssetID(rawValue: "jpg"): AssetID(rawValue: "raw"),
            AssetID(rawValue: "heic"): AssetID(rawValue: "raw"),
        ])
    }

    func testNoRawInStemGroupProducesNoBonds() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("a", "/p/IMG_1.JPG"),
            input("b", "/p/IMG_1.HEIC"),
        ])
        XCTAssertTrue(bonds.isEmpty)
    }

    func testDifferentFoldersDoNotBond() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("raw", "/a/IMG_1.CR3"),
            input("jpg", "/b/IMG_1.JPG"),
        ])
        XCTAssertTrue(bonds.isEmpty)
    }

    func testMultipleRawsNeverHideARaw() {
        // Two RAWs + one still sharing a stem: the still bonds to a deterministic
        // primary RAW; neither RAW is bonded (a RAW is never a hidden secondary).
        let bonds = AssetBondPlanner.bonds(for: [
            input("cr3", "/p/IMG_1.CR3"),
            input("dng", "/p/IMG_1.DNG"),
            input("jpg", "/p/IMG_1.JPG"),
        ])
        XCTAssertNil(bonds[AssetID(rawValue: "cr3")])
        XCTAssertNil(bonds[AssetID(rawValue: "dng")])
        // still bonds to the first RAW by sorted original_path (/p/IMG_1.CR3 < /p/IMG_1.DNG)
        XCTAssertEqual(bonds[AssetID(rawValue: "jpg")], AssetID(rawValue: "cr3"))
    }

    func testCaseInsensitiveStemAndExtension() {
        let bonds = AssetBondPlanner.bonds(for: [
            input("raw", "/p/img_1.cr3"),
            input("jpg", "/p/IMG_1.jpg"),
        ])
        XCTAssertEqual(bonds, [AssetID(rawValue: "jpg"): AssetID(rawValue: "raw")])
    }
}
