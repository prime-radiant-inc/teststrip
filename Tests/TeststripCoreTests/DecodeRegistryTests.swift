import XCTest
import ImageIO
@testable import TeststripCore

final class DecodeRegistryTests: XCTestCase {
    func testRegistrySelectsProviderByFileExtension() throws {
        let provider = FakeDecodeProvider(name: "fake", extensions: ["cr2", "dng"])
        let registry = DecodeRegistry(providers: [provider])

        let selected = try registry.provider(for: URL(fileURLWithPath: "/tmp/photo.CR2"))

        XCTAssertEqual(selected.name, "fake")
    }

    func testRegistryThrowsForUnsupportedFormat() {
        let registry = DecodeRegistry(providers: [])

        XCTAssertThrowsError(try registry.provider(for: URL(fileURLWithPath: "/tmp/photo.lytro"))) { error in
            XCTAssertEqual(error as? TeststripError, .unsupportedFormat("no decode provider for lytro"))
        }
    }

    func testImageIODimensionsReadPixelSizeFromProperties() throws {
        let dimensions = try ImageIODecodeProvider.dimensions(from: [
            kCGImagePropertyPixelWidth: 100,
            kCGImagePropertyPixelHeight: 80
        ], filename: "photo.dng")

        XCTAssertEqual(dimensions.pixelWidth, 100)
        XCTAssertEqual(dimensions.pixelHeight, 80)
    }

    func testImageIODimensionsApplyOrientationThatRotatesDisplayBounds() throws {
        let dimensions = try ImageIODecodeProvider.dimensions(from: [
            kCGImagePropertyPixelWidth: 6000,
            kCGImagePropertyPixelHeight: 4000,
            kCGImagePropertyOrientation: NSNumber(value: 6)
        ], filename: "portrait.jpg")

        XCTAssertEqual(dimensions.pixelWidth, 4000)
        XCTAssertEqual(dimensions.pixelHeight, 6000)
    }

    func testImageIOTechnicalMetadataReadsCameraLensISOAndCaptureDate() throws {
        let provenance = ProviderProvenance(provider: "ImageIO", model: "ImageIO", version: "1", settingsHash: "default")
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 1
        components.day = 2
        components.hour = 3
        components.minute = 4
        components.second = 5

        let metadata = try ImageIODecodeProvider.metadata(from: [
            kCGImagePropertyPixelWidth: 6000,
            kCGImagePropertyPixelHeight: 4000,
            kCGImagePropertyTIFFDictionary: [
                kCGImagePropertyTIFFMake: "Canon",
                kCGImagePropertyTIFFModel: "EOS R5"
            ],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifLensModel: "RF 50mm F1.2L USM",
                kCGImagePropertyExifISOSpeedRatings: [800],
                kCGImagePropertyExifDateTimeOriginal: "2026:01:02 03:04:05"
            ]
        ], provenance: provenance, filename: "photo.cr3")

        XCTAssertEqual(metadata.pixelWidth, 6000)
        XCTAssertEqual(metadata.pixelHeight, 4000)
        XCTAssertEqual(metadata.cameraMake, "Canon")
        XCTAssertEqual(metadata.cameraModel, "EOS R5")
        XCTAssertEqual(metadata.lensModel, "RF 50mm F1.2L USM")
        XCTAssertEqual(metadata.isoSpeed, 800)
        XCTAssertEqual(metadata.capturedAt, components.date)
        XCTAssertEqual(metadata.provenance, provenance)
    }

    func testImageIOSupportedExtensionsArePublicForIngestComposition() {
        XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("jpg"))
        XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("dng"))
        XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("crw"))
        XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("raf"))
        XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("rwl"))
        XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("srw"))
        XCTAssertFalse(ImageIODecodeProvider.supportedExtensions.contains("x3f"))
        XCTAssertTrue(ImageIODecodeProvider.knownUnsupportedRawExtensions.contains("x3f"))
    }

    func testImageIOCatalogableExtensionsIncludeRecognizedUnsupportedRawFamilies() {
        XCTAssertTrue(ImageIODecodeProvider.catalogableExtensions.contains("jpg"))
        XCTAssertTrue(ImageIODecodeProvider.catalogableExtensions.contains("dng"))
        XCTAssertTrue(ImageIODecodeProvider.catalogableExtensions.contains("x3f"))
        XCTAssertFalse(ImageIODecodeProvider.catalogableExtensions.contains("lytro"))
    }

    func testImageIOCapabilityMatrixMarksCommonStillFormatsAsWorking() {
        let provider = ImageIODecodeProvider()

        let jpeg = provider.capability(forFileExtension: "JPG")

        XCTAssertEqual(jpeg?.support, .working)
        XCTAssertEqual(jpeg?.fileExtension, "jpg")
        XCTAssertEqual(jpeg?.providerName, "ImageIO")
        XCTAssertTrue(jpeg?.canReadMetadata == true)
        XCTAssertTrue(jpeg?.canRenderPreview == true)
        XCTAssertTrue(jpeg?.canRenderFullImage == true)
    }

    func testImageIOCapabilityMatrixMarksEveryDeclaredRawFamilyAsBestEffort() {
        let provider = ImageIODecodeProvider()

        for fileExtension in ImageIODecodeProvider.bestEffortRawExtensions.sorted() {
            let capability = provider.capability(forFileExtension: fileExtension)

            XCTAssertEqual(capability?.support, .bestEffort, fileExtension)
            XCTAssertTrue(capability?.canReadMetadata == true, fileExtension)
            XCTAssertTrue(capability?.canUseEmbeddedPreview == true, fileExtension)
            XCTAssertTrue(capability?.canRenderPreview == true, fileExtension)
            XCTAssertFalse(capability?.canRenderFullImage == true, fileExtension)
            XCTAssertTrue(capability?.note.localizedCaseInsensitiveContains("OS") == true, fileExtension)
        }
    }

    func testImageIOUnsupportedRawFamiliesAreExcludedFromDecodeRouting() {
        let provider = ImageIODecodeProvider()

        for fileExtension in ImageIODecodeProvider.knownUnsupportedRawExtensions.sorted() {
            XCTAssertFalse(ImageIODecodeProvider.supportedExtensions.contains(fileExtension), fileExtension)
            XCTAssertFalse(provider.canDecode(url: URL(fileURLWithPath: "/tmp/photo.\(fileExtension)")), fileExtension)

            let capability = provider.capability(forFileExtension: fileExtension)
            XCTAssertEqual(capability?.support, .unsupported, fileExtension)
            XCTAssertFalse(capability?.canReadMetadata == true, fileExtension)
            XCTAssertFalse(capability?.canUseEmbeddedPreview == true, fileExtension)
            XCTAssertFalse(capability?.canRenderPreview == true, fileExtension)
            XCTAssertFalse(capability?.canRenderFullImage == true, fileExtension)
        }
    }

    func testRawFixtureCoverageUsesRealDNGWhenConfigured() throws {
        try assertRawFixtureCoverage(fileExtension: "dng", label: "Adobe DNG")
    }

    func testRawFixtureCoverageUsesRealCRWWhenConfigured() throws {
        try assertRawFixtureCoverage(fileExtension: "crw", label: "Canon CRW")
    }

    func testRawFixtureCoverageUsesRealCR2WhenConfigured() throws {
        try assertRawFixtureCoverage(fileExtension: "cr2", label: "Canon CR2")
    }

    func testRawFixtureCoverageUsesRealRAFWhenConfigured() throws {
        try assertRawFixtureCoverage(fileExtension: "raf", label: "Fuji RAF")
    }

    func testRawFixtureCoverageUsesRealX3FWhenConfigured() throws {
        try assertRawFixtureCoverage(fileExtension: "x3f", label: "Sigma/Foveon X3F")
    }

    func testImageIOCapabilityMatrixRecognizesX3FAsUnsupportedUntilDedicatedProviderExists() {
        let capability = ImageIODecodeProvider().capability(forFileExtension: "x3f")

        XCTAssertEqual(capability?.support, .unsupported)
        XCTAssertFalse(capability?.canReadMetadata == true)
        XCTAssertFalse(capability?.canRenderPreview == true)
        XCTAssertTrue(capability?.note.localizedCaseInsensitiveContains("Sigma") == true)
    }

    func testImageIOCapabilityMatrixRejectsUnsupportedLongTailFormats() {
        let capability = ImageIODecodeProvider().capability(forFileExtension: "lytro")

        XCTAssertEqual(capability?.support, .unsupported)
        XCTAssertFalse(capability?.canReadMetadata == true)
        XCTAssertFalse(capability?.canRenderPreview == true)
    }

    func testRegistryReturnsSelectedProviderCapability() throws {
        let provider = FakeDecodeProvider(name: "fake", extensions: ["dng"])
        let registry = DecodeRegistry(providers: [provider])

        let capability = try registry.capability(for: URL(fileURLWithPath: "/tmp/photo.DNG"))

        XCTAssertEqual(capability.providerName, "fake")
        XCTAssertEqual(capability.fileExtension, "dng")
        XCTAssertEqual(capability.support, .bestEffort)
    }

    func testRegistryReturnsRecognizedUnsupportedCapabilityWithoutDecodeRouting() throws {
        let registry = DecodeRegistry(providers: [ImageIODecodeProvider()])

        let capability = try registry.capability(for: URL(fileURLWithPath: "/tmp/photo.X3F"))

        XCTAssertEqual(capability.fileExtension, "x3f")
        XCTAssertEqual(capability.support, .unsupported)
        XCTAssertFalse(capability.canRenderPreview)
    }

    func testRegistryThrowsForUnrecognizedUnsupportedCapability() {
        let registry = DecodeRegistry(providers: [ImageIODecodeProvider()])

        XCTAssertThrowsError(try registry.capability(for: URL(fileURLWithPath: "/tmp/photo.lytro"))) { error in
            XCTAssertEqual(error as? TeststripError, .unsupportedFormat("no decode capability for lytro"))
        }
    }

    func testImageIOCanDecodeUsesSharedSupportedExtensions() {
        let provider = ImageIODecodeProvider()

        for fileExtension in ImageIODecodeProvider.supportedExtensions {
            XCTAssertTrue(provider.canDecode(url: URL(fileURLWithPath: "/tmp/photo.\(fileExtension)")))
        }
    }

    func testImageIODimensionsRejectUnreadablePixelSize() {
        let invalidProperties: [[CFString: Any]] = [
            [kCGImagePropertyPixelHeight: 80],
            [kCGImagePropertyPixelWidth: 100],
            [kCGImagePropertyPixelWidth: 0, kCGImagePropertyPixelHeight: 80],
            [kCGImagePropertyPixelWidth: 100, kCGImagePropertyPixelHeight: 0]
        ]

        for properties in invalidProperties {
            XCTAssertThrowsError(try ImageIODecodeProvider.dimensions(from: properties, filename: "photo.dng")) { error in
                XCTAssertEqual(error as? TeststripError, .unsupportedFormat("ImageIO could not read dimensions for photo.dng"))
            }
        }
    }

    private func rawFixtureDirectory() throws -> URL {
        guard let path = ProcessInfo.processInfo.environment["TESTSTRIP_RAW_FIXTURE_DIRECTORY"],
              !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw XCTSkip("Set TESTSTRIP_RAW_FIXTURE_DIRECTORY with real sample.<ext> files to run RAW fixture coverage.")
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath, isDirectory: true)
    }

    private func assertRawFixtureCoverage(fileExtension: String, label: String) throws {
        let fixtureURL = try rawFixtureDirectory().appendingPathComponent("sample.\(fileExtension)")
        guard FileManager.default.fileExists(atPath: fixtureURL.path) else {
            throw XCTSkip("Missing \(label) fixture at \(fixtureURL.path)")
        }
        let provider = ImageIODecodeProvider()
        let expectedSupport: DecodeSupportLevel = ImageIODecodeProvider.knownUnsupportedRawExtensions.contains(fileExtension)
            ? .unsupported
            : .bestEffort

        XCTAssertEqual(
            provider.capability(forFileExtension: fixtureURL.pathExtension)?.support,
            expectedSupport,
            label
        )
        guard expectedSupport != .unsupported else { return }

        let metadata = try provider.metadata(for: fixtureURL)
        XCTAssertGreaterThan(metadata.pixelWidth, 0, label)
        XCTAssertGreaterThan(metadata.pixelHeight, 0, label)
    }
}

private struct FakeDecodeProvider: DecodeProvider {
    let name: String
    let supportedExtensions: Set<String>

    init(name: String, extensions: [String]) {
        self.name = name
        self.supportedExtensions = Set(extensions)
    }

    func canDecode(url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    func metadata(for url: URL) throws -> DecodeMetadata {
        DecodeMetadata(pixelWidth: 1, pixelHeight: 1, provenance: ProviderProvenance(provider: name, model: "fake", version: "1", settingsHash: "default"))
    }
}
