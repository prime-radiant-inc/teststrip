import Foundation

public struct DecodeRegistry: Sendable {
    private let providers: [any DecodeProvider]

    public init(providers: [any DecodeProvider]) {
        self.providers = providers
    }

    public func provider(for url: URL) throws -> any DecodeProvider {
        if let provider = providers.first(where: { $0.canDecode(url: url) }) {
            return provider
        }
        let ext = url.pathExtension.lowercased()
        throw TeststripError.unsupportedFormat("no decode provider for \(ext)")
    }
}
