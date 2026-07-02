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
            INSERT INTO assets (id, original_path, volume_identifier, fingerprint_json, availability, metadata_json, technical_metadata_json, catalog_generation, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                original_path = excluded.original_path,
                volume_identifier = excluded.volume_identifier,
                fingerprint_json = excluded.fingerprint_json,
                availability = excluded.availability,
                metadata_json = excluded.metadata_json,
                technical_metadata_json = excluded.technical_metadata_json,
                catalog_generation = CASE
                    WHEN assets.metadata_json = excluded.metadata_json THEN assets.catalog_generation
                    ELSE assets.catalog_generation + 1
                END,
                updated_at = excluded.updated_at
            """,
            bindings: [
                asset.id.rawValue,
                asset.originalURL.path,
                asset.volumeIdentifier ?? "",
                try encode(asset.fingerprint),
                asset.availability.rawValue,
                try encode(asset.metadata),
                try asset.technicalMetadata.map(encode) ?? "",
                now,
                now
            ]
        )
    }

    public func upsert(_ assets: [Asset]) throws {
        guard !assets.isEmpty else { return }
        try database.transaction {
            for asset in assets {
                try upsert(asset)
            }
        }
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

    public func allAssets(matching query: SetQuery, limit: Int, offset: Int = 0) throws -> [Asset] {
        let compiledQuery = try compile(query)
        let rows = try database.rows(
            "SELECT * FROM assets\(compiledQuery.whereSQL) ORDER BY rowid ASC LIMIT ? OFFSET ?",
            bindings: compiledQuery.bindings + ["\(limit)", "\(offset)"]
        )
        return try rows.map(decodeAsset)
    }

    public func assets(ids: [AssetID], limit: Int, offset: Int = 0) throws -> [Asset] {
        guard limit > 0 else { return [] }
        var skippedAssetCount = 0
        var loadedAssets: [Asset] = []
        for chunk in Self.chunks(ids, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                "SELECT * FROM assets WHERE id IN (\(placeholders))",
                bindings: chunk.map(\.rawValue)
            )
            var assetsByID: [AssetID: Asset] = [:]
            for asset in try rows.map(decodeAsset) {
                assetsByID[asset.id] = asset
            }
            for id in chunk {
                guard let asset = assetsByID[id] else { continue }
                if skippedAssetCount < offset {
                    skippedAssetCount += 1
                    continue
                }
                loadedAssets.append(asset)
                if loadedAssets.count == limit {
                    return loadedAssets
                }
            }
        }
        return loadedAssets
    }

    public func assetCount(ids: [AssetID]) throws -> Int {
        var count = 0
        for chunk in Self.chunks(ids, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                "SELECT COUNT(*) AS count FROM assets WHERE id IN (\(placeholders))",
                bindings: chunk.map(\.rawValue)
            )
            guard let countString = rows.first?["count"], let chunkCount = Int(countString) else {
                throw CatalogError.sqlite("asset ID count query returned no count")
            }
            count += chunkCount
        }
        return count
    }

    public func assetOffset(id: AssetID) throws -> Int {
        let rowIDRows = try database.rows("SELECT rowid FROM assets WHERE id = ?", bindings: [id.rawValue])
        guard let rowID = rowIDRows.first?["rowid"] else {
            throw CatalogError.notFound(id.rawValue)
        }
        let offsetRows = try database.rows(
            "SELECT COUNT(*) AS offset FROM assets WHERE rowid < ?",
            bindings: [rowID]
        )
        guard let offsetString = offsetRows.first?["offset"], let offset = Int(offsetString) else {
            throw CatalogError.sqlite("asset offset query returned no count")
        }
        return offset
    }

    public func assetCount() throws -> Int {
        let rows = try database.rows("SELECT COUNT(*) AS count FROM assets")
        guard let countString = rows.first?["count"], let count = Int(countString) else {
            throw CatalogError.sqlite("asset count query returned no count")
        }
        return count
    }

    public func assetCount(matching query: SetQuery) throws -> Int {
        let compiledQuery = try compile(query)
        let rows = try database.rows(
            "SELECT COUNT(*) AS count FROM assets\(compiledQuery.whereSQL)",
            bindings: compiledQuery.bindings
        )
        guard let countString = rows.first?["count"], let count = Int(countString) else {
            throw CatalogError.sqlite("asset count query returned no count")
        }
        return count
    }

    public func upsert(_ assetSet: AssetSet) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO asset_sets (id, name, membership_json, starred, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                membership_json = excluded.membership_json,
                starred = excluded.starred,
                updated_at = excluded.updated_at
            """,
            bindings: [
                assetSet.id.rawValue,
                assetSet.name,
                try encode(assetSet.membership),
                assetSet.starred ? "1" : "0",
                now,
                now
            ]
        )
    }

    public func assetSet(id: AssetSetID) throws -> AssetSet {
        let rows = try database.rows("SELECT * FROM asset_sets WHERE id = ?", bindings: [id.rawValue])
        guard let row = rows.first else {
            throw CatalogError.notFound(id.rawValue)
        }
        return try decodeAssetSet(row)
    }

    public func assetSets(starredOnly: Bool = false) throws -> [AssetSet] {
        let rows: [[String: String]]
        if starredOnly {
            rows = try database.rows("SELECT * FROM asset_sets WHERE starred = 1 ORDER BY rowid ASC")
        } else {
            rows = try database.rows("SELECT * FROM asset_sets ORDER BY rowid ASC")
        }
        return try rows.map(decodeAssetSet)
    }

    public func save(_ session: WorkSession) throws {
        try database.execute(
            """
            INSERT INTO work_sessions (
                id,
                kind,
                intent,
                title,
                detail,
                status,
                input_set_ids_json,
                output_set_ids_json,
                completed_unit_count,
                total_unit_count,
                failure_count,
                starred,
                created_at,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                kind = excluded.kind,
                intent = excluded.intent,
                title = excluded.title,
                detail = excluded.detail,
                status = excluded.status,
                input_set_ids_json = excluded.input_set_ids_json,
                output_set_ids_json = excluded.output_set_ids_json,
                completed_unit_count = excluded.completed_unit_count,
                total_unit_count = excluded.total_unit_count,
                failure_count = excluded.failure_count,
                starred = excluded.starred,
                updated_at = excluded.updated_at
            """,
            bindings: [
                session.id.rawValue,
                session.kind.rawValue,
                session.intent,
                session.title,
                session.detail,
                session.status.rawValue,
                try encode(session.inputSetIDs),
                try encode(session.outputSetIDs),
                "\(session.completedUnitCount)",
                session.totalUnitCount.map(String.init) ?? "",
                "\(session.failureCount)",
                session.starred ? "1" : "0",
                "\(session.createdAt.timeIntervalSince1970)",
                "\(session.updatedAt.timeIntervalSince1970)"
            ]
        )
    }

    public func session(id: WorkSessionID) throws -> WorkSession {
        let rows = try database.rows("SELECT * FROM work_sessions WHERE id = ?", bindings: [id.rawValue])
        guard let row = rows.first else {
            throw CatalogError.notFound(id.rawValue)
        }
        return try decodeWorkSession(row)
    }

    public func workSessions(limit: Int, starredOnly: Bool = false) throws -> [WorkSession] {
        guard limit > 0 else { return [] }
        let rows: [[String: String]]
        if starredOnly {
            rows = try database.rows(
                "SELECT * FROM work_sessions WHERE starred = 1 ORDER BY updated_at DESC LIMIT ?",
                bindings: ["\(limit)"]
            )
        } else {
            rows = try database.rows(
                "SELECT * FROM work_sessions ORDER BY updated_at DESC LIMIT ?",
                bindings: ["\(limit)"]
            )
        }
        return try rows.map(decodeWorkSession)
    }

    public func recordEvaluationSignals(_ signals: [EvaluationSignal]) throws {
        guard !signals.isEmpty else { return }
        try database.transaction {
            for signal in signals {
                try recordEvaluationSignal(signal)
            }
        }
    }

    public func evaluationSignals(assetID: AssetID) throws -> [EvaluationSignal] {
        let rows = try database.rows(
            """
            SELECT asset_id, kind, value_json, confidence, provenance_json
            FROM evaluation_signals
            WHERE asset_id = ?
            ORDER BY rowid ASC
            """,
            bindings: [assetID.rawValue]
        )
        return try rows.map(decodeEvaluationSignal)
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
        try metadataSyncItems(status: "pending")
    }

    public func recordPreviewGenerationPending(_ item: PreviewGenerationItem) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO preview_generation_queue (asset_id, level, updated_at)
            VALUES (?, ?, ?)
            ON CONFLICT(asset_id, level) DO UPDATE SET
                updated_at = excluded.updated_at
            """,
            bindings: [
                item.assetID.rawValue,
                item.level.rawValue,
                now
            ]
        )
    }

    public func markPreviewGenerated(assetID: AssetID, level: PreviewLevel) throws {
        try database.execute(
            "DELETE FROM preview_generation_queue WHERE asset_id = ? AND level = ?",
            bindings: [assetID.rawValue, level.rawValue]
        )
    }

    public func pendingPreviewGenerationItems(limit: Int? = nil) throws -> [PreviewGenerationItem] {
        if let limit, limit <= 0 {
            return []
        }
        var sql = """
        SELECT asset_id, level
        FROM preview_generation_queue
        ORDER BY updated_at ASC
        """
        var bindings: [String] = []
        if let limit {
            sql += " LIMIT ?"
            bindings.append("\(limit)")
        }
        let rows = try database.rows(sql, bindings: bindings)
        return try rows.map(decodePreviewGenerationItem)
    }

    public func metadataSyncConflictItems() throws -> [MetadataSyncItem] {
        try metadataSyncItems(status: "conflict")
    }

    public func metadataSyncItem(assetID: AssetID) throws -> MetadataSyncItem? {
        let rows = try database.rows(
            """
            SELECT asset_id, sidecar_path, catalog_generation, last_synced_fingerprint
            FROM metadata_sync_state
            WHERE asset_id = ?
            LIMIT 1
            """,
            bindings: [assetID.rawValue]
        )
        return try rows.first.map(decodeMetadataSyncItem)
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

    public func recordMetadataSyncConflict(_ item: MetadataSyncItem) throws {
        try upsertMetadataSyncState(item, status: "conflict")
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
            metadata: try decode(AssetMetadata.self, from: metadataJSON),
            technicalMetadata: try decodeTechnicalMetadata(row["technical_metadata_json"])
        )
    }

    private func decodeAssetSet(_ row: [String: String]) throws -> AssetSet {
        guard let id = row["id"],
              let name = row["name"],
              let membershipJSON = row["membership_json"],
              let starred = row["starred"] else {
            throw CatalogError.sqlite("asset set row is missing required columns")
        }

        return AssetSet(
            id: AssetSetID(rawValue: id),
            name: name,
            membership: try decode(AssetSet.Membership.self, from: membershipJSON),
            starred: starred == "1"
        )
    }

    private func decodeWorkSession(_ row: [String: String]) throws -> WorkSession {
        guard let id = row["id"],
              let kindRawValue = row["kind"],
              let kind = WorkSessionKind(rawValue: kindRawValue),
              let intent = row["intent"],
              let title = row["title"],
              let detail = row["detail"],
              let statusRawValue = row["status"],
              let status = WorkSessionStatus(rawValue: statusRawValue),
              let inputSetIDsJSON = row["input_set_ids_json"],
              let outputSetIDsJSON = row["output_set_ids_json"],
              let completedUnitCountValue = row["completed_unit_count"],
              let completedUnitCount = Int(completedUnitCountValue),
              let totalUnitCountValue = row["total_unit_count"],
              let failureCountValue = row["failure_count"],
              let failureCount = Int(failureCountValue),
              let starred = row["starred"],
              let createdAtValue = row["created_at"],
              let createdAtInterval = TimeInterval(createdAtValue),
              let updatedAtValue = row["updated_at"],
              let updatedAtInterval = TimeInterval(updatedAtValue) else {
            throw CatalogError.sqlite("work session row is missing required columns")
        }

        let totalUnitCount = totalUnitCountValue.isEmpty ? nil : Int(totalUnitCountValue)
        if !totalUnitCountValue.isEmpty, totalUnitCount == nil {
            throw CatalogError.sqlite("work session row has invalid total unit count")
        }

        return WorkSession(
            id: WorkSessionID(rawValue: id),
            kind: kind,
            intent: intent,
            title: title,
            detail: detail,
            status: status,
            inputSetIDs: try decode([AssetSetID].self, from: inputSetIDsJSON),
            outputSetIDs: try decode([AssetSetID].self, from: outputSetIDsJSON),
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            failureCount: failureCount,
            starred: starred == "1",
            createdAt: Date(timeIntervalSince1970: createdAtInterval),
            updatedAt: Date(timeIntervalSince1970: updatedAtInterval)
        )
    }

    private func recordEvaluationSignal(_ signal: EvaluationSignal) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO evaluation_signals (
                asset_id,
                kind,
                value_json,
                confidence,
                provenance_json,
                provider,
                model,
                version,
                settings_hash,
                created_at,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(asset_id, kind, provider, model, version, settings_hash) DO UPDATE SET
                value_json = excluded.value_json,
                confidence = excluded.confidence,
                provenance_json = excluded.provenance_json,
                updated_at = excluded.updated_at
            """,
            bindings: [
                signal.assetID.rawValue,
                signal.kind.rawValue,
                try encode(signal.value),
                "\(signal.confidence)",
                try encode(signal.provenance),
                signal.provenance.provider,
                signal.provenance.model,
                signal.provenance.version,
                signal.provenance.settingsHash,
                now,
                now
            ]
        )
    }

    private func decodeEvaluationSignal(_ row: [String: String]) throws -> EvaluationSignal {
        guard let assetID = row["asset_id"],
              let kindRawValue = row["kind"],
              let kind = EvaluationKind(rawValue: kindRawValue),
              let valueJSON = row["value_json"],
              let confidenceValue = row["confidence"],
              let confidence = Double(confidenceValue),
              let provenanceJSON = row["provenance_json"] else {
            throw CatalogError.sqlite("evaluation signal row is missing required columns")
        }

        return EvaluationSignal(
            assetID: AssetID(rawValue: assetID),
            kind: kind,
            value: try decode(EvaluationValue.self, from: valueJSON),
            confidence: confidence,
            provenance: try decode(ProviderProvenance.self, from: provenanceJSON)
        )
    }

    private func compile(_ query: SetQuery) throws -> (whereSQL: String, bindings: [String]) {
        var clauses: [String] = []
        var bindings: [String] = []

        for predicate in query.predicates {
            switch predicate {
            case .text(let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                clauses.append("LOWER(original_path) LIKE LOWER(?) ESCAPE '\\'")
                bindings.append(Self.likePattern(containing: trimmed))
            case .ratingAtLeast(let rating):
                clauses.append("CAST(json_extract(metadata_json, '$.rating') AS INTEGER) >= ?")
                bindings.append("\(rating)")
            case .flag(let flag):
                clauses.append("json_extract(metadata_json, '$.flag') = ?")
                bindings.append(flag.rawValue)
            case .colorLabel(let colorLabel):
                clauses.append("json_extract(metadata_json, '$.colorLabel') = ?")
                bindings.append(colorLabel.rawValue)
            case .keyword(let keyword):
                let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                clauses.append(
                    "EXISTS (SELECT 1 FROM json_each(metadata_json, '$.keywords') WHERE LOWER(value) = LOWER(?))"
                )
                bindings.append(trimmed)
            case .availability(let availability):
                clauses.append("availability = ?")
                bindings.append(availability.rawValue)
            case .folderPrefix(let prefix):
                let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                clauses.append("original_path LIKE ? ESCAPE '\\'")
                bindings.append(Self.likePattern(prefix: trimmed))
            case .importBatch:
                throw TeststripError.invalidState("import batch queries are not catalog-backed yet")
            }
        }

        guard !clauses.isEmpty else {
            return ("", [])
        }
        return (" WHERE " + clauses.joined(separator: " AND "), bindings)
    }

    private static func likePattern(containing text: String) -> String {
        "%\(escapeLike(text))%"
    }

    private static func likePattern(prefix text: String) -> String {
        "\(escapeLike(text))%"
    }

    private static func escapeLike(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private static func chunks<T>(_ values: [T], size: Int) -> [[T]] {
        stride(from: 0, to: values.count, by: size).map { start in
            Array(values[start..<Swift.min(start + size, values.count)])
        }
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

    private func metadataSyncItems(status: String) throws -> [MetadataSyncItem] {
        let rows = try database.rows(
            """
            SELECT asset_id, sidecar_path, catalog_generation, last_synced_fingerprint
            FROM metadata_sync_state
            WHERE status = ?
            ORDER BY updated_at ASC
            """,
            bindings: [status]
        )
        return try rows.map(decodeMetadataSyncItem)
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

    private func decodePreviewGenerationItem(_ row: [String: String]) throws -> PreviewGenerationItem {
        guard let assetID = row["asset_id"],
              let levelRawValue = row["level"],
              let level = PreviewLevel(rawValue: levelRawValue) else {
            throw CatalogError.sqlite("preview generation row is missing required columns")
        }
        return PreviewGenerationItem(assetID: AssetID(rawValue: assetID), level: level)
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(data: try encoder.encode(value), encoding: .utf8)!
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String) throws -> T {
        try decoder.decode(type, from: Data(string.utf8))
    }

    private func decodeTechnicalMetadata(_ string: String?) throws -> AssetTechnicalMetadata? {
        guard let string, !string.isEmpty else { return nil }
        return try decode(AssetTechnicalMetadata.self, from: string)
    }
}
