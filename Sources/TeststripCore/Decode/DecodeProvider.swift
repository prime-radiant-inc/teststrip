import Foundation

public struct DecodeMetadata: Codable, Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var isoSpeed: Int?
    public var capturedAt: Date?
    public var provenance: ProviderProvenance

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        isoSpeed: Int? = nil,
        capturedAt: Date? = nil,
        provenance: ProviderProvenance
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.isoSpeed = isoSpeed
        self.capturedAt = capturedAt
        self.provenance = provenance
    }

    public var assetTechnicalMetadata: AssetTechnicalMetadata {
        AssetTechnicalMetadata(
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight,
            cameraMake: cameraMake,
            cameraModel: cameraModel,
            lensModel: lensModel,
            isoSpeed: isoSpeed,
            capturedAt: capturedAt,
            provenance: provenance
        )
    }
}

public protocol DecodeProvider: Sendable {
    var name: String { get }
    func canDecode(url: URL) -> Bool
    func metadata(for url: URL) throws -> DecodeMetadata
}
