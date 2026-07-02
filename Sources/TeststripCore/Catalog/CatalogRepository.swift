import Foundation

public final class CatalogRepository {
    private let database: CatalogDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: CatalogDatabase) {
        self.database = database
        encoder.dateEncodingStrategy = .secondsSince1970
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    public func upsert(_ asset: Asset) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO assets (id, original_path, volume_identifier, fingerprint_json, availability, metadata_json, catalog_generation, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                original_path = excluded.original_path,
                volume_identifier = excluded.volume_identifier,
                fingerprint_json = excluded.fingerprint_json,
                availability = excluded.availability,
                metadata_json = excluded.metadata_json,
                catalog_generation = assets.catalog_generation + 1,
                updated_at = excluded.updated_at
            """,
            bindings: [
                asset.id.rawValue,
                asset.originalURL.path,
                asset.volumeIdentifier ?? "",
                try encode(asset.fingerprint),
                asset.availability.rawValue,
                try encode(asset.metadata),
                now,
                now
            ]
        )
    }

    public func asset(id: AssetID) throws -> Asset {
        let rows = try database.rows("SELECT * FROM assets WHERE id = ?", bindings: [id.rawValue])
        guard let row = rows.first else {
            throw CatalogError.notFound(id.rawValue)
        }
        return try decodeAsset(row)
    }

    public func asset(originalURL: URL) throws -> Asset? {
        let rows = try database.rows(
            "SELECT * FROM assets WHERE original_path = ? LIMIT 1",
            bindings: [originalURL.path]
        )
        return try rows.first.map(decodeAsset)
    }

    public func allAssets(limit: Int, offset: Int = 0) throws -> [Asset] {
        let rows = try database.rows(
            "SELECT * FROM assets ORDER BY rowid ASC LIMIT ? OFFSET ?",
            bindings: ["\(limit)", "\(offset)"]
        )
        return try rows.map(decodeAsset)
    }

    public func assetCount() throws -> Int {
        let rows = try database.rows("SELECT COUNT(*) AS count FROM assets")
        guard let countString = rows.first?["count"], let count = Int(countString) else {
            throw CatalogError.sqlite("asset count query returned no count")
        }
        return count
    }

    public func updateMetadata(assetID: AssetID, _ update: (inout AssetMetadata) throws -> Void) throws {
        var asset = try asset(id: assetID)
        try update(&asset.metadata)
        try upsert(asset)
    }

    public func updateAvailability(assetID: AssetID, availability: SourceAvailability) throws {
        _ = try asset(id: assetID)
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            UPDATE assets
            SET availability = ?,
                updated_at = ?
            WHERE id = ?
            """,
            bindings: [
                availability.rawValue,
                now,
                assetID.rawValue
            ]
        )
    }

    public func catalogGeneration(assetID: AssetID) throws -> Int {
        let rows = try database.rows("SELECT catalog_generation FROM assets WHERE id = ?", bindings: [assetID.rawValue])
        guard let value = rows.first?["catalog_generation"], let intValue = Int(value) else {
            throw CatalogError.notFound(assetID.rawValue)
        }
        return intValue
    }

    public func recordMetadataSyncPending(_ item: MetadataSyncItem) throws {
        try upsertMetadataSyncState(item, status: "pending")
    }

    public func pendingMetadataSyncItems() throws -> [MetadataSyncItem] {
        let rows = try database.rows(
            """
            SELECT asset_id, sidecar_path, catalog_generation, last_synced_fingerprint
            FROM metadata_sync_state
            WHERE status = 'pending'
            ORDER BY updated_at ASC
            """
        )
        return try rows.map(decodeMetadataSyncItem)
    }

    public func markMetadataSynced(
        assetID: AssetID,
        sidecarURL: URL,
        catalogGeneration: Int,
        fingerprint: String
    ) throws {
        try upsertMetadataSyncState(
            MetadataSyncItem(
                assetID: assetID,
                sidecarURL: sidecarURL,
                catalogGeneration: catalogGeneration,
                lastSyncedFingerprint: fingerprint
            ),
            status: "synced"
        )
    }

    public func lastMetadataSyncFingerprint(assetID: AssetID) throws -> String? {
        let rows = try database.rows(
            "SELECT last_synced_fingerprint FROM metadata_sync_state WHERE asset_id = ?",
            bindings: [assetID.rawValue]
        )
        guard let fingerprint = rows.first?["last_synced_fingerprint"], !fingerprint.isEmpty else {
            return nil
        }
        return fingerprint
    }

    private func decodeAsset(_ row: [String: String]) throws -> Asset {
        guard let id = row["id"],
              let path = row["original_path"],
              let fingerprintJSON = row["fingerprint_json"],
              let availabilityRaw = row["availability"],
              let availability = SourceAvailability(rawValue: availabilityRaw),
              let metadataJSON = row["metadata_json"] else {
            throw CatalogError.sqlite("asset row is missing required columns")
        }

        return Asset(
            id: AssetID(rawValue: id),
            originalURL: URL(fileURLWithPath: path),
            volumeIdentifier: row["volume_identifier"].flatMap { $0.isEmpty ? nil : $0 },
            fingerprint: try decode(FileFingerprint.self, from: fingerprintJSON),
            availability: availability,
            metadata: try decode(AssetMetadata.self, from: metadataJSON)
        )
    }

    private func upsertMetadataSyncState(_ item: MetadataSyncItem, status: String) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO metadata_sync_state (
                asset_id,
                sidecar_path,
                catalog_generation,
                last_synced_fingerprint,
                status,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id) DO UPDATE SET
                sidecar_path = excluded.sidecar_path,
                catalog_generation = excluded.catalog_generation,
                last_synced_fingerprint = excluded.last_synced_fingerprint,
                status = excluded.status,
                updated_at = excluded.updated_at
            """,
            bindings: [
                item.assetID.rawValue,
                item.sidecarURL.path,
                "\(item.catalogGeneration)",
                item.lastSyncedFingerprint ?? "",
                status,
                now
            ]
        )
    }

    private func decodeMetadataSyncItem(_ row: [String: String]) throws -> MetadataSyncItem {
        guard let assetID = row["asset_id"],
              let sidecarPath = row["sidecar_path"],
              let generationValue = row["catalog_generation"],
              let generation = Int(generationValue),
              let fingerprint = row["last_synced_fingerprint"] else {
            throw CatalogError.sqlite("metadata sync row is missing required columns")
        }
        return MetadataSyncItem(
            assetID: AssetID(rawValue: assetID),
            sidecarURL: URL(fileURLWithPath: sidecarPath),
            catalogGeneration: generation,
            lastSyncedFingerprint: fingerprint.isEmpty ? nil : fingerprint
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8)!
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try decoder.decode(type, from: Data(string.utf8))
    }
}
