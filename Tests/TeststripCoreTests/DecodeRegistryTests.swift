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
        XCTAssertTrue(ImageIODecodeProvider.supportedExtensions.contains("x3f"))
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
