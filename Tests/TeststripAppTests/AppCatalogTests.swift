import XCTest
import TeststripCore
import TeststripApp

final class AppCatalogTests: XCTestCase {
    func testDefaultPathsLiveUnderApplicationSupportTeststrip() throws {
        let applicationSupport = URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true)

        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: applicationSupport)

        XCTAssertEqual(paths.root, applicationSupport.appendingPathComponent("Teststrip", isDirectory: true))
        XCTAssertEqual(paths.catalogURL, paths.root.appendingPathComponent("catalog.sqlite"))
        XCTAssertEqual(paths.previewCacheRoot, paths.root.appendingPathComponent("Previews", isDirectory: true))
    }

    func testDefaultPathsCanUseEnvironmentApplicationSupportOverride() throws {
        let applicationSupport = URL(fileURLWithPath: "/tmp/Isolated Teststrip", isDirectory: true)

        let paths = try AppCatalog.defaultPaths(environment: [
            AppCatalog.applicationSupportDirectoryEnvironmentKey: applicationSupport.path
        ])

        XCTAssertEqual(paths.root, applicationSupport.appendingPathComponent("Teststrip", isDirectory: true))
        XCTAssertEqual(paths.catalogURL, paths.root.appendingPathComponent("catalog.sqlite"))
        XCTAssertEqual(paths.previewCacheRoot, paths.root.appendingPathComponent("Previews", isDirectory: true))
    }

    func testLoadModelCreatesEmptyCatalogAndPreviewCache() throws {
        let root = try makeTemporaryDirectory(named: "app-catalog")
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: root)

        let model = try AppCatalog.loadModel(paths: paths)

        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.catalogURL.path))
        XCTAssertTrue(directoryExists(at: paths.previewCacheRoot))
        XCTAssertEqual(model.assets, [])
        XCTAssertNil(model.selectedAssetID)
        XCTAssertNil(model.selectedAsset)
    }

    func testBundledWorkerExecutableURLUsesBundleHelpersDirectory() {
        let bundleURL = URL(fileURLWithPath: "/Applications/Teststrip.app", isDirectory: true)

        XCTAssertEqual(
            AppCatalog.bundledWorkerExecutableURL(bundleURL: bundleURL),
            bundleURL.appendingPathComponent("Contents/Helpers/TeststripWorker")
        )
    }

    func testWorkerArgumentsIncludeConfiguredLocalHTTPModelProvider() {
        let paths = AppCatalog.defaultPaths(applicationSupportDirectory: URL(fileURLWithPath: "/tmp/Application Support", isDirectory: true))

        let arguments = AppCatalog.workerArguments(paths: paths, environment: [
            AppCatalog.localHTTPModelEndpointEnvironmentKey: "http://localhost:1234/v1/chat/completions",
            AppCatalog.localHTTPModelNameEnvironmentKey: "llava",
            AppCatalog.localHTTPModelTimeoutEnvironmentKey: "6"
        ])

        XCTAssertEqual(arguments, [
            "--catalog",
            paths.catalogURL.path,
            "--preview-cache",
            paths.previewCacheRoot.path,
            "--local-http-model-endpoint",
            "http://localhost:1234/v1/chat/completions",
            "--local-http-model",
            "llava",
            "--local-http-model-timeout",
            "6"
        ])
    }

    func testRuntimePolicyRequiresSecurityScopeAndDisablesWorkerImportsWhenConfigured() {
        let policy = AppCatalog.runtimePolicy(environment: [
            AppCatalog.requiredSecurityScopedImportAccessEnvironmentKey: "1"
        ])

        XCTAssertTrue(policy.requiresSuccessfulSecurityScopedImportAccess)
        XCTAssertFalse(policy.workerImportsEnabled)
    }

    func testLoadModelWithWorkerExecutableUsesManagedWorkKindLimits() throws {
        let root = try makeTemporaryDirectory(named: "app-catalog-worker-limits")
        let paths = AppCatalog.defaultPaths(
            applicationSupportDirectory: root.appendingPathComponent("app-support", isDirectory: true)
        )
        let workerScriptURL = root.appendingPathComponent("record-worker.sh")
        let workerOutputURL = root.appendingPathComponent("worker-output.txt")
        try writeRecordingWorkerScript(to: workerScriptURL, outputURL: workerOutputURL)

        let model = try AppCatalog.loadModel(paths: paths, workerExecutableURL: workerScriptURL)

        XCTAssertEqual(model.backgroundWorkQueue.kindRunningLimits[.sourceScan], 1)
        XCTAssertEqual(model.backgroundWorkQueue.kindRunningLimits[.xmpSync], 1)
        XCTAssertEqual(model.backgroundWorkQueue.kindRunningLimits[.recognition], 1)
        XCTAssertNil(model.backgroundWorkQueue.kindRunningLimits[.previewGeneration])
    }

    func testLoadModelWithWorkerExecutableDispatchesPreviewRequestThroughWorkerProcess() throws {
        let root = try makeTemporaryDirectory(named: "app-catalog-worker")
        let paths = AppCatalog.defaultPaths(
            applicationSupportDirectory: root.appendingPathComponent("app-support", isDirectory: true)
        )
        let catalog = try AppCatalog.open(paths: paths)
        let asset = Asset(
            id: AssetID(rawValue: "worker-asset"),
            originalURL: root.appendingPathComponent("worker-asset.jpg"),
            volumeIdentifier: "local",
            fingerprint: FileFingerprint(size: 10, modificationDate: Date(timeIntervalSince1970: 10)),
            availability: .online,
            metadata: AssetMetadata()
        )
        try catalog.repository.upsert(asset)
        let workerScriptURL = root.appendingPathComponent("record-worker.sh")
        let workerOutputURL = root.appendingPathComponent("worker-output.txt")
        try writeRecordingWorkerScript(to: workerScriptURL, outputURL: workerOutputURL)

        let model = try AppCatalog.loadModel(paths: paths, workerExecutableURL: workerScriptURL)

        try model.requestPreview(assetID: asset.id, level: .large)

        XCTAssertTrue(waitUntil { file(workerOutputURL, contains: "--catalog \(paths.catalogURL.path)") })
        XCTAssertTrue(file(workerOutputURL, contains: "--preview-cache \(paths.previewCacheRoot.path)"))
        XCTAssertTrue(waitUntil { file(workerOutputURL, contains: "\"command\":\"generatePreview\"") })
        XCTAssertTrue(file(workerOutputURL, contains: "\"assetID\":\"worker-asset\""))
        XCTAssertTrue(file(workerOutputURL, contains: "\"level\":\"large\""))
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-app-catalog-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeRecordingWorkerScript(to url: URL, outputURL: URL) throws {
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail
        printf 'args:%s\\n' "$*" > "\(outputURL.path)"
        IFS= read -r line
        printf '%s\\n' "$line" >> "\(outputURL.path)"
        """
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func waitUntil(_ condition: () -> Bool) -> Bool {
        for _ in 0..<100 {
            if condition() {
                return true
            }
            Thread.sleep(forTimeInterval: 0.01)
        }
        return false
    }

    private func file(_ url: URL, contains expectedText: String) -> Bool {
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            return false
        }
        return contents.contains(expectedText)
    }

    private func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
