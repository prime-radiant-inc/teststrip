import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// One contact's decoded photo and its best detected face, ready to persist
/// as a `contact_reference_faces` row. Produced by `ContactFaceEmbedder`,
/// consumed by `ContactFacePersister`.
public struct EmbeddedContactFace: Equatable, Sendable {
    public let identifier: String
    public let name: String
    public let imageData: Data
    public let embedding: [Double]
    public let boundingBox: FaceBoundingBox
    public let photoHash: String

    public init(
        identifier: String, name: String, imageData: Data,
        embedding: [Double], boundingBox: FaceBoundingBox, photoHash: String
    ) {
        self.identifier = identifier
        self.name = name
        self.imageData = imageData
        self.embedding = embedding
        self.boundingBox = boundingBox
        self.photoHash = photoHash
    }
}

public struct ContactEmbedResult: Equatable, Sendable {
    public var embedded: [EmbeddedContactFace] = []
    public var unchanged: Int = 0
    public var skippedNoFace: Int = 0
    public var skippedUndecodable: Int = 0

    public init(
        embedded: [EmbeddedContactFace] = [], unchanged: Int = 0,
        skippedNoFace: Int = 0, skippedUndecodable: Int = 0
    ) {
        self.embedded = embedded
        self.unchanged = unchanged
        self.skippedNoFace = skippedNoFace
        self.skippedUndecodable = skippedUndecodable
    }
}

/// Decodes each contact photo and embeds its best face — the slow half of
/// Contacts seeding (Vision + CoreML, plus the `CNContactStore` fetch that
/// feeds it). `Sendable` and holds only a detector closure, so it can run
/// inside a `Task.detached` without capturing the catalog repository or the
/// app model; `ContactFacePersister` does the fast DB-write half on the main
/// actor from this type's output.
public struct ContactFaceEmbedder: Sendable {
    private let detectFaces: @Sendable (CGImage) throws -> [AppleVisionFaceObservation]

    public init(detectFaces: @escaping @Sendable (CGImage) throws -> [AppleVisionFaceObservation]) {
        self.detectFaces = detectFaces
    }

    /// `currentHashes` is the existing `contact_reference_faces` photo hash
    /// per contact identifier (`CatalogRepository.contactReferenceHashesByIdentifier()`)
    /// — a contact whose photo hash is unchanged since the last import is
    /// skipped without decoding or detecting.
    public func embed(records: [ContactRecord], currentHashes: [String: String]) throws -> ContactEmbedResult {
        var result = ContactEmbedResult()
        for record in records {
            let hash = Self.hash(record.imageData)
            if currentHashes[record.identifier] == hash {
                result.unchanged += 1
                continue
            }
            guard let image = Self.decodeImage(record.imageData) else {
                result.skippedUndecodable += 1
                continue
            }
            let faces = try detectFaces(image)
            guard let best = faces.max(by: { ($0.captureQuality ?? -1) < ($1.captureQuality ?? -1) }) else {
                result.skippedNoFace += 1
                continue
            }
            result.embedded.append(EmbeddedContactFace(
                identifier: record.identifier, name: record.name, imageData: record.imageData,
                embedding: best.featurePrintVector, boundingBox: best.boundingBox, photoHash: hash
            ))
        }
        return result
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes with EXIF orientation applied (contact photos can be rotated;
    /// `CGImageSourceCreateImageAtIndex` does not auto-apply orientation).
    private static func decodeImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                        kCGImageSourceThumbnailMaxPixelSize: 1024]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            ?? CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
