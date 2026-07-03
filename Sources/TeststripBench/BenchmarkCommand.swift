import Foundation

public enum BenchmarkCommand: Equatable {
    case catalogScale(count: Int)
    case importDeferred(count: Int)
    case localHTTPSmoke(endpoint: URL, model: String, imagePath: String?, timeout: TimeInterval)
    case metadataWrite(count: Int)
    case previewRender(count: Int)
    case seedAppCatalog(applicationSupportDirectory: URL, count: Int)

    public static func parse(_ arguments: [String]) -> BenchmarkCommand {
        let userArguments = Array(arguments.dropFirst())
        guard let firstArgument = userArguments.first else {
            return .catalogScale(count: 100_000)
        }
        if firstArgument == "import-deferred" {
            return .importDeferred(count: Int(userArguments.dropFirst().first ?? "1000") ?? 1_000)
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
        if firstArgument == "preview-render" {
            return .previewRender(count: Int(userArguments.dropFirst().first ?? "250") ?? 250)
        }
        if firstArgument == "seed-app-catalog" {
            let directory = userArguments.dropFirst().first ?? FileManager.default.currentDirectoryPath
            let count = Int(userArguments.dropFirst(2).first ?? "24") ?? 24
            return .seedAppCatalog(applicationSupportDirectory: URL(fileURLWithPath: directory), count: count)
        }
        return .catalogScale(count: Int(firstArgument) ?? 100_000)
    }
}
