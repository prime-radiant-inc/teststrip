import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

public struct ContactSeedSummary: Equatable, Sendable {
    public var seeded: Int = 0
    public var unchanged: Int = 0
    public var skippedNoFace: Int = 0
}

/// Turns address-book contact records into reference faces: embed the contact
/// photo's primary face and upsert a `contact_reference_faces` row, attaching to
/// an existing same-named person or minting a latent `contact:<id>` person id.
public struct ContactFaceSeeder: Sendable {
    private let detectFaces: @Sendable (CGImage) throws -> [AppleVisionFaceObservation]
    private let repository: CatalogRepository
    private let photoCache: ContactPhotoCache

    public init(
        detectFaces: @escaping @Sendable (CGImage) throws -> [AppleVisionFaceObservation],
        repository: CatalogRepository,
        photoCache: ContactPhotoCache
    ) {
        self.detectFaces = detectFaces
        self.repository = repository
        self.photoCache = photoCache
    }

    public func seed(records: [ContactRecord]) throws -> ContactSeedSummary {
        var summary = ContactSeedSummary()
        for record in records {
            let hash = Self.hash(record.imageData)
            if try repository.contactReferencePhotoHash(contactIdentifier: record.identifier) == hash {
                summary.unchanged += 1
                continue
            }
            guard let image = Self.decodeImage(record.imageData) else {
                summary.skippedNoFace += 1
                continue
            }
            let faces = try detectFaces(image)
            guard let best = faces.max(by: { ($0.captureQuality ?? -1) < ($1.captureQuality ?? -1) }) else {
                summary.skippedNoFace += 1
                continue
            }
            let personID = try repository.personID(matchingName: record.name) ?? "contact:\(record.identifier)"
            try Self.writePhoto(record.imageData, to: photoCache.url(for: record.identifier))
            try repository.upsertContactReferenceFace(
                contactIdentifier: record.identifier, personID: personID, name: record.name,
                embedding: best.featurePrintVector, boundingBox: best.boundingBox, photoHash: hash
            )
            summary.seeded += 1
        }
        return summary
    }

    private static func hash(_ data: Data) -> String {
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

    private static func writePhoto(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
