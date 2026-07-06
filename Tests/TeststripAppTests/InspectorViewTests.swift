import XCTest
import CoreGraphics
import TeststripCore
@testable import TeststripApp

final class InspectorViewTests: XCTestCase {
    func testSelectedPreviewLayoutPinsSize() {
        XCTAssertEqual(InspectorPreviewLayout.size, CGSize(width: 258, height: 186))
    }

    func testInspectorColumnWidthPinsPreviewPlusPadding() {
        XCTAssertEqual(InspectorPreviewLayout.columnWidth, 286)
    }

    func testSelectedPreviewLayoutPinsPreviewAboveMetadataScroll() {
        XCTAssertTrue(InspectorPreviewLayout.pinsPreviewAboveMetadataScroll)
    }

    func testAssetIdentitySplitsFilenameExtensionAndStatus() {
        let asset = makeAsset(
            id: "identity",
            originalURL: URL(fileURLWithPath: "/Photos/Patagonia/frame-001.CR2"),
            availability: .offline,
            metadata: AssetMetadata(rating: 4)
        )

        let identity = InspectorAssetIdentity(asset: asset)

        XCTAssertEqual(identity.fullFilename, "frame-001.CR2")
        XCTAssertEqual(identity.displayName, "frame-001")
        XCTAssertEqual(identity.extensionBadge, "CR2")
        XCTAssertEqual(identity.availabilityText, "Original offline; cached previews only")
        XCTAssertEqual(identity.ratingText, "Rating: 4")
        XCTAssertEqual(identity.accessibilityValue, "Original offline; cached previews only, Rating: 4")
        XCTAssertNil(identity.capturedText)
    }

    func testAssetIdentityUsesCapturedDateWhenTechnicalMetadataExists() {
        let asset = makeAsset(
            id: "captured",
            metadata: AssetMetadata(),
            technicalMetadata: AssetTechnicalMetadata(
                pixelWidth: 6000,
                pixelHeight: 4000,
                capturedAt: Date(timeIntervalSince1970: 1_704_067_200),
                provenance: ProviderProvenance(provider: "test", model: "test", version: "1", settingsHash: "test")
            )
        )

        let identity = InspectorAssetIdentity(asset: asset)

        XCTAssertNotNil(identity.capturedText)
    }

    func testTechnicalRowsUseCompactCatalogMetadata() {
        let metadata = AssetTechnicalMetadata(
            pixelWidth: 8256,
            pixelHeight: 5504,
            cameraMake: "Fujifilm",
            cameraModel: "GFX 100S",
            lensModel: "GF45-100mmF4",
            isoSpeed: 800,
            capturedAt: nil,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )

        XCTAssertEqual(
            InspectorTechnicalRows(metadata: metadata).rows,
            [
                InspectorMetadataRow(title: "Dimensions", value: "8256 x 5504"),
                InspectorMetadataRow(title: "Camera", value: "Fujifilm GFX 100S"),
                InspectorMetadataRow(title: "Lens", value: "GF45-100mmF4"),
                InspectorMetadataRow(title: "ISO", value: "800")
            ]
        )
    }

    func testTechnicalRowsIncludeApertureShutterSpeedAndFocalLengthWhenPresent() {
        let metadata = AssetTechnicalMetadata(
            pixelWidth: 8256,
            pixelHeight: 5504,
            cameraMake: "Fujifilm",
            cameraModel: "GFX 100S",
            lensModel: "GF45-100mmF4",
            isoSpeed: 800,
            aperture: 2.8,
            shutterSpeed: 1.0 / 250.0,
            focalLength: 85,
            capturedAt: nil,
            provenance: ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        )

        XCTAssertEqual(
            InspectorTechnicalRows(metadata: metadata).rows,
            [
                InspectorMetadataRow(title: "Dimensions", value: "8256 x 5504"),
                InspectorMetadataRow(title: "Camera", value: "Fujifilm GFX 100S"),
                InspectorMetadataRow(title: "Lens", value: "GF45-100mmF4"),
                InspectorMetadataRow(title: "ISO", value: "800"),
                InspectorMetadataRow(title: "Aperture", value: "ƒ/2.8"),
                InspectorMetadataRow(title: "Shutter Speed", value: "1/250s"),
                InspectorMetadataRow(title: "Focal Length", value: "85mm")
            ]
        )
    }

    func testEvaluationSignalsGroupIntoPhotographerFacingSections() {
        let signals = [
            evaluationSignal(kind: .object, value: .label("camera")),
            evaluationSignal(kind: .focus, value: .score(0.92)),
            evaluationSignal(kind: .ocrText, value: .text("Invoice 123")),
            evaluationSignal(kind: .framing, value: .label("tight crop")),
            evaluationSignal(kind: .colorPalette, value: .vector([0.12, 0.34, 0.56])),
            evaluationSignal(kind: .faceCount, value: .count(2))
        ]

        let groups = InspectorEvaluationSignalGroup.groups(for: signals)

        XCTAssertEqual(groups.map(\.title), [
            "Technical Quality",
            "Faces",
            "Text",
            "Objects & Content",
            "Color & Look"
        ])
        XCTAssertEqual(groups[0].rows.map(\.title), ["Focus"])
        XCTAssertEqual(groups[1].rows.map(\.title), ["Face count"])
        XCTAssertEqual(groups[2].rows.map(\.value), ["Invoice 123"])
        XCTAssertEqual(groups[3].rows.map(\.title), ["Object"])
        XCTAssertEqual(groups[4].rows.map(\.title), ["Framing", "Color"])
        XCTAssertEqual(groups[4].rows.map(\.value), ["tight crop", "0.12, 0.34, 0.56"])
    }

    func testEvaluationRowsKeepConfidenceAndProviderProvenance() {
        let signal = evaluationSignal(
            kind: .aesthetics,
            value: .label("keeper"),
            confidence: 0.735,
            provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
        )

        let row = try! XCTUnwrap(InspectorEvaluationSignalGroup.groups(for: [signal]).first?.rows.first)

        XCTAssertEqual(row.title, "Aesthetics")
        XCTAssertEqual(row.value, "keeper")
        XCTAssertEqual(row.detail, "74% - local-http-model/llava")
    }

    func testCaptionSuggestionPresentationNamesExplicitAcceptAction() {
        let suggestion = CaptionSuggestion(
            caption: "Invoice 123 Client ABC",
            sourceKind: .ocrText,
            confidence: 0.923,
            providerName: "apple-vision",
            modelName: "Vision-OCR"
        )

        let presentation = InspectorCaptionSuggestionPresentation(suggestions: [suggestion])

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.title, "TESTSTRIP READS")
        XCTAssertEqual(presentation.actionLabel(for: suggestion), "Accept OCR caption")
        XCTAssertEqual(presentation.detailText(for: suggestion), "92% - apple-vision/Vision-OCR")
        XCTAssertEqual(presentation.helpText(for: suggestion), "Accept OCR caption: Invoice 123 Client ABC")
    }

    func testProviderFailurePresentationNamesFailureAndRetryAction() {
        let failure = CatalogEvaluationFailure(
            assetID: AssetID(rawValue: "failed"),
            provider: "local-http-model",
            message: "model timed out",
            failedAt: Date(timeIntervalSince1970: 1_704_067_200)
        )

        let presentation = InspectorProviderFailurePresentation(failures: [failure])

        XCTAssertTrue(presentation.isVisible)
        XCTAssertEqual(presentation.title, "Provider retry needed")
        XCTAssertEqual(presentation.detailText(for: failure), "local-http-model failed: model timed out")
        XCTAssertEqual(presentation.actionLabel(for: failure), "Retry local-http-model")
    }

    func testEvaluationRowsKeepDuplicateProvidersVisible() {
        let signals = [
            evaluationSignal(
                kind: .focus,
                value: .score(0.91),
                confidence: 0.82,
                provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
            ),
            evaluationSignal(
                kind: .focus,
                value: .score(0.88),
                confidence: 0.77,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            )
        ]

        let rows = try! XCTUnwrap(InspectorEvaluationSignalGroup.groups(for: signals).first?.rows)

        XCTAssertEqual(rows.map(\.value), ["0.91", "0.88"])
        XCTAssertEqual(rows.map(\.detail), ["82% - apple-vision/Vision", "77% - local-http-model/llava"])
    }

    func testMetadataSyncStatusPresentationDescribesPendingSidecar() throws {
        let asset = makeAsset(id: "pending", metadata: AssetMetadata(rating: 4))
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: URL(fileURLWithPath: "/Photos/pending.jpg.xmp"),
            catalogGeneration: 7,
            lastSyncedFingerprint: "old"
        )

        let status = try XCTUnwrap(InspectorMetadataSyncStatus(
            asset: asset,
            pendingItems: [pending],
            conflictItems: []
        ))

        XCTAssertEqual(status.kind, .pending)
        XCTAssertEqual(status.title, "XMP sync pending")
        XCTAssertEqual(status.detail, "Catalog metadata is saved; sidecar write is waiting to retry.")
        XCTAssertEqual(status.sidecarFilename, "pending.jpg.xmp")
        XCTAssertEqual(status.sidecarPath, "/Photos/pending.jpg.xmp")
        XCTAssertEqual(status.catalogGenerationText, "Catalog generation 7")
    }

    func testMetadataSyncStatusPresentationPrefersConflictOverPending() throws {
        let asset = makeAsset(id: "conflict", metadata: AssetMetadata(rating: 4))
        let pending = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: URL(fileURLWithPath: "/Photos/conflict-pending.jpg.xmp"),
            catalogGeneration: 4,
            lastSyncedFingerprint: "old"
        )
        let conflict = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: URL(fileURLWithPath: "/Photos/conflict.jpg.xmp"),
            catalogGeneration: 5,
            lastSyncedFingerprint: "newer"
        )

        let status = try XCTUnwrap(InspectorMetadataSyncStatus(
            asset: asset,
            pendingItems: [pending],
            conflictItems: [conflict]
        ))

        XCTAssertEqual(status.kind, .conflict)
        XCTAssertEqual(status.title, "XMP conflict")
        XCTAssertEqual(status.detail, "Catalog and sidecar both changed since the last sync.")
        XCTAssertEqual(status.sidecarFilename, "conflict.jpg.xmp")
        XCTAssertEqual(status.catalogGenerationText, "Catalog generation 5")
    }

    func testMetadataSyncStatusPresentationShowsConflictFieldDifferences() throws {
        let asset = makeAsset(
            id: "conflict",
            metadata: AssetMetadata(rating: 4, colorLabel: .red, flag: .pick, keywords: ["catalog"])
        )
        let conflict = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: URL(fileURLWithPath: "/Photos/conflict.jpg.xmp"),
            catalogGeneration: 5,
            lastSyncedFingerprint: "newer"
        )

        let status = try XCTUnwrap(InspectorMetadataSyncStatus(
            asset: asset,
            pendingItems: [],
            conflictItems: [conflict],
            conflictSidecarMetadata: AssetMetadata(rating: 5, colorLabel: .green, flag: .reject, keywords: ["sidecar"])
        ))

        XCTAssertEqual(status.detail, "Review changed fields before choosing whether Catalog or XMP wins.")
        XCTAssertEqual(status.conflictRows.map(\.title), ["Rating", "Color label", "Flag", "Keywords"])
        XCTAssertEqual(status.conflictRows.map(\.catalogValue), ["4", "red", "pick", "catalog"])
        XCTAssertEqual(status.conflictRows.map(\.sidecarValue), ["5", "green", "reject", "sidecar"])
    }

    func testMetadataSyncStatusPresentationDisablesSidecarActionsWhenConflictSidecarUnreadable() throws {
        let asset = makeAsset(id: "conflict", metadata: AssetMetadata(rating: 4))
        let conflict = MetadataSyncItem(
            assetID: asset.id,
            sidecarURL: URL(fileURLWithPath: "/Photos/conflict.jpg.xmp"),
            catalogGeneration: 5,
            lastSyncedFingerprint: "newer"
        )

        let status = try XCTUnwrap(InspectorMetadataSyncStatus(
            asset: asset,
            pendingItems: [],
            conflictItems: [conflict],
            conflictSidecarMetadataState: .unreadable
        ))

        XCTAssertEqual(status.detail, "XMP sidecar metadata could not be read. Use Catalog to recreate the sidecar, or restore the sidecar before importing it.")
        XCTAssertEqual(status.conflictRows, [])
        XCTAssertEqual(status.conflictActions.map(\.title), [
            "Merge Missing",
            "Use Catalog",
            "Use XMP"
        ])
        XCTAssertEqual(status.conflictActions.map(\.isEnabled), [
            false,
            true,
            false
        ])
    }

    func testMetadataConflictActionsExposeMergeBeforeDestructiveChoices() {
        XCTAssertEqual(InspectorMetadataConflictActionPresentation.actions.map(\.title), [
            "Merge Missing",
            "Use Catalog",
            "Use XMP"
        ])
        XCTAssertEqual(InspectorMetadataConflictActionPresentation.actions.map(\.kind), [
            .mergeMissingSidecarFields,
            .useCatalog,
            .useSidecar
        ])
        XCTAssertTrue(InspectorMetadataConflictActionPresentation.actions[0].help.localizedCaseInsensitiveContains("missing"))
        XCTAssertTrue(InspectorMetadataConflictActionPresentation.actions[1].help.localizedCaseInsensitiveContains("overwrite"))
        XCTAssertTrue(InspectorMetadataConflictActionPresentation.actions[2].help.localizedCaseInsensitiveContains("import"))
    }

    func testMetadataDraftFormatsPortableMetadataFromAsset() {
        let asset = makeAsset(
            id: "draft-asset",
            metadata: AssetMetadata(
                keywords: ["Patagonia", "keeper"],
                caption: "Fitz Roy sunrise",
                creator: "Jesse",
                copyright: "Copyright Jesse"
            )
        )

        let draft = InspectorMetadataDraft(asset: asset)

        XCTAssertEqual(draft.assetID, asset.id)
        XCTAssertEqual(draft.keywords, "Patagonia, keeper")
        XCTAssertEqual(draft.caption, "Fitz Roy sunrise")
        XCTAssertEqual(draft.creator, "Jesse")
        XCTAssertEqual(draft.copyright, "Copyright Jesse")
    }

    func testMetadataDraftResetsOnlyWhenSelectionChanges() {
        let first = makeAsset(
            id: "first",
            metadata: AssetMetadata(keywords: ["first"], caption: "First caption")
        )
        let second = makeAsset(
            id: "second",
            metadata: AssetMetadata(keywords: ["second"], caption: "Second caption")
        )
        var draft = InspectorMetadataDraft(asset: first)
        draft.caption = "Unsaved typing"

        draft.sync(to: first)
        XCTAssertEqual(draft.caption, "Unsaved typing")

        draft.sync(to: second)
        XCTAssertEqual(draft.assetID, second.id)
        XCTAssertEqual(draft.keywords, "second")
        XCTAssertEqual(draft.caption, "Second caption")
    }

    func testMetadataDraftRefreshesSameSelectionWhenSourceMetadataChanges() {
        let original = makeAsset(
            id: "same",
            metadata: AssetMetadata(keywords: ["first"], caption: "First caption")
        )
        let updated = makeAsset(
            id: "same",
            metadata: AssetMetadata(keywords: ["updated"], caption: "Updated caption")
        )
        var draft = InspectorMetadataDraft(asset: original)

        draft.sync(to: updated)

        XCTAssertEqual(draft.assetID, updated.id)
        XCTAssertEqual(draft.keywords, "updated")
        XCTAssertEqual(draft.caption, "Updated caption")
    }

    func testMetadataDraftTracksAppliedSameSelectionChangesForUndoRefresh() {
        let original = makeAsset(
            id: "same",
            metadata: AssetMetadata(keywords: ["first"], caption: "First caption")
        )
        let applied = makeAsset(
            id: "same",
            metadata: AssetMetadata(keywords: ["first"], caption: "Applied caption")
        )
        var draft = InspectorMetadataDraft(asset: original)
        draft.caption = "Applied caption"

        draft.sync(to: applied)
        draft.sync(to: original)

        XCTAssertEqual(draft.caption, "First caption")
    }

    private func makeAsset(
        id: String,
        originalURL: URL? = nil,
        availability: SourceAvailability = .online,
        metadata: AssetMetadata,
        technicalMetadata: AssetTechnicalMetadata? = nil
    ) -> Asset {
        Asset(
            id: AssetID(rawValue: id),
            originalURL: originalURL ?? URL(fileURLWithPath: "/Photos/\(id).jpg"),
            volumeIdentifier: "Photos",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: availability,
            metadata: metadata,
            technicalMetadata: technicalMetadata
        )
    }

    private func evaluationSignal(
        kind: EvaluationKind,
        value: EvaluationValue,
        confidence: Double = 0.82,
        provenance: ProviderProvenance = ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
    ) -> EvaluationSignal {
        EvaluationSignal(
            assetID: AssetID(rawValue: "asset-\(kind.rawValue)"),
            kind: kind,
            value: value,
            confidence: confidence,
            provenance: provenance
        )
    }
}
