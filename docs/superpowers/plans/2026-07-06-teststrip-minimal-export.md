# Minimal Resized-JPEG Export Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resized-JPEG export of the current selection/visible page/current scope: JPEG quality + optional long-edge pixel cap, destination folder chosen via the existing folder panel, presets "Full-res JPEG" (quality 0.9, no resize) and "Web 2048px" (quality 0.8, 2048px long edge). Writes only into the chosen destination; originals and catalog are never touched. No watermarking, no print presets, no color-space controls, no export history.

**Architecture:** A new pure core service `ExportService` in `Sources/TeststripCore/Export/ExportService.swift` takes original file URLs + `ExportSettings`, writes JPEGs into a destination directory using the same CGImageSource/CGImageDestination pattern as `PreviewRenderer`, and returns per-file results (exported / skipped-unavailable / failed-with-message) with deterministic `-2`, `-3` collision suffixes. The app layer adds three `AppModel` async methods mirroring the `applyVisibleBatchMetadata` / `applySelectedBatchMetadata` / `applyCurrentScopeBatchMetadata` trio, running the service on a detached task (the `beginImportFolder` pattern) with a main-actor progress sink (the `AppImportProgressSink` pattern). The UI is an Export toolbar popover in `LibraryGridView` that clones the Batch Metadata popover wiring (scope segmented picker, count text, all-catalog confirmation toggle) plus a preset picker, and gets the destination from a new `FolderSelectionPanel.chooseExportDestinationFolder` that clones the card-destination panel.

**Tech Stack:** Swift 6 / SwiftPM, macOS 14+, SwiftUI + AppKit (NSOpenPanel), ImageIO (CGImageSource/CGImageDestination), XCTest.

**Decision — in-process async, not worker-dispatched:** Batch XMP writes go through `WorkerSupervisor` because they must coordinate catalog metadata-sync state (pending fingerprints, conflict detection, background-work queue items). Export has none of that: it reads originals and writes new files to a user-chosen folder with zero catalog writes, so there is no shared state to coordinate and no recovery story needed. The import flow already demonstrates the sanctioned in-process pattern (`Task.detached` factory + main-actor completion, AppModel.swift:7528-7563, 7983); export copies it directly. Worker dispatch would require a new worker command, protocol plumbing, and event handling for no benefit.

**Decision — no export work session:** `WorkSessionKind.export` exists (Sources/TeststripCore/Work/WorkSession.swift:21), but recording one would pull in the `AppWorkActivity` machinery (`recordRecentActivity`, output asset sets, sidebar rebuilds — AppModel.swift:7752-7783) which is import-shaped and nontrivial. The approved spec explicitly excludes export history, so we omit it. The completion `statusMessage` is the user-visible record.

## Global Constraints

- TDD is mandatory: every behavior lands as failing test → minimal implementation → green → commit.
- Presets are exactly: "Full-res JPEG" = quality 0.9, no long-edge cap; "Web 2048px" = quality 0.8, cap 2048.
- JPEG quality is clamped to 0...1 in `ExportSettings.init`.
- Export never upscales (ImageIO thumbnail API never enlarges past source pixels).
- Output filenames come only from `sourceURL.deletingPathExtension().lastPathComponent` + `.jpg`; collisions get deterministic `-2`, `-3`, ... suffixes; nothing is ever written outside the destination directory.
- Missing/unreadable originals are reported as `skippedUnavailable` (filesystem check at export time); undecodable files as `failed(message:)`. No silent drops.
- No catalog writes anywhere in the export path. No backward-compatibility shims.
- Run `swift test` from `/Users/jesse/git/projects/teststrip`. Full gate at the end: `swift test` and `./script/build_and_run.sh --build`.
- Work on a WIP branch (e.g. `git checkout -b minimal-export`) if not already on one. Commit after every green step.
- Line numbers below are anchors as of commit `dd18246`; re-locate by the quoted code if they have shifted.

---

## Task 1: Export settings and preset value types

**Files:**
- Create: `Sources/TeststripCore/Export/ExportService.swift`
- Create: `Tests/TeststripCoreTests/ExportServiceTests.swift`

**Interfaces:**
- Produces: `ExportSettings(jpegQuality: Double, longEdgeMaximumPixels: Int? = nil)` (Hashable, Sendable; quality clamped to 0...1)
- Produces: `ExportPreset` (Hashable, Sendable) with `static let fullResolutionJPEG`, `static let web2048`, `static let all: [ExportPreset]`
- Consumes: nothing (pure value types)

**Steps:**

- [ ] Write the failing test file `Tests/TeststripCoreTests/ExportServiceTests.swift`:

```swift
import Foundation
import XCTest
import TeststripCore

final class ExportServiceTests: XCTestCase {
    func testPresetsMatchApprovedSpecValues() {
        XCTAssertEqual(ExportPreset.fullResolutionJPEG.name, "Full-res JPEG")
        XCTAssertEqual(ExportPreset.fullResolutionJPEG.settings.jpegQuality, 0.9)
        XCTAssertNil(ExportPreset.fullResolutionJPEG.settings.longEdgeMaximumPixels)
        XCTAssertEqual(ExportPreset.web2048.name, "Web 2048px")
        XCTAssertEqual(ExportPreset.web2048.settings.jpegQuality, 0.8)
        XCTAssertEqual(ExportPreset.web2048.settings.longEdgeMaximumPixels, 2048)
        XCTAssertEqual(ExportPreset.all, [.fullResolutionJPEG, .web2048])
    }

    func testSettingsClampJpegQualityToUnitRange() {
        XCTAssertEqual(ExportSettings(jpegQuality: 1.5).jpegQuality, 1.0)
        XCTAssertEqual(ExportSettings(jpegQuality: -0.2).jpegQuality, 0.0)
        XCTAssertEqual(ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 2048).longEdgeMaximumPixels, 2048)
    }
}
```

- [ ] Run `swift test --filter ExportServiceTests` — expect compile failure: `cannot find 'ExportPreset' in scope`.
- [ ] Create `Sources/TeststripCore/Export/ExportService.swift` with the minimal types:

```swift
import Foundation

public struct ExportSettings: Hashable, Sendable {
    public var jpegQuality: Double
    public var longEdgeMaximumPixels: Int?

    public init(jpegQuality: Double, longEdgeMaximumPixels: Int? = nil) {
        self.jpegQuality = min(max(jpegQuality, 0), 1)
        self.longEdgeMaximumPixels = longEdgeMaximumPixels
    }
}

public struct ExportPreset: Hashable, Sendable {
    public var name: String
    public var settings: ExportSettings

    public init(name: String, settings: ExportSettings) {
        self.name = name
        self.settings = settings
    }

    public static let fullResolutionJPEG = ExportPreset(
        name: "Full-res JPEG",
        settings: ExportSettings(jpegQuality: 0.9)
    )

    public static let web2048 = ExportPreset(
        name: "Web 2048px",
        settings: ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 2048)
    )

    public static let all = [fullResolutionJPEG, web2048]
}
```

- [ ] Run `swift test --filter ExportServiceTests` — expect 2 tests passing.
- [ ] Commit: `git add Sources/TeststripCore/Export/ExportService.swift Tests/TeststripCoreTests/ExportServiceTests.swift && git commit -m "Add export settings and preset value types"`

---

## Task 2: ExportService writes resized JPEGs and returns per-file results

**Files:**
- Modify: `Sources/TeststripCore/Export/ExportService.swift` (append below `ExportPreset`)
- Test: `Tests/TeststripCoreTests/ExportServiceTests.swift`

**Interfaces:**
- Produces: `ExportOutcome` enum: `.exported(destinationURL: URL)`, `.skippedUnavailable`, `.failed(message: String)` (Equatable, Sendable)
- Produces: `ExportFileResult { sourceURL: URL, outcome: ExportOutcome }` (Equatable, Sendable)
- Produces: `public typealias ExportProgressHandler = @Sendable (_ completedCount: Int, _ totalCount: Int) -> Void`
- Produces: `ExportService.export(originalURLs: [URL], settings: ExportSettings, destinationDirectory: URL, progress: ExportProgressHandler? = nil) throws -> [ExportFileResult]` (throws `TeststripError.io` only for destination-directory creation failure)
- Consumes: `TeststripError` (Sources/TeststripCore/Support/TeststripError.swift:3), `TestDirectories.makeTemporaryDirectory` / `writeTestJPEG` (Tests/TeststripCoreTests/TestSupport.swift:8,17), `PreviewRenderer.dimensions(of:)` (Sources/TeststripCore/Preview/PreviewRenderer.swift:49)

**Steps:**

- [ ] Add failing tests to `ExportServiceTests`:

```swift
    func testExportWritesJpegBoundedByLongEdgeCap() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-resize")
        let source = directory.appendingPathComponent("source.jpg")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.8, longEdgeMaximumPixels: 600),
            destinationDirectory: destination
        )

        let exportedURL = destination.appendingPathComponent("source.jpg")
        XCTAssertEqual(results, [ExportFileResult(sourceURL: source, outcome: .exported(destinationURL: exportedURL))])
        let dimensions = try PreviewRenderer().dimensions(of: exportedURL)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 600, height: 400))
    }

    func testExportWithoutCapKeepsFullResolutionAndReplacesExtension() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-full-res")
        let source = directory.appendingPathComponent("source.png")
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try TestDirectories.writeTestJPEG(to: source, width: 1200, height: 800)

        let results = try ExportService().export(
            originalURLs: [source],
            settings: ExportPreset.fullResolutionJPEG.settings,
            destinationDirectory: destination
        )

        let exportedURL = destination.appendingPathComponent("source.jpg")
        XCTAssertEqual(results, [ExportFileResult(sourceURL: source, outcome: .exported(destinationURL: exportedURL))])
        let dimensions = try PreviewRenderer().dimensions(of: exportedURL)
        XCTAssertEqual(dimensions, PreviewDimensions(width: 1200, height: 800))
    }

    func testExportWrapsDestinationDirectoryCreationFailureAsIO() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-destination-error")
        let source = directory.appendingPathComponent("source.jpg")
        let blockedParent = directory.appendingPathComponent("blocked-parent")
        try TestDirectories.writeTestJPEG(to: source, width: 100, height: 100)
        try Data("not a directory".utf8).write(to: blockedParent)

        XCTAssertThrowsError(try ExportService().export(
            originalURLs: [source],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: blockedParent.appendingPathComponent("nested", isDirectory: true)
        )) { error in
            guard case .io = error as? TeststripError else {
                XCTFail("expected TeststripError.io, got \(error)")
                return
            }
        }
    }
```

Note: `writeTestJPEG(to:)` writes JPEG bytes regardless of the `.png` name in the second test; ImageIO sniffs content, so this also proves the output name always becomes `.jpg`.

- [ ] Run `swift test --filter ExportServiceTests` — expect compile failure: `cannot find 'ExportService' in scope`.
- [ ] Append the service to `Sources/TeststripCore/Export/ExportService.swift` (and change the file's imports to `import Foundation`, `import ImageIO`, `import UniformTypeIdentifiers`):

```swift
public enum ExportOutcome: Equatable, Sendable {
    case exported(destinationURL: URL)
    case skippedUnavailable
    case failed(message: String)
}

public struct ExportFileResult: Equatable, Sendable {
    public var sourceURL: URL
    public var outcome: ExportOutcome

    public init(sourceURL: URL, outcome: ExportOutcome) {
        self.sourceURL = sourceURL
        self.outcome = outcome
    }
}

public typealias ExportProgressHandler = @Sendable (_ completedCount: Int, _ totalCount: Int) -> Void

public struct ExportService: Sendable {
    public init() {}

    public func export(
        originalURLs: [URL],
        settings: ExportSettings,
        destinationDirectory: URL,
        progress: ExportProgressHandler? = nil
    ) throws -> [ExportFileResult] {
        do {
            try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw TeststripError.io("could not create export destination \(destinationDirectory.path): \(error.localizedDescription)")
        }
        var claimedFilenames: Set<String> = []
        var results: [ExportFileResult] = []
        for (index, sourceURL) in originalURLs.enumerated() {
            progress?(index + 1, originalURLs.count)
            results.append(ExportFileResult(
                sourceURL: sourceURL,
                outcome: exportOutcome(
                    sourceURL: sourceURL,
                    settings: settings,
                    destinationDirectory: destinationDirectory,
                    claimedFilenames: &claimedFilenames
                )
            ))
        }
        return results
    }

    private func exportOutcome(
        sourceURL: URL,
        settings: ExportSettings,
        destinationDirectory: URL,
        claimedFilenames: inout Set<String>
    ) -> ExportOutcome {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return .skippedUnavailable
        }
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            return .failed(message: "could not read \(sourceURL.lastPathComponent)")
        }
        var thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        if let longEdgeMaximumPixels = settings.longEdgeMaximumPixels {
            thumbnailOptions[kCGImageSourceThumbnailMaxPixelSize] = longEdgeMaximumPixels
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) else {
            return .failed(message: "could not decode \(sourceURL.lastPathComponent)")
        }
        let destinationURL = availableDestinationURL(
            for: sourceURL,
            destinationDirectory: destinationDirectory,
            claimedFilenames: &claimedFilenames
        )
        guard let destination = CGImageDestinationCreateWithURL(destinationURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            return .failed(message: "could not create \(destinationURL.lastPathComponent)")
        }
        let destinationProperties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: settings.jpegQuality
        ]
        CGImageDestinationAddImage(destination, image, destinationProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            return .failed(message: "could not write \(destinationURL.lastPathComponent)")
        }
        return .exported(destinationURL: destinationURL)
    }

    private func availableDestinationURL(
        for sourceURL: URL,
        destinationDirectory: URL,
        claimedFilenames: inout Set<String>
    ) -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        var candidateName = "\(baseName).jpg"
        var suffix = 2
        while claimedFilenames.contains(candidateName.lowercased())
            || FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent(candidateName).path) {
            candidateName = "\(baseName)-\(suffix).jpg"
            suffix += 1
        }
        claimedFilenames.insert(candidateName.lowercased())
        return destinationDirectory.appendingPathComponent(candidateName)
    }
}
```

- [ ] Run `swift test --filter ExportServiceTests` — expect 5 tests passing. If `testExportWithoutCapKeepsFullResolutionAndReplacesExtension` fails on dimensions, the no-cap thumbnail path is wrong: fix by computing the source's max pixel dimension via `CGImageSourceCopyPropertiesAtIndex` and passing it as `kCGImageSourceThumbnailMaxPixelSize` instead of omitting the key (do not weaken the test).
- [ ] Commit: `git add -u Sources Tests && git commit -m "Write resized JPEG exports with per-file results"`

---

## Task 3: Collision suffixes, skip/fail reporting, progress, quality, non-destructive guarantees

**Files:**
- Modify: `Sources/TeststripCore/Export/ExportService.swift` (only if a test exposes a gap — the Task 2 implementation is expected to already satisfy these)
- Test: `Tests/TeststripCoreTests/ExportServiceTests.swift`

**Interfaces:**
- Consumes: everything produced in Task 2. No new public API.

**Steps:**

- [ ] Add failing/characterization tests to `ExportServiceTests`:

```swift
    func testExportResolvesFilenameCollisionsWithDeterministicSuffix() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-collisions")
        let firstFolder = directory.appendingPathComponent("a", isDirectory: true)
        let secondFolder = directory.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let firstSource = firstFolder.appendingPathComponent("photo.jpg")
        let secondSource = secondFolder.appendingPathComponent("photo.jpg")
        try TestDirectories.writeTestJPEG(to: firstSource, width: 100, height: 80)
        try TestDirectories.writeTestJPEG(to: secondSource, width: 100, height: 80)
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try TestDirectories.writeTestJPEG(to: destination.appendingPathComponent("photo.jpg"), width: 10, height: 10)

        let results = try ExportService().export(
            originalURLs: [firstSource, secondSource],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination
        )

        XCTAssertEqual(results, [
            ExportFileResult(sourceURL: firstSource, outcome: .exported(destinationURL: destination.appendingPathComponent("photo-2.jpg"))),
            ExportFileResult(sourceURL: secondSource, outcome: .exported(destinationURL: destination.appendingPathComponent("photo-3.jpg")))
        ])
        let preexistingDimensions = try PreviewRenderer().dimensions(of: destination.appendingPathComponent("photo.jpg"))
        XCTAssertEqual(preexistingDimensions, PreviewDimensions(width: 10, height: 10))
    }

    func testExportSkipsMissingOriginalsAndReportsUndecodableOnesAsFailed() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-skip-fail")
        let goodSource = directory.appendingPathComponent("good.jpg")
        let missingSource = directory.appendingPathComponent("missing.jpg")
        let brokenSource = directory.appendingPathComponent("broken.jpg")
        try TestDirectories.writeTestJPEG(to: goodSource, width: 100, height: 80)
        try Data("not an image".utf8).write(to: brokenSource)
        let destination = directory.appendingPathComponent("out", isDirectory: true)

        let results = try ExportService().export(
            originalURLs: [goodSource, missingSource, brokenSource],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination
        )

        XCTAssertEqual(results.count, 3)
        XCTAssertEqual(results[0].outcome, .exported(destinationURL: destination.appendingPathComponent("good.jpg")))
        XCTAssertEqual(results[1].outcome, .skippedUnavailable)
        guard case .failed(let message) = results[2].outcome else {
            XCTFail("expected failed outcome, got \(results[2].outcome)")
            return
        }
        XCTAssertTrue(message.contains("broken.jpg"), "failure message should name the file: \(message)")
        let writtenNames = try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted()
        XCTAssertEqual(writtenNames, ["good.jpg"])
    }

    func testExportReportsProgressPerFile() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-progress")
        let sources = try (0..<3).map { index -> URL in
            let url = directory.appendingPathComponent("photo-\(index).jpg")
            try TestDirectories.writeTestJPEG(to: url, width: 50, height: 40)
            return url
        }
        let destination = directory.appendingPathComponent("out", isDirectory: true)
        let recorded = ProgressRecorder()

        _ = try ExportService().export(
            originalURLs: sources,
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination
        ) { completedCount, totalCount in
            recorded.append(completed: completedCount, total: totalCount)
        }

        XCTAssertEqual(recorded.pairs.map(\.completed), [1, 2, 3])
        XCTAssertEqual(recorded.pairs.map(\.total), [3, 3, 3])
    }

    func testLowerQualityProducesSmallerFile() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-quality")
        let source = directory.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 800, height: 600)
        let highDestination = directory.appendingPathComponent("high", isDirectory: true)
        let lowDestination = directory.appendingPathComponent("low", isDirectory: true)

        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 1.0),
            destinationDirectory: highDestination
        )
        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportSettings(jpegQuality: 0.1),
            destinationDirectory: lowDestination
        )

        let highSize = try XCTUnwrap(FileManager.default.attributesOfItem(
            atPath: highDestination.appendingPathComponent("source.jpg").path
        )[.size] as? Int64)
        let lowSize = try XCTUnwrap(FileManager.default.attributesOfItem(
            atPath: lowDestination.appendingPathComponent("source.jpg").path
        )[.size] as? Int64)
        XCTAssertLessThan(lowSize, highSize)
    }

    func testExportLeavesOriginalsUntouchedAndWritesOnlyIntoDestination() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "export-non-destructive")
        let sourceFolder = directory.appendingPathComponent("originals", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        let source = sourceFolder.appendingPathComponent("source.jpg")
        try TestDirectories.writeTestJPEG(to: source, width: 100, height: 80)
        let originalBytes = try Data(contentsOf: source)
        let destination = directory.appendingPathComponent("out", isDirectory: true)

        _ = try ExportService().export(
            originalURLs: [source],
            settings: ExportPreset.web2048.settings,
            destinationDirectory: destination
        )

        XCTAssertEqual(try Data(contentsOf: source), originalBytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: sourceFolder.path), ["source.jpg"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["source.jpg"])
    }
```

And add this helper class at the bottom of `ExportServiceTests.swift` (inside the file, outside the test class), needed because the progress handler is `@Sendable`:

```swift
private final class ProgressRecorder: @unchecked Sendable {
    private(set) var pairs: [(completed: Int, total: Int)] = []
    private let lock = NSLock()

    func append(completed: Int, total: Int) {
        lock.lock()
        defer { lock.unlock() }
        pairs.append((completed, total))
    }
}
```

- [ ] Run `swift test --filter ExportServiceTests` — these are characterization tests for behavior Task 2 already implemented, so they may pass immediately. If any fails, fix `ExportService` (not the test) until green. Confirm all 10 tests pass.
- [ ] Commit: `git add -u Tests Sources && git commit -m "Cover export collisions, skips, failures, progress, and quality"`

---

## Task 4: Export destination folder panel

**Files:**
- Modify: `Sources/TeststripApp/FolderSelectionPanel.swift` (keys at lines 6-8; choose functions end line 44; configure functions end line 89; starting-directory functions end line 101; remember functions end line 113)
- Test: `Tests/TeststripAppTests/FolderSelectionPanelTests.swift`

**Interfaces:**
- Produces: `FolderSelectionPanel.chooseExportDestinationFolder(defaults: UserDefaults = .standard) -> URL?`
- Produces: `FolderSelectionPanel.configureExportDestinationPanel(_ panel: NSOpenPanel, startingDirectory: URL? = nil, rememberedDirectory: URL? = nil)`
- Produces: `FolderSelectionPanel.startingExportDestinationDirectory(defaults: UserDefaults = .standard) -> URL?`
- Produces: `FolderSelectionPanel.rememberExportDestinationFolder(_ folderURL: URL, defaults: UserDefaults = .standard)`
- Consumes: private helpers `configureDirectoryPanel`, `rememberDirectory`, `rememberedDirectory(for:defaults:)`, `defaultStartingDirectory()` (FolderSelectionPanel.swift:135-175)

**Steps:**

- [ ] Add failing tests to `FolderSelectionPanelTests` (after `testCardDestinationPanelChoosesOneCreatableDirectory`, line 68):

```swift
    @MainActor
    func testExportDestinationPanelChoosesOneCreatableDirectory() throws {
        let panel = NSOpenPanel()
        let startingDirectory = try makeTemporaryDirectory(named: "export-destination-start")

        FolderSelectionPanel.configureExportDestinationPanel(panel, startingDirectory: startingDirectory)

        XCTAssertTrue(panel.canChooseDirectories)
        XCTAssertFalse(panel.canChooseFiles)
        XCTAssertFalse(panel.allowsMultipleSelection)
        XCTAssertTrue(panel.canCreateDirectories)
        XCTAssertEqual(panel.prompt, "Export Here")
        XCTAssertEqual(panel.message, "Select where exported JPEGs should be written.")
        XCTAssertEqual(panel.directoryURL?.standardizedFileURL, startingDirectory.standardizedFileURL)
    }

    @MainActor
    func testRememberedExportDestinationStartsNextChooserAtSelectedDirectory() throws {
        let defaults = try makeDefaults()
        let parent = try makeTemporaryDirectory(named: "remember-export-destination-parent")
        let destination = parent.appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        FolderSelectionPanel.rememberExportDestinationFolder(destination, defaults: defaults)

        XCTAssertEqual(
            FolderSelectionPanel.startingExportDestinationDirectory(defaults: defaults)?.standardizedFileURL,
            destination.standardizedFileURL
        )
    }
```

- [ ] Run `swift test --filter FolderSelectionPanelTests` — expect compile failure: `type 'FolderSelectionPanel' has no member 'configureExportDestinationPanel'`.
- [ ] Implement in `FolderSelectionPanel.swift`, exactly mirroring the card-destination trio. Add the key beside the others (after line 8):

```swift
    private static let exportDestinationParentKey = "FolderSelectionPanel.exportDestinationParent"
```

Add after `chooseCardDestinationFolder` (line 44):

```swift
    static func chooseExportDestinationFolder(defaults: UserDefaults = .standard) -> URL? {
        let panel = NSOpenPanel()
        configureExportDestinationPanel(
            panel,
            startingDirectory: defaultStartingDirectory(),
            rememberedDirectory: rememberedDirectory(for: exportDestinationParentKey, defaults: defaults)
        )
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        rememberExportDestinationFolder(url, defaults: defaults)
        return url
    }
```

Add after `configureCardDestinationPanel` (line 89):

```swift
    static func configureExportDestinationPanel(
        _ panel: NSOpenPanel,
        startingDirectory: URL? = nil,
        rememberedDirectory: URL? = nil
    ) {
        configureDirectoryPanel(
            panel,
            startingDirectory: startingDirectory,
            rememberedDirectory: rememberedDirectory,
            canCreateDirectories: true,
            prompt: "Export Here",
            message: "Select where exported JPEGs should be written."
        )
    }
```

Add after `startingCardDestinationDirectory` (line 101):

```swift
    static func startingExportDestinationDirectory(defaults: UserDefaults = .standard) -> URL? {
        rememberedDirectory(for: exportDestinationParentKey, defaults: defaults) ?? defaultStartingDirectory()
    }
```

Add after `rememberCardDestinationFolder` (line 113):

```swift
    static func rememberExportDestinationFolder(_ folderURL: URL, defaults: UserDefaults = .standard) {
        rememberDirectory(folderURL, for: exportDestinationParentKey, defaults: defaults)
    }
```

- [ ] Run `swift test --filter FolderSelectionPanelTests` — expect all tests (existing 9 + new 2) passing.
- [ ] Commit: `git add -u Sources Tests && git commit -m "Add export destination folder panel"`

---

## Task 5: AppModel export actions (selected / visible / current scope)

**Files:**
- Modify: `Sources/TeststripApp/AppModel.swift`:
  - `ExportCompletionSummary` struct after `ImportCompletionSummary` (after line 795)
  - `public private(set) var isExporting = false` after `public var errorMessage: String?` (line 1037)
  - export methods after the `applyBatchMetadata` block (after line 4130, before `setCaptionForSelectedAsset`)
  - `AppExportProgressSink` after `AppImportProgressSink` (after line 8742)
- Test: `Tests/TeststripAppTests/AppModelTests.swift`

**Interfaces:**
- Produces: `ExportCompletionSummary { exportedCount, skippedCount, failedCount: Int; destinationFolder: URL; firstFailureMessage: String?; statusText: String }` (Equatable, Sendable)
- Produces on `AppModel`, all `@discardableResult @MainActor ... async throws -> ExportCompletionSummary`: `exportVisibleAssets(settings:destinationFolder:)`, `exportSelectedAssets(settings:destinationFolder:)`, `exportCurrentScopeAssets(settings:destinationFolder:)`
- Produces: `public private(set) var isExporting: Bool`
- Consumes: `assets.map(\.id)` / `selectedBatchAssetIDsInCatalogOrder` (AppModel.swift:2545) / `currentAssetScopeIDs(repository:)` (AppModel.swift:6859), `catalog.repository.asset(id:)` (CatalogRepository.swift:75), `ExportService.export` (Task 2), `Self.photoCountDescription` (AppModel.swift:7893), `TeststripError.invalidState`

**Steps:**

- [ ] Add failing tests to `AppModelTests` (after `testCurrentScopeBatchMetadataAppliesExplicitSetBeyondLoadedPage`, around line 1560; the fixtures reuse the file's existing `makeTemporaryDirectory(named:)` at line 12473 and `writeTestPNG(to:)` at line 12482 — the 1x1 PNG is ImageIO-decodable, so it exports as a 1x1 JPEG):

```swift
    func testExportVisibleAssetsWritesJpegCopiesAndReportsCompletionSummary() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-export-visible")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let goodURL = photosDirectory.appendingPathComponent("good.png")
        let brokenURL = photosDirectory.appendingPathComponent("broken.jpg")
        let missingURL = photosDirectory.appendingPathComponent("missing.jpg")
        try writeTestPNG(to: goodURL)
        try Data("not an image".utf8).write(to: brokenURL)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let good = makeAsset(id: "export-good", path: goodURL.path, rating: 0)
        let broken = makeAsset(id: "export-broken", path: brokenURL.path, rating: 0)
        let missing = makeAsset(id: "export-missing", path: missingURL.path, rating: 0, availability: .missing)
        try repository.upsert([good, broken, missing])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        let destination = directory.appendingPathComponent("exports", isDirectory: true)
        let originalBytes = try Data(contentsOf: goodURL)

        let summary = try await model.exportVisibleAssets(
            settings: ExportPreset.web2048.settings,
            destinationFolder: destination
        )

        XCTAssertEqual(summary.exportedCount, 1)
        XCTAssertEqual(summary.skippedCount, 1)
        XCTAssertEqual(summary.failedCount, 1)
        XCTAssertEqual(summary.destinationFolder, destination)
        XCTAssertEqual(summary.firstFailureMessage, "could not decode broken.jpg")
        XCTAssertEqual(model.statusMessage, "Exported 1 photo to exports (1 skipped, 1 failed)")
        XCTAssertEqual(model.errorMessage, "could not decode broken.jpg")
        XCTAssertFalse(model.isExporting)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["good.jpg"])
        XCTAssertEqual(try Data(contentsOf: goodURL), originalBytes)
        XCTAssertEqual(try repository.asset(id: good.id), good)
        XCTAssertEqual(try repository.asset(id: broken.id), broken)
        XCTAssertEqual(try repository.asset(id: missing.id), missing)
    }

    func testExportSelectedAssetsExportsOnlySelectedBatch() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-export-selected")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let assets = try (0..<3).map { index -> Asset in
            let url = photosDirectory.appendingPathComponent("photo-\(index).png")
            try writeTestPNG(to: url)
            return makeAsset(id: "export-selected-\(index)", path: url.path, rating: 0)
        }
        try repository.upsert(assets)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        model.setBatchSelection(assets[0].id, isSelected: true)
        model.setBatchSelection(assets[2].id, isSelected: true)
        let destination = directory.appendingPathComponent("exports", isDirectory: true)

        let summary = try await model.exportSelectedAssets(
            settings: ExportPreset.fullResolutionJPEG.settings,
            destinationFolder: destination
        )

        XCTAssertEqual(summary.exportedCount, 2)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(model.statusMessage, "Exported 2 photos to exports")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted(),
            ["photo-0.jpg", "photo-2.jpg"]
        )
    }

    func testExportCurrentScopeAssetsExportsFilteredAssetsBeyondLoadedPage() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-export-current-scope")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let matchingAssets = try (0..<121).map { index -> Asset in
            let url = photosDirectory.appendingPathComponent("matching-\(index).png")
            try writeTestPNG(to: url)
            return makeAsset(id: "export-scope-\(index)", path: url.path, rating: 0, colorLabel: .green)
        }
        let outsideURL = photosDirectory.appendingPathComponent("outside.png")
        try writeTestPNG(to: outsideURL)
        let outsideAsset = makeAsset(id: "export-scope-outside", path: outsideURL.path, rating: 0, colorLabel: .red)
        try repository.upsert(matchingAssets + [outsideAsset])
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        model.colorLabelFilter = .green
        try model.applyLibraryFilters()
        XCTAssertLessThan(model.assets.count, matchingAssets.count)
        let destination = directory.appendingPathComponent("exports", isDirectory: true)

        let summary = try await model.exportCurrentScopeAssets(
            settings: ExportPreset.web2048.settings,
            destinationFolder: destination
        )

        XCTAssertEqual(summary.exportedCount, matchingAssets.count)
        XCTAssertEqual(summary.skippedCount, 0)
        XCTAssertEqual(summary.failedCount, 0)
        XCTAssertEqual(model.statusMessage, "Exported 121 photos to exports")
        let writtenNames = try FileManager.default.contentsOfDirectory(atPath: destination.path)
        XCTAssertEqual(writtenNames.count, matchingAssets.count)
        XCTAssertFalse(writtenNames.contains("outside.jpg"))
    }

    func testExportWithNoAssetsThrows() async throws {
        let (model, _) = try makeModelWithCatalogAssets(named: "app-model-export-empty", assets: [])
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-export-empty-\(UUID().uuidString)", isDirectory: true)

        do {
            _ = try await model.exportVisibleAssets(
                settings: ExportPreset.web2048.settings,
                destinationFolder: destination
            )
            XCTFail("expected export of empty scope to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "no photos to export")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    @MainActor
    func testSecondExportWhileRunningThrows() async throws {
        let directory = try makeTemporaryDirectory(named: "app-model-export-reentrancy")
        let photosDirectory = directory.appendingPathComponent("photos", isDirectory: true)
        try FileManager.default.createDirectory(at: photosDirectory, withIntermediateDirectories: true)
        let url = photosDirectory.appendingPathComponent("photo.png")
        try writeTestPNG(to: url)
        let database = try CatalogDatabase.open(at: directory.appendingPathComponent("catalog.sqlite"))
        try database.migrate()
        let repository = CatalogRepository(database: database)
        let asset = makeAsset(id: "export-reentrancy", path: url.path, rating: 0)
        try repository.upsert(asset)
        let model = try AppModel.load(catalog: AppCatalog(
            paths: AppCatalog.defaultPaths(applicationSupportDirectory: directory.appendingPathComponent("app-support", isDirectory: true)),
            repository: repository,
            previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true)),
            importService: LibraryImportService(
                ingestService: IngestService(scanner: FolderScanner(supportedExtensions: [])),
                previewCache: PreviewCache(root: directory.appendingPathComponent("previews", isDirectory: true))
            )
        ))
        let destination = directory.appendingPathComponent("exports", isDirectory: true)

        let firstExport = Task { @MainActor in
            try await model.exportVisibleAssets(
                settings: ExportPreset.web2048.settings,
                destinationFolder: destination
            )
        }
        while !model.isExporting {
            await Task.yield()
        }

        do {
            _ = try await model.exportVisibleAssets(
                settings: ExportPreset.web2048.settings,
                destinationFolder: destination
            )
            XCTFail("expected concurrent export to throw")
        } catch {
            XCTAssertEqual(error.localizedDescription, "another export is already running")
        }
        let summary = try await firstExport.value
        XCTAssertEqual(summary.exportedCount, 1)
        XCTAssertFalse(model.isExporting)
    }
```

Note on the re-entrancy test: it is deterministic because `exportVisibleAssets` is `@MainActor` and sets `isExporting = true` before its only suspension point (the detached-task await); the second call runs its guard synchronously on the main actor while the first is suspended.

- [ ] Run `swift test --filter AppModelTests.testExportVisibleAssetsWritesJpegCopiesAndReportsCompletionSummary` — expect compile failure: `value of type 'AppModel' has no member 'exportVisibleAssets'`.
- [ ] Implement in `AppModel.swift`. After the `ImportCompletionSummary` struct (line 795) add:

```swift
public struct ExportCompletionSummary: Equatable, Sendable {
    public var exportedCount: Int
    public var skippedCount: Int
    public var failedCount: Int
    public var destinationFolder: URL
    public var firstFailureMessage: String?

    public init(
        exportedCount: Int,
        skippedCount: Int,
        failedCount: Int,
        destinationFolder: URL,
        firstFailureMessage: String?
    ) {
        self.exportedCount = exportedCount
        self.skippedCount = skippedCount
        self.failedCount = failedCount
        self.destinationFolder = destinationFolder
        self.firstFailureMessage = firstFailureMessage
    }

    public init(results: [ExportFileResult], destinationFolder: URL) {
        var exportedCount = 0
        var skippedCount = 0
        var failedCount = 0
        var firstFailureMessage: String?
        for result in results {
            switch result.outcome {
            case .exported:
                exportedCount += 1
            case .skippedUnavailable:
                skippedCount += 1
            case .failed(let message):
                failedCount += 1
                if firstFailureMessage == nil {
                    firstFailureMessage = message
                }
            }
        }
        self.init(
            exportedCount: exportedCount,
            skippedCount: skippedCount,
            failedCount: failedCount,
            destinationFolder: destinationFolder,
            firstFailureMessage: firstFailureMessage
        )
    }

    public var statusText: String {
        let exportedText = "Exported \(exportedCount) \(exportedCount == 1 ? "photo" : "photos") to \(destinationFolder.lastPathComponent)"
        var problems: [String] = []
        if skippedCount > 0 {
            problems.append("\(skippedCount) skipped")
        }
        if failedCount > 0 {
            problems.append("\(failedCount) failed")
        }
        guard !problems.isEmpty else { return exportedText }
        return "\(exportedText) (\(problems.joined(separator: ", ")))"
    }
}
```

After `public var errorMessage: String?` (line 1037) add:

```swift
    public private(set) var isExporting = false
```

After the end of `applyBatchMetadata` (line 4130, before `setCaptionForSelectedAsset`) add:

```swift
    @discardableResult
    @MainActor
    public func exportVisibleAssets(settings: ExportSettings, destinationFolder: URL) async throws -> ExportCompletionSummary {
        try await exportAssets(assetIDs: assets.map(\.id), settings: settings, destinationFolder: destinationFolder)
    }

    @discardableResult
    @MainActor
    public func exportSelectedAssets(settings: ExportSettings, destinationFolder: URL) async throws -> ExportCompletionSummary {
        try await exportAssets(assetIDs: selectedBatchAssetIDsInCatalogOrder, settings: settings, destinationFolder: destinationFolder)
    }

    @discardableResult
    @MainActor
    public func exportCurrentScopeAssets(settings: ExportSettings, destinationFolder: URL) async throws -> ExportCompletionSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        return try await exportAssets(
            assetIDs: try currentAssetScopeIDs(repository: catalog.repository),
            settings: settings,
            destinationFolder: destinationFolder
        )
    }

    @MainActor
    private func exportAssets(
        assetIDs: [AssetID],
        settings: ExportSettings,
        destinationFolder: URL
    ) async throws -> ExportCompletionSummary {
        guard let catalog else {
            throw TeststripError.invalidState("app model has no catalog")
        }
        guard !isExporting else {
            throw TeststripError.invalidState("another export is already running")
        }
        var seenAssetIDs: Set<AssetID> = []
        var originalURLs: [URL] = []
        for assetID in assetIDs {
            guard seenAssetIDs.insert(assetID).inserted else { continue }
            originalURLs.append(try catalog.repository.asset(id: assetID).originalURL)
        }
        guard !originalURLs.isEmpty else {
            throw TeststripError.invalidState("no photos to export")
        }
        isExporting = true
        defer { isExporting = false }
        errorMessage = nil
        statusMessage = "Exporting \(Self.photoCountDescription(originalURLs.count)) to \(destinationFolder.lastPathComponent)..."
        let sink = AppExportProgressSink(model: self, destinationName: destinationFolder.lastPathComponent)
        let service = ExportService()
        let urls = originalURLs
        let destination = destinationFolder
        let results: [ExportFileResult]
        do {
            results = try await Task.detached(priority: .userInitiated) {
                try service.export(
                    originalURLs: urls,
                    settings: settings,
                    destinationDirectory: destination
                ) { completedCount, totalCount in
                    sink.handle(completedCount: completedCount, totalCount: totalCount)
                }
            }.value
        } catch {
            statusMessage = nil
            throw error
        }
        let summary = ExportCompletionSummary(results: results, destinationFolder: destinationFolder)
        statusMessage = summary.statusText
        if summary.failedCount > 0 {
            errorMessage = summary.firstFailureMessage
        }
        return summary
    }
```

After the `AppImportProgressSink` class (line 8742, end of file region) add:

```swift
private final class AppExportProgressSink: @unchecked Sendable {
    private weak var model: AppModel?
    private let destinationName: String

    init(model: AppModel, destinationName: String) {
        self.model = model
        self.destinationName = destinationName
    }

    func handle(completedCount: Int, totalCount: Int) {
        Task { @MainActor in
            // Late-arriving progress hops are dropped once the export summary
            // has landed, so the completion message is never overwritten.
            guard let model = self.model, model.isExporting else { return }
            model.statusMessage = "Exporting photo \(completedCount) of \(totalCount) to \(self.destinationName)..."
        }
    }
}
```

- [ ] Run `swift test --filter "AppModelTests.testExport"` then `swift test --filter "AppModelTests.testSecondExportWhileRunningThrows"` — expect all 5 new tests passing.
- [ ] Run `swift test --filter AppModelTests` — expect the whole class green (no regressions).
- [ ] Commit: `git add -u Sources Tests && git commit -m "Add async selection/visible/scope JPEG export to app model"`

---

## Task 6: Export popover UI with shared scope modes

**Files:**
- Modify: `Sources/TeststripApp/LibraryGridView.swift`:
  - rename `BatchMetadataScopeMode` → `BatchScopeMode` at its 4 references (lines 23, 843, 3257, 3289)
  - state vars after line 24
  - toolbar button after the Batch Metadata button block (after line 179, `.liveMockupPlaceholder(.keywordingBatch)`)
  - `exportPopover` after `batchMetadataPopover` (after line 929)
  - `chooseExportDestinationAndExport()` after `applyVisibleBatchMetadataDraft()` (after line 2507)
  - `ExportReviewPresentation` struct after `BatchMetadataReviewPresentation` (after line 3324)
- Create: `Tests/TeststripAppTests/ExportReviewPresentationTests.swift`

**Interfaces:**
- Produces: `enum BatchScopeMode` (renamed from `BatchMetadataScopeMode`; cases `.selected`, `.visible`, `.currentScope`; same `title` strings)
- Produces: `struct ExportReviewPresentation: Equatable { countText: String; isExportEnabled: Bool; exportTitle: String; confirmationText: String? }` with `init(visibleAssetCount:selectedAssetCount:currentScopeAssetCount:selectedScope:requiresAllCatalogConfirmation:isAllCatalogConfirmed:isExporting:)`
- Consumes: `model.assets.count`, `model.selectedBatchAssetCount` (AppModel.swift:2480), `model.totalAssetCount`, `model.hasActiveLibraryFilters` (AppModel.swift:1643), `model.isExporting` (Task 5), `ExportPreset.all` (Task 1), `FolderSelectionPanel.chooseExportDestinationFolder` (Task 4), `model.exportSelectedAssets` / `exportVisibleAssets` / `exportCurrentScopeAssets` (Task 5)

**Steps:**

- [ ] Refactor (behavior-neutral, no new test): rename `BatchMetadataScopeMode` to `BatchScopeMode` everywhere. Run `grep -rn "BatchMetadataScopeMode" Sources Tests` — exactly 4 hits, all in `Sources/TeststripApp/LibraryGridView.swift` (lines 23, 843, 3257, 3289). Edit all 4, then confirm `grep -rn "BatchMetadataScopeMode" Sources Tests` returns nothing.
- [ ] Run `swift build && swift test --filter AppModelTests.testVisibleBatchMetadata` — expect build success and green (rename is compile-checked).
- [ ] Commit: `git add -u Sources && git commit -m "Rename batch metadata scope mode to shared batch scope mode"`
- [ ] Write the failing presentation test file `Tests/TeststripAppTests/ExportReviewPresentationTests.swift`:

```swift
import XCTest
@testable import TeststripApp

final class ExportReviewPresentationTests: XCTestCase {
    func testSelectedScopeCountsSelectionAndEnablesWhenNotEmpty() {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 3,
            currentScopeAssetCount: 500,
            selectedScope: .selected,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            isExporting: false
        )

        XCTAssertEqual(presentation.countText, "3 selected photos")
        XCTAssertTrue(presentation.isExportEnabled)
        XCTAssertEqual(presentation.exportTitle, "Export selected batch")
        XCTAssertNil(presentation.confirmationText)
    }

    func testSelectedScopeDisablesWhenSelectionIsEmpty() {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 500,
            selectedScope: .selected,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            isExporting: false
        )

        XCTAssertEqual(presentation.countText, "0 selected photos")
        XCTAssertFalse(presentation.isExportEnabled)
    }

    func testVisibleScopeCountsVisiblePhotos() {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: 1,
            selectedAssetCount: 0,
            currentScopeAssetCount: 500,
            selectedScope: .visible,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            isExporting: false
        )

        XCTAssertEqual(presentation.countText, "1 visible photo")
        XCTAssertTrue(presentation.isExportEnabled)
        XCTAssertEqual(presentation.exportTitle, "Export visible batch")
    }

    func testCurrentScopeWithoutFiltersRequiresAllCatalogConfirmation() {
        let unconfirmed = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 500,
            selectedScope: .currentScope,
            requiresAllCatalogConfirmation: true,
            isAllCatalogConfirmed: false,
            isExporting: false
        )
        let confirmed = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 0,
            currentScopeAssetCount: 500,
            selectedScope: .currentScope,
            requiresAllCatalogConfirmation: true,
            isAllCatalogConfirmed: true,
            isExporting: false
        )

        XCTAssertEqual(unconfirmed.countText, "500 photos in current scope")
        XCTAssertEqual(unconfirmed.confirmationText, "Confirm exporting all 500 catalog photos.")
        XCTAssertFalse(unconfirmed.isExportEnabled)
        XCTAssertTrue(confirmed.isExportEnabled)
        XCTAssertEqual(confirmed.exportTitle, "Export current scope")
    }

    func testRunningExportDisablesAnotherExport() {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: 12,
            selectedAssetCount: 3,
            currentScopeAssetCount: 500,
            selectedScope: .visible,
            requiresAllCatalogConfirmation: false,
            isAllCatalogConfirmed: false,
            isExporting: true
        )

        XCTAssertFalse(presentation.isExportEnabled)
    }
}
```

- [ ] Run `swift test --filter ExportReviewPresentationTests` — expect compile failure: `cannot find 'ExportReviewPresentation' in scope`.
- [ ] Add the presentation struct to `LibraryGridView.swift` immediately after `BatchMetadataReviewPresentation` (after line 3324):

```swift
struct ExportReviewPresentation: Equatable {
    var countText: String
    var isExportEnabled: Bool
    var exportTitle: String
    var confirmationText: String?

    init(
        visibleAssetCount: Int,
        selectedAssetCount: Int,
        currentScopeAssetCount: Int,
        selectedScope: BatchScopeMode,
        requiresAllCatalogConfirmation: Bool,
        isAllCatalogConfirmed: Bool,
        isExporting: Bool
    ) {
        switch selectedScope {
        case .selected:
            countText = "\(selectedAssetCount) selected \(selectedAssetCount == 1 ? "photo" : "photos")"
            confirmationText = nil
            isExportEnabled = selectedAssetCount > 0 && !isExporting
            exportTitle = "Export selected batch"
        case .visible:
            countText = "\(visibleAssetCount) visible \(visibleAssetCount == 1 ? "photo" : "photos")"
            confirmationText = nil
            isExportEnabled = visibleAssetCount > 0 && !isExporting
            exportTitle = "Export visible batch"
        case .currentScope:
            countText = "\(currentScopeAssetCount) \(currentScopeAssetCount == 1 ? "photo" : "photos") in current scope"
            confirmationText = requiresAllCatalogConfirmation
                ? "Confirm exporting all \(currentScopeAssetCount) catalog \(currentScopeAssetCount == 1 ? "photo" : "photos")."
                : nil
            isExportEnabled = currentScopeAssetCount > 0
                && !isExporting
                && (!requiresAllCatalogConfirmation || isAllCatalogConfirmed)
            exportTitle = "Export current scope"
        }
    }
}
```

- [ ] Run `swift test --filter ExportReviewPresentationTests` — expect 5 tests passing.
- [ ] Commit: `git add Sources/TeststripApp/LibraryGridView.swift Tests/TeststripAppTests/ExportReviewPresentationTests.swift && git commit -m "Add export review presentation"`
- [ ] Wire the UI (SwiftUI body wiring; covered by the presentation and model tests above per the repo's no-snapshot-test convention). Add state after line 24 (`isAllCatalogBatchMetadataConfirmed`):

```swift
    @State private var isReviewingExport = false
    @State private var exportScope: BatchScopeMode = .visible
    @State private var exportPreset: ExportPreset = .fullResolutionJPEG
    @State private var isAllCatalogExportConfirmed = false
```

Add the toolbar button directly after the Batch Metadata button block (after `.liveMockupPlaceholder(.keywordingBatch)`, line 179):

```swift
            Button {
                exportScope = model.selectedBatchAssetCount > 0 ? .selected : .visible
                isAllCatalogExportConfirmed = false
                isReviewingExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(isImporting || model.assets.isEmpty || model.isExporting)
            .help("Export JPEG copies to a folder")
            .popover(isPresented: $isReviewingExport) {
                exportPopover
            }
```

Add the popover after `batchMetadataPopover` (after line 929):

```swift
    private var exportPopover: some View {
        let presentation = ExportReviewPresentation(
            visibleAssetCount: model.assets.count,
            selectedAssetCount: model.selectedBatchAssetCount,
            currentScopeAssetCount: model.totalAssetCount,
            selectedScope: exportScope,
            requiresAllCatalogConfirmation: exportScope == .currentScope && !model.hasActiveLibraryFilters,
            isAllCatalogConfirmed: isAllCatalogExportConfirmed,
            isExporting: model.isExporting
        )
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Export JPEGs")
                        .font(.headline)
                    Text(presentation.countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.orange)
            }

            Picker("Export scope", selection: $exportScope) {
                ForEach(BatchScopeMode.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: exportScope) { _, _ in
                isAllCatalogExportConfirmed = false
            }

            Picker("Export preset", selection: $exportPreset) {
                ForEach(ExportPreset.all, id: \.name) { preset in
                    Text(preset.name).tag(preset)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if let confirmationText = presentation.confirmationText {
                Toggle(confirmationText, isOn: $isAllCatalogExportConfirmed)
                    .font(.caption)
            }

            HStack {
                Button("Cancel") {
                    isReviewingExport = false
                }
                Spacer()
                Button(presentation.exportTitle) {
                    chooseExportDestinationAndExport()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!presentation.isExportEnabled)
            }
        }
        .padding(14)
        .frame(width: 360)
    }
```

Add the action after `applyVisibleBatchMetadataDraft()` (after line 2507):

```swift
    private func chooseExportDestinationAndExport() {
        guard let destination = FolderSelectionPanel.chooseExportDestinationFolder() else { return }
        let settings = exportPreset.settings
        let scope = exportScope
        isReviewingExport = false
        isAllCatalogExportConfirmed = false
        Task { @MainActor in
            do {
                switch scope {
                case .selected:
                    try await model.exportSelectedAssets(settings: settings, destinationFolder: destination)
                case .visible:
                    try await model.exportVisibleAssets(settings: settings, destinationFolder: destination)
                case .currentScope:
                    try await model.exportCurrentScopeAssets(settings: settings, destinationFolder: destination)
                }
            } catch {
                model.errorMessage = error.localizedDescription
            }
        }
    }
```

- [ ] Run `swift build` — expect clean build.
- [ ] Run `swift test --filter "ExportReviewPresentationTests|FolderSelectionPanelTests"` — expect green.
- [ ] Commit: `git add -u Sources && git commit -m "Wire export popover into library grid toolbar"`

---

## Task 7: Full verification gate

**Files:**
- Test: entire suite; build: `script/build_and_run.sh`

**Interfaces:**
- Consumes: everything above. Produces: nothing new.

**Steps:**

- [ ] Run `swift test` — expect the full suite green (roughly 1000+ tests, zero failures, pristine output). Any failure anywhere is yours to fix before proceeding, even if pre-existing.
- [ ] Run `./script/build_and_run.sh --build` — expect the packaged dev app build to succeed (bundle staged under `dist/Teststrip.app`).
- [ ] Verify no stray changes: `git status` — only intended files; no leftover scratch files.
- [ ] Commit anything outstanding: `git add -u && git commit -m "Verify minimal export feature end to end"` (skip if the tree is already clean).
- [ ] Optional live check for the human loop: `./script/build_and_run.sh --isolated`, import a small folder, select a few photos, Export → "Web 2048px" → pick a folder, and confirm the status message reports exported counts and the JPEGs appear in the chosen folder.
