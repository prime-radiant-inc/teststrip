import Foundation

public struct DecodeMetadata: Codable, Equatable, Sendable {
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var cameraMake: String?
    public var cameraModel: String?
    public var lensModel: String?
    public var isoSpeed: Int?
    public var aperture: Double?
    public var shutterSpeed: Double?
    public var focalLength: Double?
    public var capturedAt: Date?
    public var provenance: ProviderProvenance

    public init(
        pixelWidth: Int,
        pixelHeight: Int,
        cameraMake: String? = nil,
        cameraModel: String? = nil,
        lensModel: String? = nil,
        isoSpeed: Int? = nil,
        aperture: Double? = nil,
        shutterSpeed: Double? = nil,
        focalLength: Double? = nil,
        capturedAt: Date? = nil,
        provenance: ProviderProvenance
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.cameraMake = cameraMake
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.isoSpeed = isoSpeed
        self.aperture = aperture
        self.shutterSpeed = shutterSpeed
        self.focalLength = focalLength
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
            aperture: aperture,
            shutterSpeed: shutterSpeed,
            focalLength: focalLength,
            capturedAt: capturedAt,
            provenance: provenance
        )
    }
}

public enum DecodeSupportLevel: String, Codable, Equatable, Sendable {
    case working
    case bestEffort
    case unsupported
}

public struct DecodeCapability: Codable, Equatable, Sendable {
    public var providerName: String
    public var fileExtension: String
    public var support: DecodeSupportLevel
    public var canReadMetadata: Bool
    public var canUseEmbeddedPreview: Bool
    public var canRenderPreview: Bool
    public var canRenderFullImage: Bool
    public var note: String

    public init(
        providerName: String,
        fileExtension: String,
        support: DecodeSupportLevel,
        canReadMetadata: Bool,
        canUseEmbeddedPreview: Bool,
        canRenderPreview: Bool,
        canRenderFullImage: Bool,
        note: String
    ) {
        self.providerName = providerName
        self.fileExtension = fileExtension.lowercased()
        self.support = support
        self.canReadMetadata = canReadMetadata
        self.canUseEmbeddedPreview = canUseEmbeddedPreview
        self.canRenderPreview = canRenderPreview
        self.canRenderFullImage = canRenderFullImage
        self.note = note
    }
}

public protocol DecodeProvider: Sendable {
    var name: String { get }
    func canDecode(url: URL) -> Bool
    func canCatalog(url: URL) -> Bool
    func capability(forFileExtension fileExtension: String) -> DecodeCapability?
    func metadata(for url: URL) throws -> DecodeMetadata
}

public extension DecodeProvider {
    func canCatalog(url: URL) -> Bool {
        canDecode(url: url)
    }

    func capability(forFileExtension fileExtension: String) -> DecodeCapability? {
        let normalizedExtension = fileExtension.lowercased()
        let supported = canDecode(url: URL(fileURLWithPath: "/tmp/photo.\(normalizedExtension)"))
        return DecodeCapability(
            providerName: name,
            fileExtension: normalizedExtension,
            support: supported ? .bestEffort : .unsupported,
            canReadMetadata: supported,
            canUseEmbeddedPreview: false,
            canRenderPreview: false,
            canRenderFullImage: false,
            note: supported
                ? "Provider accepts this extension but has not declared detailed capabilities."
                : "Provider does not accept this extension."
        )
    }
}
