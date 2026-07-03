public enum BenchmarkCommand: Equatable {
    case catalogScale(count: Int)
    case importDeferred(count: Int)
    case metadataWrite(count: Int)
    case previewRender(count: Int)

    public static func parse(_ arguments: [String]) -> BenchmarkCommand {
        let userArguments = Array(arguments.dropFirst())
        guard let firstArgument = userArguments.first else {
            return .catalogScale(count: 100_000)
        }
        if firstArgument == "import-deferred" {
            return .importDeferred(count: Int(userArguments.dropFirst().first ?? "1000") ?? 1_000)
        }
        if firstArgument == "metadata-write" {
            return .metadataWrite(count: Int(userArguments.dropFirst().first ?? "1000") ?? 1_000)
        }
        if firstArgument == "preview-render" {
            return .previewRender(count: Int(userArguments.dropFirst().first ?? "250") ?? 250)
        }
        return .catalogScale(count: Int(firstArgument) ?? 100_000)
    }
}
