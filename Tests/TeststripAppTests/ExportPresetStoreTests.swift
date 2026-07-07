import XCTest
import TeststripCore
@testable import TeststripApp

final class ExportPresetStoreTests: XCTestCase {
    func testLoadPresetsReturnsBuiltInDefaultsWhenNothingSaved() throws {
        let defaults = try makeDefaults()

        XCTAssertEqual(ExportPresetStore.loadPresets(defaults: defaults), ExportPreset.all)
    }

    func testSaveAndLoadPresetsRoundTrips() throws {
        let defaults = try makeDefaults()
        let custom = [
            ExportPreset.web2048,
            ExportPreset(name: "Client delivery", settings: ExportSettings(jpegQuality: 0.92, longEdgeMaximumPixels: 3600))
        ]

        ExportPresetStore.savePresets(custom, defaults: defaults)

        XCTAssertEqual(ExportPresetStore.loadPresets(defaults: defaults), custom)
    }

    func testLoadPresetsFallsBackToBuiltInsWhenSavedListIsEmpty() throws {
        let defaults = try makeDefaults()

        ExportPresetStore.savePresets([], defaults: defaults)

        XCTAssertEqual(ExportPresetStore.loadPresets(defaults: defaults), ExportPreset.all)
    }

    func testLastUsedPresetNameIsNilUntilRemembered() throws {
        let defaults = try makeDefaults()

        XCTAssertNil(ExportPresetStore.lastUsedPresetName(defaults: defaults))

        ExportPresetStore.rememberLastUsedPreset(named: "Web 2048px", defaults: defaults)

        XCTAssertEqual(ExportPresetStore.lastUsedPresetName(defaults: defaults), "Web 2048px")
    }

    func testLastUsedPresetLooksUpByNameWithinGivenList() throws {
        let defaults = try makeDefaults()
        let presets = [ExportPreset.fullResolutionJPEG, ExportPreset.web2048]
        ExportPresetStore.rememberLastUsedPreset(named: "Web 2048px", defaults: defaults)

        XCTAssertEqual(ExportPresetStore.lastUsedPreset(in: presets, defaults: defaults), .web2048)
    }

    func testLastUsedPresetReturnsNilWhenRememberedNameNoLongerExists() throws {
        let defaults = try makeDefaults()
        ExportPresetStore.rememberLastUsedPreset(named: "Deleted preset", defaults: defaults)

        XCTAssertNil(ExportPresetStore.lastUsedPreset(in: [ExportPreset.fullResolutionJPEG], defaults: defaults))
    }

    func testUpsertingAppendsANewlyNamedPreset() {
        let presets = [ExportPreset.fullResolutionJPEG, ExportPreset.web2048]
        let addition = ExportPreset(name: "Client delivery", settings: ExportSettings(jpegQuality: 0.92))

        let result = ExportPresetListEditing.upserting(addition, into: presets)

        XCTAssertEqual(result, [.fullResolutionJPEG, .web2048, addition])
    }

    func testUpsertingOverwritesAnExistingPresetInPlace() {
        let presets = [ExportPreset.fullResolutionJPEG, ExportPreset.web2048, ExportPreset.print300dpi]
        let replacement = ExportPreset(name: "Web 2048px", settings: ExportSettings(jpegQuality: 0.5, longEdgeMaximumPixels: 1024))

        let result = ExportPresetListEditing.upserting(replacement, into: presets)

        XCTAssertEqual(result, [.fullResolutionJPEG, replacement, .print300dpi])
    }

    func testRemovingDropsThePresetWithThatName() {
        let presets = [ExportPreset.fullResolutionJPEG, ExportPreset.web2048, ExportPreset.print300dpi]

        let result = ExportPresetListEditing.removing(named: "Web 2048px", from: presets)

        XCTAssertEqual(result, [.fullResolutionJPEG, .print300dpi])
    }

    func testRemovingAbsentNameIsANoOp() {
        let presets = [ExportPreset.fullResolutionJPEG, ExportPreset.web2048]

        let result = ExportPresetListEditing.removing(named: "Not present", from: presets)

        XCTAssertEqual(result, presets)
    }

    func testRemovingTheLastRemainingPresetIsANoOp() {
        let presets = [ExportPreset.fullResolutionJPEG]

        let result = ExportPresetListEditing.removing(named: "Full-res JPEG", from: presets)

        XCTAssertEqual(result, presets)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "teststrip.export-preset-store.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "ExportPresetStoreTests", code: 1)
        }
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
