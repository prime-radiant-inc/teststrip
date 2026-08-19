import Foundation

public enum MetadataSyncDecision: Equatable, Sendable {
    case upToDate
    case writeCatalog
    case importSidecar(metadata: AssetMetadata, rotation: Int?)
    case conflict(catalogMetadata: AssetMetadata, sidecarMetadata: AssetMetadata)
}

public struct MetadataSyncPlanner: Sendable {
    public init() {}

    public func decision(
        catalogMetadata: AssetMetadata,
        catalogRotation: Int? = nil,
        catalogGeneration: Int,
        lastSynced: MetadataSyncItem?,
        sidecarData: Data?,
        sidecarModificationDate: Date? = nil
    ) throws -> MetadataSyncDecision {
        guard let sidecarData else {
            // Non-destructive invariant: a sidecar exists only after the user
            // sets a portable field. Untouched metadata (rating 0, nothing
            // else set) with no sidecar on disk must never trigger a write —
            // otherwise merely browsing an asset would spray Rating=0
            // sidecars next to the originals.
            let hasPortableMetadata = catalogMetadata.hasWrittenPortableMetadata || (catalogRotation ?? 0) != 0
            return hasPortableMetadata ? .writeCatalog : .upToDate
        }

        guard let lastSynced, let lastSyncedFingerprint = lastSynced.lastSyncedFingerprint else {
            let packet = try XMPPacket.parse(sidecarData)
            return .importSidecar(metadata: packet.metadata, rotation: packet.rotation)
        }

        let sidecarFingerprint = XMPSidecarStore.fingerprint(for: sidecarData)
        let sidecarContentChanged = sidecarFingerprint != lastSyncedFingerprint
        let localChanged = sidecarContentChanged
            ? catalogGeneration != lastSynced.catalogGeneration
            : try catalogMetadata.confirmedProjection != XMPPacket.parse(sidecarData).metadata
        let sidecarFreshened = sidecarModificationDate.map { modificationDate in
            lastSynced.lastSyncedAt.map { modificationDate > $0 } ?? false
        } ?? false

        switch (localChanged, sidecarContentChanged, sidecarFreshened) {
        case (false, false, false):
            return .upToDate
        case (true, false, _):
            return .writeCatalog
        case (false, true, _), (false, false, true):
            let packet = try XMPPacket.parse(sidecarData)
            return .importSidecar(metadata: packet.metadata, rotation: packet.rotation)
        case (true, true, _):
            return .conflict(
                catalogMetadata: catalogMetadata,
                sidecarMetadata: try XMPPacket.parse(sidecarData).metadata
            )
        }
    }
}
