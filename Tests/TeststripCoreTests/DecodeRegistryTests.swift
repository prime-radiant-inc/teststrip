import XCTest
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
