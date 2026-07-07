import Foundation

public enum BenchmarkCommand: Equatable {
    public static let catalogBaselineCount = 500_000
    public static let catalogStressCount = 1_000_000

    case catalogScale(count: Int)
    case cardImportSmoke(count: Int)
    case importDeferred(count: Int)
    case importPreviewDrain(count: Int)
    case localHTTPSmoke(endpoint: URL, model: String, imagePath: String?, timeout: TimeInterval)
    case metadataWrite(count: Int)
    case offlineReconnectSmoke
    case sourceAvailability(count: Int)
    case previewRender(count: Int)
    case workerRecoverySmoke(count: Int)
    case realCorpusSmoke(photoDirectory: URL)
    case seedGeoFixtures(directory: URL, count: Int)
    case seedDupFixtures(directory: URL)
    case samplePreviewRender(photoDirectory: URL)
    case seedAppCatalog(applicationSupportDirectory: URL, count: Int)
    case seedRealCorpusCatalog(applicationSupportDirectory: URL, photoDirectory: URL)
    case seedSampleCatalog(applicationSupportDirectory: URL, photoDirectory: URL)

    public static func parse(_ arguments: [String]) -> BenchmarkCommand {
        let userArguments = Array(arguments.dropFirst())
        guard let firstArgument = userArguments.first else {
            return .catalogScale(count: catalogBaselineCount)
        }
        if firstArgument == "catalog-baseline" {
            return .catalogScale(count: catalogBaselineCount)
        }
        if firstArgument == "catalog-stress" {
            return .catalogScale(count: catalogStressCount)
        }
        if firstArgument == "card-import-smoke" {
            return .cardImportSmoke(count: Int(userArguments.dropFirst().first ?? "12") ?? 12)
        }
        if firstArgument == "import-deferred" {
            return .importDeferred(count: Int(userArguments.dropFirst().first ?? "1000") ?? 1_000)
        }
        if firstArgument == "import-preview-drain" {
            return .importPreviewDrain(count: Int(userArguments.dropFirst().first ?? "100") ?? 100)
        }
        if firstArgument == "local-http-smoke" {
            let endpointString = userArguments.dropFirst().first ?? "http://localhost:1234/v1/chat/completions"
            let endpoint = URL(string: endpointString) ?? URL(string: "http://localhost:1234/v1/chat/completions")!
            let model = userArguments.dropFirst(2).first ?? "llava"
            let imagePath = userArguments.dropFirst(3).first
            let timeout = TimeInterval(userArguments.dropFirst(4).first ?? "30") ?? 30
            return .localHTTPSmoke(endpoint: endpoint, model: model, imagePath: imagePath, timeout: timeout)
        }
        if firstArgument == "metadata-write" {
            return .metadataWrite(count: Int(userArguments.dropFirst().first ?? "1000") ?? 1_000)
        }
        if firstArgument == "offline-reconnect-smoke" {
            return .offlineReconnectSmoke
        }
        if firstArgument == "source-availability" {
            return .sourceAvailability(count: Int(userArguments.dropFirst().first ?? "1000") ?? 1_000)
        }
        if firstArgument == "preview-render" {
            return .previewRender(count: Int(userArguments.dropFirst().first ?? "250") ?? 250)
        }
        if firstArgument == "worker-recovery-smoke" {
            return .workerRecoverySmoke(count: Int(userArguments.dropFirst().first ?? "24") ?? 24)
        }
        if firstArgument == "real-corpus-smoke" {
            let directory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            return .realCorpusSmoke(photoDirectory: URL(fileURLWithPath: directory))
        }
        if firstArgument == "sample-preview-render" {
            let directory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            return .samplePreviewRender(photoDirectory: URL(fileURLWithPath: directory))
        }
        if firstArgument == "seed-geo-fixtures" {
            let directory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            let count = Int(userArguments.dropFirst(2).first ?? "12") ?? 12
            return .seedGeoFixtures(directory: URL(fileURLWithPath: directory), count: count)
        }
        if firstArgument == "seed-dup-fixtures" {
            let directory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            return .seedDupFixtures(directory: URL(fileURLWithPath: directory))
        }
        if firstArgument == "seed-app-catalog" {
            let directory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            let count = Int(userArguments.dropFirst(2).first ?? "24") ?? 24
            return .seedAppCatalog(applicationSupportDirectory: URL(fileURLWithPath: directory), count: count)
        }
        if firstArgument == "seed-real-corpus-catalog" {
            let applicationSupportDirectory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            let photoDirectory = userArguments.dropFirst(2).first ?? FileManager.default.currentDirectoryPath
            return .seedRealCorpusCatalog(
                applicationSupportDirectory: URL(fileURLWithPath: applicationSupportDirectory),
                photoDirectory: URL(fileURLWithPath: photoDirectory)
            )
        }
        if firstArgument == "seed-sample-catalog" {
            let applicationSupportDirectory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            let photoDirectory = userArguments.dropFirst(2).first ?? FileManager.default.currentDirectoryPath
            return .seedSampleCatalog(
                applicationSupportDirectory: URL(fileURLWithPath: applicationSupportDirectory),
                photoDirectory: URL(fileURLWithPath: photoDirectory)
            )
        }
        return .catalogScale(count: Int(firstArgument) ?? catalogBaselineCount)
    }
}
