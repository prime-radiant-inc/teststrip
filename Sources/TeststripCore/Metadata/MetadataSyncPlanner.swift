import Foundation

public enum MetadataSyncDecision: Equatable, Sendable {
    case upToDate
    case writeCatalog
    case importSidecar(AssetMetadata)
    case conflict(catalogMetadata: AssetMetadata, sidecarMetadata: AssetMetadata)
}

public struct MetadataSyncPlanner: Sendable {
    public init() {}

    public func decision(
        catalogMetadata: AssetMetadata,
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
            return catalogMetadata.hasWrittenPortableMetadata ? .writeCatalog : .upToDate
        }

        guard let lastSynced, let lastSyncedFingerprint = lastSynced.lastSyncedFingerprint else {
            return .importSidecar(try XMPPacket.parse(sidecarData).metadata)
        }

        let sidecarFingerprint = XMPSidecarStore.fingerprint(for: sidecarData)
        let sidecarContentChanged = sidecarFingerprint != lastSyncedFingerprint
        // Whether the catalog changed locally must key on the CONFIRMED
        // projection, not raw catalog_generation: promoting an AI label (an
        // autopilot/face-group confirmation elsewhere) bumps catalog_generation
        // without changing what the sidecar would contain, and must not queue a
        // rewrite of an already-synced sidecar with no user gesture behind it.
        // When the sidecar hasn't moved since the last sync checkpoint
        // (!sidecarContentChanged), its parsed content IS that checkpoint's
        // confirmed metadata — XMP never carries AI-unconfirmed markers (see
        // AssetMetadata.confirmedProjection) — so comparing against it directly
        // is exact. When the sidecar HAS moved externally, that comparison is no
        // longer meaningful (current disk content isn't the last-sync
        // checkpoint), so fall back to the raw generation signal there, same as
        // before.
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
            return .importSidecar(try XMPPacket.parse(sidecarData).metadata)
        case (true, true, _):
            return .conflict(
                catalogMetadata: catalogMetadata,
                sidecarMetadata: try XMPPacket.parse(sidecarData).metadata
            )
        }
    }
}
