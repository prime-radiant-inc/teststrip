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
            return .writeCatalog
        }

        guard let lastSynced, let lastSyncedFingerprint = lastSynced.lastSyncedFingerprint else {
            return .importSidecar(try XMPPacket.parse(sidecarData).metadata)
        }

        let sidecarFingerprint = XMPSidecarStore.fingerprint(for: sidecarData)
        let localChanged = catalogGeneration != lastSynced.catalogGeneration
        let sidecarContentChanged = sidecarFingerprint != lastSyncedFingerprint
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
