import Foundation

public struct SidecarRescanSummary: Equatable, Sendable {
    /// Every synced row the rescan walked (including those the cheap mtime
    /// gate skipped without reading) — the "Checked N sidecars" number.
    public var scannedCount: Int
    /// Synced rows whose sidecar passed the cheap mtime gate and were read.
    public var checkedCount: Int
    /// Rows re-marked pending (sidecar changed out-of-band, or vanished).
    public var pendingCount: Int
    /// Rows marked conflict (sidecar and catalog both changed since sync).
    public var conflictCount: Int

    public init(scannedCount: Int = 0, checkedCount: Int = 0, pendingCount: Int = 0, conflictCount: Int = 0) {
        self.scannedCount = scannedCount
        self.checkedCount = checkedCount
        self.pendingCount = pendingCount
        self.conflictCount = conflictCount
    }
}

/// Detects out-of-band sidecar edits after a clean sync (Jesse's ruling
/// 2026-07-11; closes the activity-006 product gap: an edited sidecar used
/// to stay "synced" forever). For every `metadata_sync_state` row with
/// status `synced`, a cheap stat gate (file mtime vs the recorded sync
/// instant) skips untouched sidecars without reading them; changed ones are
/// re-planned with the existing `MetadataSyncPlanner` semantics — sidecar
/// change alone re-queues as pending (the worker then imports/rewrites),
/// sidecar + catalog both changed records a conflict. No schema change:
/// `last_synced_fingerprint` (content hash) and `updated_at` already record
/// what the check needs.
public struct SidecarRescanService: Sendable {
    public init() {}

    /// Rescans synced sidecars, optionally restricted to `assetIDs` (the
    /// menu command's current scope); nil means every synced row. Batched
    /// by the caller as needed — each row costs one stat, plus one read
    /// only when the stat says the file moved on.
    public func rescanSyncedSidecars(
        repository: CatalogRepository,
        assetIDs: Set<AssetID>? = nil
    ) throws -> SidecarRescanSummary {
        var summary = SidecarRescanSummary()
        for item in try repository.syncedMetadataSyncItems() {
            if let assetIDs, !assetIDs.contains(item.assetID) { continue }
            summary.scannedCount += 1
            let attributes = try? FileManager.default.attributesOfItem(atPath: item.sidecarURL.path)
            let modificationDate = attributes?[.modificationDate] as? Date
            if let modificationDate,
               let lastSyncedAt = item.lastSyncedAt,
               modificationDate <= lastSyncedAt {
                // Cheap gate: untouched since the recorded sync — skip
                // without reading the file.
                continue
            }
            summary.checkedCount += 1
            let sidecarData = try? Data(contentsOf: item.sidecarURL)
            let asset: Asset
            let catalogGeneration: Int
            do {
                asset = try repository.asset(id: item.assetID)
                catalogGeneration = try repository.catalogGeneration(assetID: item.assetID)
            } catch {
                continue // asset removed since; nothing to re-sync
            }
            let decision: MetadataSyncDecision
            do {
                decision = try MetadataSyncPlanner().decision(
                    catalogMetadata: asset.metadata,
                    catalogGeneration: catalogGeneration,
                    lastSynced: item,
                    sidecarData: sidecarData,
                    sidecarModificationDate: modificationDate
                )
            } catch {
                // Unparsable (possibly torn) sidecar: leave it for the
                // worker's torn-write handling on the next real sync pass.
                continue
            }
            switch decision {
            case .upToDate:
                break
            case .conflict:
                try repository.recordMetadataSyncConflict(item)
                summary.conflictCount += 1
            case .importSidecar, .writeCatalog:
                try repository.recordMetadataSyncPending(item)
                summary.pendingCount += 1
            }
        }
        return summary
    }
}
