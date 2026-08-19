import XCTest
@testable import TeststripApp
@testable import TeststripCore

final class ManualRotationTests: XCTestCase {
    func testRotateClockwiseFromZero() throws {
        let model = try makeModelWithSingleAsset()
        try model.rotateSelectedAssetClockwise()
        XCTAssertEqual(try selectedAssetRotation(model), 90)
    }

    func testRotateClockwiseWrapsToZero() throws {
        let model = try makeModelWithSingleAsset()
        try model.rotateSelectedAssetClockwise()  // 0 → 90
        try model.rotateSelectedAssetClockwise()  // 90 → 180
        try model.rotateSelectedAssetClockwise()  // 180 → 270
        try model.rotateSelectedAssetClockwise()  // 270 → 0
        XCTAssertEqual(try selectedAssetRotation(model), 0)
    }

    func testRotateCounterClockwiseFromZero() throws {
        let model = try makeModelWithSingleAsset()
        try model.rotateSelectedAssetCounterClockwise()  // 0 → 270
        XCTAssertEqual(try selectedAssetRotation(model), 270)
    }

    func testRotateCounterClockwiseWrapsTo270() throws {
        let model = try makeModelWithSingleAsset()
        try model.rotateSelectedAssetCounterClockwise()  // 0 → 270
        try model.rotateSelectedAssetCounterClockwise()  // 270 → 180
        try model.rotateSelectedAssetCounterClockwise()  // 180 → 90
        try model.rotateSelectedAssetCounterClockwise()  // 90 → 0
        XCTAssertEqual(try selectedAssetRotation(model), 0)
    }

    // MARK: - Helpers

    private func makeModelWithSingleAsset() throws -> AppModel {
        let assetID = AssetID(rawValue: "rotation-test")
        let asset = Asset(
            id: assetID,
            originalURL: URL(fileURLWithPath: "/Photos/rotation-test.jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 4000,
                pixelHeight: 3000,
                provenance: ProviderProvenance(
                    provider: "test",
                    model: "test",
                    version: "1",
                    settingsHash: ""
                )
            )
        )
        let (model, repository) = try makeModelWithCatalogAssets(
            named: "manual-rotation",
            assets: [asset]
        )
        model.selectedAssetID = assetID
        _ = repository
        return model
    }

    private func selectedAssetRotation(_ model: AppModel) throws -> Int {
        guard let selectedAssetID = model.selectedAssetID else {
            throw TeststripError.invalidState("no selected asset")
        }
        let asset = model.assets.first { $0.id == selectedAssetID }
        return asset?.technicalMetadata?.rotation ?? 0
    }
}
