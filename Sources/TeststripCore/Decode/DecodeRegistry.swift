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

    public func capability(for url: URL) throws -> DecodeCapability {
        let ext = url.pathExtension.lowercased()
        for provider in providers where provider.canCatalog(url: url) {
            guard let capability = provider.capability(forFileExtension: ext) else {
                continue
            }
            return capability
        }
        throw TeststripError.unsupportedFormat("no decode capability for \(ext)")
    }
}
