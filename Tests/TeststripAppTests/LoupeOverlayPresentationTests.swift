import XCTest
@testable import TeststripApp
import TeststripCore

final class LoupeOverlayPresentationTests: XCTestCase {

    // MARK: - ExifOverlayLevel cycle

    func testExifOverlayLevelCyclesOffExposureLineFullAndWraps() {
        XCTAssertEqual(ExifOverlayLevel.off.next(), .exposureLine)
        XCTAssertEqual(ExifOverlayLevel.exposureLine.next(), .full)
        XCTAssertEqual(ExifOverlayLevel.full.next(), .off)
    }

    func testCycleExifOverlayLevelShortcutAdvancesModelState() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "exif", size: 1)])

        XCTAssertEqual(model.exifOverlayLevel, .off)

        try model.applyCullingShortcut(.cycleExifOverlay)
        XCTAssertEqual(model.exifOverlayLevel, .exposureLine)

        try model.applyCullingShortcut(.cycleExifOverlay)
        XCTAssertEqual(model.exifOverlayLevel, .full)

        try model.applyCullingShortcut(.cycleExifOverlay)
        XCTAssertEqual(model.exifOverlayLevel, .off)
    }

    func testLoupeExifOverlayPresentationLinesGrowByLevel() {
        let metadata = AssetTechnicalMetadata(
            pixelWidth: 4000,
            pixelHeight: 3000,
            cameraMake: "Fujifilm",
            cameraModel: "X-T5",
            isoSpeed: 200,
            aperture: 2.8,
            shutterSpeed: 1.0 / 250,
            focalLength: 35,
            latitude: 37.7749,
            longitude: -122.4194,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )

        XCTAssertEqual(LoupeExifOverlayPresentation(technicalMetadata: metadata, level: .off).lines, [])

        let exposureLines = LoupeExifOverlayPresentation(technicalMetadata: metadata, level: .exposureLine).lines
        XCTAssertEqual(exposureLines.count, 1)

        let fullLines = LoupeExifOverlayPresentation(technicalMetadata: metadata, level: .full).lines
        XCTAssertGreaterThan(fullLines.count, exposureLines.count)
        XCTAssertTrue(fullLines.contains("4000 × 3000"))
    }

    func testShowKeyMapShortcutTogglesOverlayVisibility() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "keymap", size: 1)])

        XCTAssertFalse(model.isKeyMapOverlayVisible)

        try model.applyCullingShortcut(.showKeyMap)
        XCTAssertTrue(model.isKeyMapOverlayVisible)

        try model.applyCullingShortcut(.showKeyMap)
        XCTAssertFalse(model.isKeyMapOverlayVisible)
    }

    func testQuestionMarkCharacterMapsToShowKeyMapShortcut() {
        XCTAssertEqual(CullingShortcut(key: .character("?")), .showKeyMap)
    }

    // MARK: - Face-cycle index wraps

    func testNearestFaceIndexPicksClosestFaceToReferenceFocus() {
        let faces = [
            LoupeZoomFocus(x: 0.1, y: 0.1),
            LoupeZoomFocus(x: 0.9, y: 0.9),
            LoupeZoomFocus(x: 0.5, y: 0.5)
        ]

        XCTAssertEqual(LoupeFaceZoomTargeting.nearestFaceIndex(to: .center, among: faces), 2)
        XCTAssertEqual(LoupeFaceZoomTargeting.nearestFaceIndex(to: LoupeZoomFocus(x: 0.05, y: 0.05), among: faces), 0)
        XCTAssertNil(LoupeFaceZoomTargeting.nearestFaceIndex(to: .center, among: []))
    }

    func testWrappedIndexWrapsAroundFaceCount() {
        XCTAssertEqual(LoupeFaceZoomTargeting.wrappedIndex(current: 0, faceCount: 3), 1)
        XCTAssertEqual(LoupeFaceZoomTargeting.wrappedIndex(current: 1, faceCount: 3), 2)
        XCTAssertEqual(LoupeFaceZoomTargeting.wrappedIndex(current: 2, faceCount: 3), 0)
    }

    func testZoomToNearestFaceShortcutZoomsToNearestThenCyclesOnRepeatedPress() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "faces", size: 1)])
        model.setLoupeFaceFocuses([
            LoupeZoomFocus(x: 0.2, y: 0.2),
            LoupeZoomFocus(x: 0.8, y: 0.8)
        ])

        try model.applyCullingShortcut(.zoomToNearestFace)
        XCTAssertEqual(model.loupeZoomFocus, LoupeZoomFocus(x: 0.2, y: 0.2))

        try model.applyCullingShortcut(.zoomToNearestFace)
        XCTAssertEqual(model.loupeZoomFocus, LoupeZoomFocus(x: 0.8, y: 0.8))

        try model.applyCullingShortcut(.zoomToNearestFace)
        XCTAssertEqual(model.loupeZoomFocus, LoupeZoomFocus(x: 0.2, y: 0.2))
    }

    func testZoomToNearestFaceShortcutFallsBackToPlainCenterWhenNoFacesDetected() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "no-faces", size: 1)])

        try model.applyCullingShortcut(.zoomToNearestFace)

        XCTAssertEqual(model.loupeZoomFocus, .center)
    }

    func testManualZoomOrResetClearsFaceCycleIndexSoNextZoomPicksNearestAgain() throws {
        let model = AppModel(sidebarSections: [], selectedView: .grid, assets: [makeAsset(id: "manual-zoom", size: 1)])
        model.setLoupeFaceFocuses([
            LoupeZoomFocus(x: 0.2, y: 0.2),
            LoupeZoomFocus(x: 0.8, y: 0.8)
        ])

        try model.applyCullingShortcut(.zoomToNearestFace)
        XCTAssertEqual(model.loupeZoomFocus, LoupeZoomFocus(x: 0.2, y: 0.2))

        // A manual pan/click zoom breaks out of face-cycle tracking.
        model.zoomLoupe(to: LoupeZoomFocus(x: 0.75, y: 0.75))

        try model.applyCullingShortcut(.zoomToNearestFace)
        // Nearest to (0.75, 0.75) is picked fresh again, not "the next face after 0".
        XCTAssertEqual(model.loupeZoomFocus, LoupeZoomFocus(x: 0.8, y: 0.8))
    }

    private func makeAsset(id: String, size: Int64) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: size, modificationDate: Date(timeIntervalSince1970: TimeInterval(size))),
            availability: .online,
            metadata: AssetMetadata()
        )
    }
}
