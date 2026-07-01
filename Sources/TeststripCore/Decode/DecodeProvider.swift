import Foundation

public struct DecodeMetadata: Codable, Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var provenance: ProviderProvenance

    public init(pixelWidth: Int, pixelHeight: Int, provenance: ProviderProvenance) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.provenance = provenance
    }
}

public protocol DecodeProvider: Sendable {
    var name: String { get }
    func canDecode(url: URL) -> Bool
    func metadata(for url: URL) throws -> DecodeMetadata
}
