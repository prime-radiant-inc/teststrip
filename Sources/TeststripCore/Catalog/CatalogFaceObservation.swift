import Foundation

public struct FaceBoundingBox: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct FaceID: Hashable, Sendable {
    public var assetID: AssetID
    public var faceIndex: Int

    public init(assetID: AssetID, faceIndex: Int) {
        self.assetID = assetID
        self.faceIndex = faceIndex
    }
}

public struct CatalogFaceObservation: Equatable, Sendable {
    public var assetID: AssetID
    public var faceIndex: Int
    public var boundingBox: FaceBoundingBox
    public var captureQuality: Double?
    public var embedding: [Double]
    public var provenance: ProviderProvenance

    public init(
        assetID: AssetID,
        faceIndex: Int,
        boundingBox: FaceBoundingBox,
        captureQuality: Double?,
        embedding: [Double],
        provenance: ProviderProvenance
    ) {
        self.assetID = assetID
        self.faceIndex = faceIndex
        self.boundingBox = boundingBox
        self.captureQuality = captureQuality
        self.embedding = embedding
        self.provenance = provenance
    }

    public var faceID: FaceID {
        FaceID(assetID: assetID, faceIndex: faceIndex)
    }
}
