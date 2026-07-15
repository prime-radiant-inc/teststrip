import CoreGraphics
import Foundation

public struct ContactSeedSummary: Equatable, Sendable {
    public var seeded: Int = 0
    public var unchanged: Int = 0
    public var skippedNoFace: Int = 0
}

/// Persists an embed phase's output (`ContactFaceEmbedder.embed`) to the
/// catalog: writes the cached reference photo and upserts
/// `contact_reference_faces`, attaching to an existing same-named person or
/// minting a latent `contact:<id>` person id. Fast, DB-only work — safe to
/// run on the main actor, unlike the embedder's decode+detect.
public struct ContactFacePersister {
    private let repository: CatalogRepository
    private let photoCache: ContactPhotoCache

    public init(repository: CatalogRepository, photoCache: ContactPhotoCache) {
        self.repository = repository
        self.photoCache = photoCache
    }

    public func persist(_ result: ContactEmbedResult) throws -> ContactSeedSummary {
        var summary = ContactSeedSummary(unchanged: result.unchanged, skippedNoFace: result.skippedNoFace)
        for face in result.embedded {
            let personID = try repository.personID(matchingName: face.name) ?? "contact:\(face.identifier)"
            try Self.writePhoto(face.imageData, to: photoCache.url(for: face.identifier))
            try repository.upsertContactReferenceFace(
                contactIdentifier: face.identifier, personID: personID, name: face.name,
                embedding: face.embedding, boundingBox: face.boundingBox, photoHash: face.photoHash
            )
            summary.seeded += 1
        }
        return summary
    }

    private static func writePhoto(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}

/// Turns address-book contact records into reference faces: embed the contact
/// photo's primary face and upsert a `contact_reference_faces` row, attaching to
/// an existing same-named person or minting a latent `contact:<id>` person id.
/// Combines `ContactFaceEmbedder` (decode+detect, off-main-thread-safe) and
/// `ContactFacePersister` (the DB write) for callers that don't need to split
/// the work across a thread boundary — `AppModel.importFacesFromContacts()`
/// does split it, running the embedder in a `Task.detached` and only
/// `ContactFacePersister` on the main actor.
public struct ContactFaceSeeder {
    private let detectFaces: @Sendable (CGImage) throws -> [AppleVisionFaceObservation]
    private let repository: CatalogRepository
    private let persister: ContactFacePersister

    public init(
        detectFaces: @escaping @Sendable (CGImage) throws -> [AppleVisionFaceObservation],
        repository: CatalogRepository,
        photoCache: ContactPhotoCache
    ) {
        self.detectFaces = detectFaces
        self.repository = repository
        self.persister = ContactFacePersister(repository: repository, photoCache: photoCache)
    }

    public func seed(records: [ContactRecord]) throws -> ContactSeedSummary {
        let currentHashes = try repository.contactReferenceHashesByIdentifier()
        let result = try ContactFaceEmbedder(detectFaces: detectFaces).embed(records: records, currentHashes: currentHashes)
        return try persister.persist(result)
    }
}
