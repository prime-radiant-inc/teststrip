import Foundation

public struct SourceRootReconnectResult: Equatable, Sendable {
    public var scannedAssetCount: Int
    public var reconnectedAssetCount: Int
    public var missingFileCount: Int
    public var fingerprintMismatchCount: Int

    public init(
        scannedAssetCount: Int = 0,
        reconnectedAssetCount: Int = 0,
        missingFileCount: Int = 0,
        fingerprintMismatchCount: Int = 0
    ) {
        self.scannedAssetCount = scannedAssetCount
        self.reconnectedAssetCount = reconnectedAssetCount
        self.missingFileCount = missingFileCount
        self.fingerprintMismatchCount = fingerprintMismatchCount
    }
}

public final class CatalogRepository {
    private let database: CatalogDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // Single source of truth for the coordinate expressions. The SQLite planner
    // only uses `idx_assets_gps` when the predicate expression is byte-identical
    // to the indexed expression, so the geo predicate, the cluster aggregation,
    // and the migration's index must all reference these exact strings.
    static let latitudeExpressionSQL = "CAST(json_extract(technical_metadata_json, '$.latitude') AS REAL)"
    static let longitudeExpressionSQL = "CAST(json_extract(technical_metadata_json, '$.longitude') AS REAL)"

    public init(database: CatalogDatabase) {
        self.database = database
        encoder.dateEncodingStrategy = .secondsSince1970
        // Upsert detects metadata edits by comparing stored metadata_json text,
        // so encoding must be byte-stable across decode round trips; JSONEncoder
        // key order otherwise varies per process and re-upserting an unchanged
        // asset (reconnect, availability refresh) spuriously bumps the catalog
        // generation and creates false XMP conflicts.
        encoder.outputFormatting = [.sortedKeys]
        decoder.dateDecodingStrategy = .secondsSince1970
    }

    public func upsert(_ asset: Asset) throws {
        let now = "\(Date().timeIntervalSince1970)"
        let metadataJSON = try encode(asset.metadata)
        try database.execute(
            """
            INSERT INTO assets (id, original_path, volume_identifier, fingerprint_json, availability, metadata_json, technical_metadata_json, content_hash, catalog_generation, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                original_path = excluded.original_path,
                volume_identifier = excluded.volume_identifier,
                fingerprint_json = excluded.fingerprint_json,
                availability = excluded.availability,
                metadata_json = excluded.metadata_json,
                technical_metadata_json = excluded.technical_metadata_json,
                content_hash = excluded.content_hash,
                catalog_generation = CASE
                    WHEN assets.metadata_json = excluded.metadata_json OR ? = '1' THEN assets.catalog_generation
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
                metadataJSON,
                try asset.technicalMetadata.map(encode) ?? "",
                asset.fingerprint.contentHash ?? "",
                now,
                now,
                try storedMetadataMatchesSemantically(asset.metadata, encodedMetadata: metadataJSON, assetID: asset.id) ? "1" : "0"
            ]
        )
    }

    // Catalogs written before the sorted-keys encoder hold metadata_json in
    // per-process-random key order, so the byte compare above would treat the
    // first canonical re-encode of an unchanged asset as a metadata edit and
    // spuriously bump the catalog generation (triggering machine-initiated XMP
    // writes and false conflicts). When the stored text differs, compare the
    // decoded values instead; the byte-equal SQL path stays the common case.
    private func storedMetadataMatchesSemantically(
        _ metadata: AssetMetadata,
        encodedMetadata: String,
        assetID: AssetID
    ) throws -> Bool {
        let rows = try database.rows(
            "SELECT metadata_json FROM assets WHERE id = ?",
            bindings: [assetID.rawValue]
        )
        guard let storedJSON = rows.first?["metadata_json"], storedJSON != encodedMetadata else {
            // No stored row (plain insert) or byte-equal text; the SQL byte
            // compare already keeps the generation for the byte-equal case.
            return false
        }
        guard let storedMetadata = try? decoder.decode(AssetMetadata.self, from: Data(storedJSON.utf8)) else {
            return false
        }
        return storedMetadata == metadata
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

    /// The first cataloged asset whose content matches `contentHash`, regardless
    /// of where it lives — the basis for recognizing a photo already in the
    /// library when it arrives again under a different name or folder. An empty
    /// hash means "no identity recorded" and never matches.
    public func asset(contentHash: String) throws -> Asset? {
        guard !contentHash.isEmpty else { return nil }
        let rows = try database.rows(
            "SELECT * FROM assets WHERE content_hash = ? LIMIT 1",
            bindings: [contentHash]
        )
        return try rows.first.map(decodeAsset)
    }

    /// The subset of `hashes` that already exist in the catalog, for counting
    /// how many source files an import would recognize as already present
    /// without decoding each candidate asset.
    public func containedContentHashes(_ hashes: Set<String>) throws -> Set<String> {
        let queryHashes = hashes.filter { !$0.isEmpty }
        guard !queryHashes.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: queryHashes.count).joined(separator: ", ")
        let rows = try database.rows(
            "SELECT DISTINCT content_hash FROM assets WHERE content_hash IN (\(placeholders))",
            bindings: Array(queryHashes)
        )
        return Set(rows.compactMap { $0["content_hash"] }.filter { !$0.isEmpty })
    }

    public func allAssets(limit: Int, offset: Int = 0, sort: LibrarySortOption = .importOrder) throws -> [Asset] {
        let rows = try database.rows(
            "SELECT * FROM assets ORDER BY \(Self.orderSQL(for: sort)) LIMIT ? OFFSET ?",
            bindings: ["\(limit)", "\(offset)"]
        )
        return try rows.map(decodeAsset)
    }

    public func allAssets(
        matching query: SetQuery,
        limit: Int,
        offset: Int = 0,
        sort: LibrarySortOption = .importOrder
    ) throws -> [Asset] {
        let compiledQuery = try compile(query)
        let rows = try database.rows(
            "SELECT * FROM assets\(compiledQuery.whereSQL) ORDER BY \(Self.orderSQL(for: sort)) LIMIT ? OFFSET ?",
            bindings: compiledQuery.bindings + ["\(limit)", "\(offset)"]
        )
        return try rows.map(decodeAsset)
    }

    public func assetIDs() throws -> [AssetID] {
        let rows = try database.rows("SELECT id FROM assets ORDER BY rowid ASC")
        return try rows.map(decodeAssetID)
    }

    public func assetIDs(matching query: SetQuery) throws -> [AssetID] {
        let compiledQuery = try compile(query)
        let rows = try database.rows(
            "SELECT id FROM assets\(compiledQuery.whereSQL) ORDER BY rowid ASC",
            bindings: compiledQuery.bindings
        )
        return try rows.map(decodeAssetID)
    }

    public func assetIDs(ids: [AssetID], matching query: SetQuery) throws -> [AssetID] {
        guard !ids.isEmpty else { return [] }
        let compiledQuery = try compile(query)
        var matchingAssetIDs: [AssetID] = []
        for chunk in Self.chunks(ids, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let idClause = "assets.id IN (\(placeholders))"
            let whereSQL = compiledQuery.whereSQL.isEmpty
                ? " WHERE \(idClause)"
                : "\(compiledQuery.whereSQL) AND \(idClause)"
            let rows = try database.rows(
                "SELECT assets.id FROM assets\(whereSQL) ORDER BY rowid ASC",
                bindings: compiledQuery.bindings + chunk.map(\.rawValue)
            )
            matchingAssetIDs.append(contentsOf: try rows.map(decodeAssetID))
        }
        return matchingAssetIDs
    }

    private static func orderSQL(for sort: LibrarySortOption) -> String {
        let validCapturedAtSQL = """
        CASE
            WHEN json_valid(technical_metadata_json)
                AND json_type(technical_metadata_json, '$.capturedAt') IN ('integer', 'real')
            THEN 0
            ELSE 1
        END
        """
        let capturedAtSQL = """
        CASE
            WHEN json_valid(technical_metadata_json)
                AND json_type(technical_metadata_json, '$.capturedAt') IN ('integer', 'real')
            THEN CAST(json_extract(technical_metadata_json, '$.capturedAt') AS REAL)
            ELSE NULL
        END
        """

        switch sort {
        case .importOrder:
            return "rowid ASC"
        case .captureTimeNewestFirst:
            return "\(validCapturedAtSQL) ASC, \(capturedAtSQL) DESC, LOWER(original_path) ASC, rowid ASC"
        case .captureTimeOldestFirst:
            return "\(validCapturedAtSQL) ASC, \(capturedAtSQL) ASC, LOWER(original_path) ASC, rowid ASC"
        case .filename:
            return "LOWER(original_path) ASC, rowid ASC"
        }
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

    private func decodeAssetID(_ row: [String: String]) throws -> AssetID {
        guard let id = row["id"] else {
            throw CatalogError.sqlite("asset ID row is missing id")
        }
        return AssetID(rawValue: id)
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

    public func assetCount(ids: [AssetID], flag: PickFlag) throws -> Int {
        var count = 0
        for chunk in Self.chunks(ids, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                "SELECT COUNT(*) AS count FROM assets WHERE id IN (\(placeholders)) AND json_extract(metadata_json, '$.flag') = ?",
                bindings: chunk.map(\.rawValue) + [flag.rawValue]
            )
            guard let countString = rows.first?["count"], let chunkCount = Int(countString) else {
                throw CatalogError.sqlite("asset ID flag count query returned no count")
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

    public func folders() throws -> [CatalogFolder] {
        let rows = try database.rows(
            """
            SELECT
                rtrim(original_path, replace(original_path, '/', '')) AS folder_path,
                COUNT(*) AS asset_count
            FROM assets
            GROUP BY folder_path
            """
        )
        let folders = try rows.map { row in
            guard let path = row["folder_path"],
                  let countString = row["asset_count"],
                  let assetCount = Int(countString) else {
                throw CatalogError.sqlite("folder row is missing required columns")
            }
            return CatalogFolder(path: path, name: Self.folderName(forFolderPath: path), assetCount: assetCount)
        }
        return folders.sorted { lhs, rhs in
            lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
        }
    }

    public func timelineDays() throws -> [CatalogTimelineDay] {
        let rows = try database.rows(
            """
            WITH valid_assets AS (
                SELECT technical_metadata_json
                FROM assets
                WHERE json_valid(technical_metadata_json)
            ),
            captured_assets AS (
                SELECT CAST(json_extract(technical_metadata_json, '$.capturedAt') AS REAL) AS captured_at
                FROM valid_assets
                WHERE json_type(technical_metadata_json, '$.capturedAt') IN ('integer', 'real')
            )
            SELECT
                CAST(strftime('%Y', captured_at, 'unixepoch') AS INTEGER) AS year,
                CAST(strftime('%m', captured_at, 'unixepoch') AS INTEGER) AS month,
                CAST(strftime('%d', captured_at, 'unixepoch') AS INTEGER) AS day,
                COUNT(*) AS asset_count
            FROM captured_assets
            GROUP BY year, month, day
            ORDER BY year DESC, month DESC, day DESC
            """
        )
        return try rows.map { row in
            guard let yearValue = row["year"],
                  let year = Int(yearValue),
                  let monthValue = row["month"],
                  let month = Int(monthValue),
                  let dayValue = row["day"],
                  let day = Int(dayValue),
                  let assetCountValue = row["asset_count"],
                  let assetCount = Int(assetCountValue) else {
                throw CatalogError.sqlite("timeline day row is missing required columns")
            }
            return CatalogTimelineDay(year: year, month: month, day: day, assetCount: assetCount)
        }
    }

    public func placeClusters(bounds: GeoBounds?, cellSize: Double) throws -> [CatalogPlaceCluster] {
        precondition(cellSize > 0, "cellSize must be positive")
        var boundsClause = ""
        var bindings: [String] = []
        if let bounds {
            boundsClause = """
                AND \(Self.latitudeExpressionSQL) BETWEEN ? AND ?
                AND \(Self.longitudeExpressionSQL) BETWEEN ? AND ?
            """
            bindings = [
                "\(bounds.minLatitude)", "\(bounds.maxLatitude)",
                "\(bounds.minLongitude)", "\(bounds.maxLongitude)"
            ]
        }
        let cell = "\(cellSize)"
        let rows = try database.rows(
            """
            WITH located AS (
                SELECT \(Self.latitudeExpressionSQL) AS lat,
                       \(Self.longitudeExpressionSQL) AS lon
                FROM assets
                WHERE json_valid(technical_metadata_json)
                  AND json_type(technical_metadata_json, '$.latitude') IN ('integer', 'real')
                  AND json_type(technical_metadata_json, '$.longitude') IN ('integer', 'real')
                  \(boundsClause)
            )
            SELECT
                CAST(FLOOR(lat / \(cell)) AS INTEGER) AS lat_cell,
                CAST(FLOOR(lon / \(cell)) AS INTEGER) AS lon_cell,
                AVG(lat) AS lat_mean,
                AVG(lon) AS lon_mean,
                COUNT(*) AS asset_count
            FROM located
            GROUP BY lat_cell, lon_cell
            """,
            bindings: bindings
        )
        return try rows.map { row in
            guard let latMean = row["lat_mean"].flatMap(Double.init),
                  let lonMean = row["lon_mean"].flatMap(Double.init),
                  let count = row["asset_count"].flatMap(Int.init) else {
                throw CatalogError.sqlite("place cluster row is missing required columns")
            }
            return CatalogPlaceCluster(latitude: latMean, longitude: lonMean, assetCount: count)
        }
    }

    public func geotaggedCoverage() throws -> CatalogGeotaggedCoverage {
        let rows = try database.rows(
            """
            SELECT
                COUNT(*) AS total,
                SUM(CASE
                    WHEN json_valid(technical_metadata_json)
                     AND json_type(technical_metadata_json, '$.latitude') IN ('integer', 'real')
                    THEN 1 ELSE 0 END) AS geotagged
            FROM assets
            """
        )
        guard let row = rows.first,
              let total = row["total"].flatMap(Int.init) else {
            throw CatalogError.sqlite("coverage row is missing required columns")
        }
        let geotagged = row["geotagged"].flatMap(Int.init) ?? 0
        return CatalogGeotaggedCoverage(geotaggedCount: geotagged, totalCount: total)
    }

    public func enqueueMissingGeocodeCoordinates(limit: Int) throws -> Int {
        guard limit > 0 else { return 0 }
        let now = "\(Date().timeIntervalSince1970)"
        let rows = try database.rows(
            """
            WITH located AS (
                SELECT \(Self.latitudeExpressionSQL) AS lat,
                       \(Self.longitudeExpressionSQL) AS lon
                FROM assets
                WHERE json_valid(technical_metadata_json)
                  AND json_type(technical_metadata_json, '$.latitude') IN ('integer', 'real')
                  AND json_type(technical_metadata_json, '$.longitude') IN ('integer', 'real')
            ),
            keyed AS (
                SELECT printf('%.2f,%.2f', ROUND(lat, 2), ROUND(lon, 2)) AS coordinate_key,
                       AVG(lat) AS lat, AVG(lon) AS lon
                FROM located
                GROUP BY coordinate_key
            )
            SELECT coordinate_key, lat, lon
            FROM keyed
            WHERE coordinate_key NOT IN (SELECT coordinate_key FROM place_cache)
              AND coordinate_key NOT IN (SELECT coordinate_key FROM geocode_queue)
            LIMIT ?
            """,
            bindings: ["\(limit)"]
        )
        try database.transaction {
            for row in rows {
                guard let key = row["coordinate_key"],
                      let lat = row["lat"], let lon = row["lon"] else { continue }
                try database.execute(
                    """
                    INSERT OR IGNORE INTO geocode_queue (coordinate_key, latitude, longitude, updated_at)
                    VALUES (?, ?, ?, ?)
                    """,
                    bindings: [key, lat, lon, now]
                )
            }
        }
        return rows.count
    }

    public func pendingGeocodeItems(limit: Int, maximumAttemptCount: Int) throws -> [GeocodeQueueItem] {
        guard limit > 0, maximumAttemptCount > 0 else { return [] }
        let rows = try database.rows(
            """
            SELECT coordinate_key, latitude, longitude
            FROM geocode_queue
            WHERE attempt_count < ?
            ORDER BY updated_at ASC
            LIMIT ?
            """,
            bindings: ["\(maximumAttemptCount)", "\(limit)"]
        )
        return try rows.map { row in
            guard let key = row["coordinate_key"],
                  let latitude = row["latitude"].flatMap(Double.init),
                  let longitude = row["longitude"].flatMap(Double.init) else {
                throw CatalogError.sqlite("geocode queue row is missing required columns")
            }
            return GeocodeQueueItem(coordinateKey: key, latitude: latitude, longitude: longitude)
        }
    }

    public func recordGeocodeFailure(coordinateKey: String, errorMessage: String) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            UPDATE geocode_queue
            SET attempt_count = attempt_count + 1,
                last_error = ?,
                last_attempted_at = ?,
                updated_at = ?
            WHERE coordinate_key = ?
            """,
            bindings: [errorMessage, now, now, coordinateKey]
        )
    }

    public func recordPlaceName(_ placeName: CatalogPlaceName) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            try database.execute(
                """
                INSERT INTO place_cache (coordinate_key, locality, administrative_area, country, display_name, updated_at)
                VALUES (?, NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), NULLIF(?, ''), ?)
                ON CONFLICT(coordinate_key) DO UPDATE SET
                    locality = excluded.locality,
                    administrative_area = excluded.administrative_area,
                    country = excluded.country,
                    display_name = excluded.display_name,
                    updated_at = excluded.updated_at
                """,
                bindings: [
                    placeName.coordinateKey,
                    placeName.locality ?? "",
                    placeName.administrativeArea ?? "",
                    placeName.country ?? "",
                    placeName.displayName ?? "",
                    now
                ]
            )
            try database.execute(
                "DELETE FROM geocode_queue WHERE coordinate_key = ?",
                bindings: [placeName.coordinateKey]
            )
        }
    }

    public func placeName(coordinateKey: String) throws -> CatalogPlaceName? {
        let rows = try database.rows(
            """
            SELECT coordinate_key, locality, administrative_area, country, display_name
            FROM place_cache
            WHERE coordinate_key = ?
            LIMIT 1
            """,
            bindings: [coordinateKey]
        )
        guard let row = rows.first, let key = row["coordinate_key"] else { return nil }
        return CatalogPlaceName(
            coordinateKey: key,
            locality: row["locality"],
            administrativeArea: row["administrative_area"],
            country: row["country"],
            displayName: row["display_name"]
        )
    }

    public func geocodeQueueDepth() throws -> Int {
        let rows = try database.rows("SELECT COUNT(*) AS count FROM geocode_queue")
        guard let count = rows.first?["count"].flatMap(Int.init) else {
            throw CatalogError.sqlite("geocode queue depth query returned no count")
        }
        return count
    }

    public func assetsMissingCoordinates(limit: Int) throws -> [AssetID] {
        guard limit > 0 else { return [] }
        let rows = try database.rows(
            """
            SELECT id
            FROM assets
            WHERE availability = ?
              AND NOT (
                json_valid(technical_metadata_json)
                AND COALESCE(json_type(technical_metadata_json, '$.latitude'), 'null') IN ('integer', 'real')
              )
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            bindings: [SourceAvailability.online.rawValue, "\(limit)"]
        )
        return try rows.map { row in
            guard let id = row["id"] else {
                throw CatalogError.sqlite("missing-coordinates row is missing id")
            }
            return AssetID(rawValue: id)
        }
    }

    public func topLocations(limit: Int) throws -> [CatalogTopLocation] {
        guard limit > 0 else { return [] }
        let rows = try database.rows(
            """
            WITH located AS (
                SELECT \(Self.latitudeExpressionSQL) AS lat,
                       \(Self.longitudeExpressionSQL) AS lon
                FROM assets
                WHERE json_valid(technical_metadata_json)
                  AND json_type(technical_metadata_json, '$.latitude') IN ('integer', 'real')
                  AND json_type(technical_metadata_json, '$.longitude') IN ('integer', 'real')
            ),
            keyed AS (
                SELECT printf('%.2f,%.2f', ROUND(lat, 2), ROUND(lon, 2)) AS coordinate_key,
                       lat, lon
                FROM located
            )
            SELECT place_cache.display_name AS display_name,
                   COUNT(*) AS asset_count,
                   AVG(keyed.lat) AS lat_mean,
                   AVG(keyed.lon) AS lon_mean
            FROM keyed
            JOIN place_cache ON place_cache.coordinate_key = keyed.coordinate_key
            WHERE place_cache.display_name IS NOT NULL
            GROUP BY place_cache.display_name
            ORDER BY asset_count DESC, display_name ASC
            LIMIT ?
            """,
            bindings: ["\(limit)"]
        )
        return try rows.map { row in
            guard let displayName = row["display_name"],
                  let assetCount = row["asset_count"].flatMap(Int.init),
                  let latMean = row["lat_mean"].flatMap(Double.init),
                  let lonMean = row["lon_mean"].flatMap(Double.init) else {
                throw CatalogError.sqlite("top location row is missing required columns")
            }
            return CatalogTopLocation(
                displayName: displayName,
                assetCount: assetCount,
                latitude: latMean,
                longitude: lonMean
            )
        }
    }

    public func recordSourceRoot(_ root: URL, securityScopedBookmarkData: Data? = nil) throws {
        let path = Self.normalizedDirectoryPath(root)
        let now = "\(Date().timeIntervalSince1970)"
        let bookmarkBase64 = securityScopedBookmarkData?.base64EncodedString() ?? ""
        try database.execute(
            """
            INSERT INTO source_roots (path, name, security_scoped_bookmark_base64, created_at, updated_at)
            VALUES (?, ?, NULLIF(?, ''), ?, ?)
            ON CONFLICT(path) DO UPDATE SET
                name = excluded.name,
                security_scoped_bookmark_base64 = COALESCE(
                    excluded.security_scoped_bookmark_base64,
                    source_roots.security_scoped_bookmark_base64
                ),
                updated_at = excluded.updated_at
            """,
            bindings: [
                path,
                Self.folderName(forFolderPath: path),
                bookmarkBase64,
                now,
                now
            ]
        )
    }

    public func sourceRoots() throws -> [CatalogSourceRoot] {
        let rows = try database.rows(
            """
            SELECT path, name, security_scoped_bookmark_base64
            FROM source_roots
            ORDER BY updated_at DESC, path COLLATE NOCASE ASC
            """
        )
        return try rows.map { row in
            guard let path = row["path"], let name = row["name"] else {
                throw CatalogError.sqlite("source root row is missing required columns")
            }
            let counts = try assetCounts(underSourceRootPath: path)
            let bookmarkData = row["security_scoped_bookmark_base64"].flatMap { Data(base64Encoded: $0) }
            return CatalogSourceRoot(
                path: path,
                name: name,
                assetCount: counts.assetCount,
                unavailableAssetCount: counts.unavailableAssetCount,
                securityScopedBookmarkData: bookmarkData
            )
        }
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

    public func deleteAssetSet(id: AssetSetID) throws {
        try database.execute("DELETE FROM asset_sets WHERE id = ?", bindings: [id.rawValue])
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

    public func upsertPerson(id: String, name: String) throws {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            throw TeststripError.invalidState("person id is required")
        }
        guard !trimmedName.isEmpty else {
            throw TeststripError.invalidState("person name is required")
        }
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO people (id, name, created_at, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                updated_at = excluded.updated_at
            """,
            bindings: [trimmedID, trimmedName, now, now]
        )
    }

    public func assignAssets(_ assetIDs: [AssetID], toPersonID personID: String) throws {
        let trimmedPersonID = personID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPersonID.isEmpty else {
            throw TeststripError.invalidState("person id is required")
        }
        guard !assetIDs.isEmpty else { return }
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            try requirePerson(id: trimmedPersonID)
            for assetID in assetIDs {
                try database.execute(
                    """
                    INSERT OR IGNORE INTO person_assets (person_id, asset_id, created_at)
                    VALUES (?, ?, ?)
                    """,
                    bindings: [trimmedPersonID, assetID.rawValue, now]
                )
                try database.execute(
                    "DELETE FROM dismissed_face_assets WHERE asset_id = ?",
                    bindings: [assetID.rawValue]
                )
            }
        }
    }

    /// Fails writes that would link faces or assets to a person that no longer
    /// exists, e.g. a stale suggestion confirmed after the person was merged away.
    private func requirePerson(id: String) throws {
        let rows = try database.rows("SELECT 1 FROM people WHERE id = ?", bindings: [id])
        guard !rows.isEmpty else {
            throw CatalogError.notFound(id)
        }
    }

    public func mergePerson(sourceID: String, into targetID: String) throws {
        let trimmedSourceID = sourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTargetID = targetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSourceID.isEmpty, !trimmedTargetID.isEmpty else {
            throw TeststripError.invalidState("person id is required")
        }
        guard trimmedSourceID != trimmedTargetID else { return }
        try database.transaction {
            try database.execute(
                """
                INSERT OR IGNORE INTO person_assets (person_id, asset_id, created_at)
                SELECT ?, asset_id, created_at
                FROM person_assets
                WHERE person_id = ?
                """,
                bindings: [trimmedTargetID, trimmedSourceID]
            )
            try database.execute(
                "UPDATE person_faces SET person_id = ? WHERE person_id = ?",
                bindings: [trimmedTargetID, trimmedSourceID]
            )
            try database.execute("DELETE FROM person_assets WHERE person_id = ?", bindings: [trimmedSourceID])
            try database.execute("DELETE FROM people WHERE id = ?", bindings: [trimmedSourceID])
        }
    }

    public func dismissFaceAssets(_ assetIDs: [AssetID]) throws {
        guard !assetIDs.isEmpty else { return }
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            for assetID in assetIDs {
                try database.execute(
                    "INSERT OR IGNORE INTO dismissed_face_assets (asset_id, created_at) VALUES (?, ?)",
                    bindings: [assetID.rawValue, now]
                )
                try database.execute("DELETE FROM person_assets WHERE asset_id = ?", bindings: [assetID.rawValue])
                try database.execute("DELETE FROM person_faces WHERE asset_id = ?", bindings: [assetID.rawValue])
            }
        }
    }

    public func people() throws -> [CatalogPerson] {
        let rows = try database.rows(
            """
            SELECT people.id, people.name, COUNT(person_assets.asset_id) AS asset_count
            FROM people
            LEFT JOIN person_assets ON person_assets.person_id = people.id
            GROUP BY people.id, people.name
            ORDER BY people.name COLLATE NOCASE ASC
            """
        )
        return try rows.map { row in
            guard let id = row["id"], let name = row["name"], let countString = row["asset_count"], let assetCount = Int(countString) else {
                throw CatalogError.sqlite("person row is missing required columns")
            }
            return CatalogPerson(id: id, name: name, assetCount: assetCount)
        }
    }

    public func assetIDs(personID: String) throws -> [AssetID] {
        let rows = try database.rows(
            "SELECT asset_id FROM person_assets WHERE person_id = ? ORDER BY rowid ASC",
            bindings: [personID]
        )
        return try rows.map { row in
            guard let id = row["asset_id"] else {
                throw CatalogError.sqlite("person asset row is missing asset_id")
            }
            return AssetID(rawValue: id)
        }
    }

    public func dismissedFaceAssetIDs() throws -> [AssetID] {
        let rows = try database.rows("SELECT asset_id FROM dismissed_face_assets ORDER BY rowid ASC")
        return try rows.map { row in
            guard let id = row["asset_id"] else {
                throw CatalogError.sqlite("dismissed face row is missing asset_id")
            }
            return AssetID(rawValue: id)
        }
    }

    public func replaceFaceObservations(
        assetID: AssetID,
        provenance: ProviderProvenance,
        with observations: [CatalogFaceObservation]
    ) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            // person_faces/dismissed_faces reference faces by (asset_id, face_index) only,
            // so a re-scan that changes the detected face set leaves them pointing at the
            // wrong faces. Compare old and new detections and clear the asset's face links
            // when they differ; the user re-confirms after the re-scan.
            let previousRows = try database.rows(
                """
                SELECT face_index, face_json
                FROM face_observations
                WHERE asset_id = ? AND provider = ? AND model = ? AND version = ? AND settings_hash = ?
                """,
                bindings: [
                    assetID.rawValue,
                    provenance.provider,
                    provenance.model,
                    provenance.version,
                    provenance.settingsHash
                ]
            )
            var previousBoxes: [Int: FaceBoundingBox] = [:]
            for row in previousRows {
                guard let indexValue = row["face_index"],
                      let index = Int(indexValue),
                      let faceJSON = row["face_json"] else {
                    throw CatalogError.sqlite("face observation row is missing required columns")
                }
                previousBoxes[index] = try decode(FaceObservationPayload.self, from: faceJSON).boundingBox
            }
            let newBoxes = Dictionary(uniqueKeysWithValues: observations.map { ($0.faceIndex, $0.boundingBox) })
            if previousBoxes != newBoxes {
                try database.execute("DELETE FROM person_faces WHERE asset_id = ?", bindings: [assetID.rawValue])
                try database.execute("DELETE FROM dismissed_faces WHERE asset_id = ?", bindings: [assetID.rawValue])
            }
            try database.execute(
                """
                DELETE FROM face_observations
                WHERE asset_id = ? AND provider = ? AND model = ? AND version = ? AND settings_hash = ?
                """,
                bindings: [
                    assetID.rawValue,
                    provenance.provider,
                    provenance.model,
                    provenance.version,
                    provenance.settingsHash
                ]
            )
            for observation in observations {
                try database.execute(
                    """
                    INSERT INTO face_observations (
                        asset_id, face_index, face_json, provenance_json,
                        provider, model, version, settings_hash, created_at, updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    bindings: [
                        observation.assetID.rawValue,
                        "\(observation.faceIndex)",
                        try encode(FaceObservationPayload(
                            boundingBox: observation.boundingBox,
                            captureQuality: observation.captureQuality,
                            embedding: observation.embedding
                        )),
                        try encode(observation.provenance),
                        observation.provenance.provider,
                        observation.provenance.model,
                        observation.provenance.version,
                        observation.provenance.settingsHash,
                        now,
                        now
                    ]
                )
            }
        }
    }

    public func faceObservations(assetID: AssetID) throws -> [CatalogFaceObservation] {
        let rows = try database.rows(
            """
            SELECT asset_id, face_index, face_json, provenance_json
            FROM face_observations
            WHERE asset_id = ?
            ORDER BY provider ASC, model ASC, version ASC, settings_hash ASC, face_index ASC
            """,
            bindings: [assetID.rawValue]
        )
        return try rows.map(decodeFaceObservation)
    }

    private func decodeFaceObservation(_ row: [String: String]) throws -> CatalogFaceObservation {
        guard let assetID = row["asset_id"],
              let faceIndexValue = row["face_index"],
              let faceIndex = Int(faceIndexValue),
              let faceJSON = row["face_json"],
              let provenanceJSON = row["provenance_json"] else {
            throw CatalogError.sqlite("face observation row is missing required columns")
        }
        let payload = try decode(FaceObservationPayload.self, from: faceJSON)
        return CatalogFaceObservation(
            assetID: AssetID(rawValue: assetID),
            faceIndex: faceIndex,
            boundingBox: payload.boundingBox,
            captureQuality: payload.captureQuality,
            embedding: payload.embedding,
            provenance: try decode(ProviderProvenance.self, from: provenanceJSON)
        )
    }

    public func unassignedFaceObservations(provenance: ProviderProvenance, limit: Int) throws -> [CatalogFaceObservation] {
        let rows = try database.rows(
            """
            SELECT asset_id, face_index, face_json, provenance_json
            FROM face_observations
            WHERE provider = ? AND model = ? AND version = ? AND settings_hash = ?
              AND NOT EXISTS (
                  SELECT 1 FROM person_faces
                  WHERE person_faces.asset_id = face_observations.asset_id
                    AND person_faces.face_index = face_observations.face_index
              )
              AND NOT EXISTS (
                  SELECT 1 FROM dismissed_faces
                  WHERE dismissed_faces.asset_id = face_observations.asset_id
                    AND dismissed_faces.face_index = face_observations.face_index
              )
              AND NOT EXISTS (
                  SELECT 1 FROM dismissed_face_assets
                  WHERE dismissed_face_assets.asset_id = face_observations.asset_id
              )
              AND NOT EXISTS (
                  SELECT 1 FROM person_assets
                  WHERE person_assets.asset_id = face_observations.asset_id
              )
            ORDER BY created_at DESC, asset_id ASC, face_index ASC
            LIMIT ?
            """,
            bindings: [provenance.provider, provenance.model, provenance.version, provenance.settingsHash, "\(limit)"]
        )
        return try rows.map(decodeFaceObservation)
    }

    public func confirmedFaceEmbeddingsByPerson(provenance: ProviderProvenance) throws -> [String: [[Double]]] {
        let rows = try database.rows(
            """
            SELECT person_faces.person_id AS person_id, face_observations.face_json AS face_json
            FROM person_faces
            JOIN face_observations
              ON face_observations.asset_id = person_faces.asset_id
             AND face_observations.face_index = person_faces.face_index
            WHERE face_observations.provider = ? AND face_observations.model = ?
              AND face_observations.version = ? AND face_observations.settings_hash = ?
            ORDER BY person_faces.person_id ASC, person_faces.asset_id ASC, person_faces.face_index ASC
            """,
            bindings: [provenance.provider, provenance.model, provenance.version, provenance.settingsHash]
        )
        var embeddingsByPerson: [String: [[Double]]] = [:]
        for row in rows {
            guard let personID = row["person_id"], let faceJSON = row["face_json"] else {
                throw CatalogError.sqlite("confirmed face row is missing required columns")
            }
            let payload = try decode(FaceObservationPayload.self, from: faceJSON)
            embeddingsByPerson[personID, default: []].append(payload.embedding)
        }
        return embeddingsByPerson
    }

    public func faceObservationAssetCount(provenance: ProviderProvenance) throws -> Int {
        let rows = try database.rows(
            """
            SELECT COUNT(DISTINCT asset_id) AS asset_count
            FROM face_observations
            WHERE provider = ? AND model = ? AND version = ? AND settings_hash = ?
            """,
            bindings: [provenance.provider, provenance.model, provenance.version, provenance.settingsHash]
        )
        return rows.first.flatMap { $0["asset_count"] }.flatMap(Int.init) ?? 0
    }

    public func assignFaces(_ faceIDs: [FaceID], toPersonID personID: String) throws {
        let trimmedPersonID = personID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPersonID.isEmpty else {
            throw TeststripError.invalidState("person id is required")
        }
        guard !faceIDs.isEmpty else { return }
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            try requirePerson(id: trimmedPersonID)
            for faceID in faceIDs {
                try database.execute(
                    """
                    INSERT INTO person_faces (person_id, asset_id, face_index, created_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(asset_id, face_index) DO UPDATE SET person_id = excluded.person_id
                    """,
                    bindings: [trimmedPersonID, faceID.assetID.rawValue, "\(faceID.faceIndex)", now]
                )
                try database.execute(
                    "DELETE FROM dismissed_faces WHERE asset_id = ? AND face_index = ?",
                    bindings: [faceID.assetID.rawValue, "\(faceID.faceIndex)"]
                )
            }
            for assetID in Set(faceIDs.map(\.assetID)).sorted(by: { $0.rawValue < $1.rawValue }) {
                try database.execute(
                    "INSERT OR IGNORE INTO person_assets (person_id, asset_id, created_at) VALUES (?, ?, ?)",
                    bindings: [trimmedPersonID, assetID.rawValue, now]
                )
                try database.execute(
                    "DELETE FROM dismissed_face_assets WHERE asset_id = ?",
                    bindings: [assetID.rawValue]
                )
            }
        }
    }

    public func dismissFaces(_ faceIDs: [FaceID]) throws {
        guard !faceIDs.isEmpty else { return }
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            for faceID in faceIDs {
                try database.execute(
                    "INSERT OR IGNORE INTO dismissed_faces (asset_id, face_index, created_at) VALUES (?, ?, ?)",
                    bindings: [faceID.assetID.rawValue, "\(faceID.faceIndex)", now]
                )
                try database.execute(
                    "DELETE FROM person_faces WHERE asset_id = ? AND face_index = ?",
                    bindings: [faceID.assetID.rawValue, "\(faceID.faceIndex)"]
                )
            }
        }
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
                issues_json,
                starred,
                created_at,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                issues_json = excluded.issues_json,
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
                try encode(session.issues),
                session.starred ? "1" : "0",
                "\(session.createdAt.timeIntervalSince1970)",
                "\(session.updatedAt.timeIntervalSince1970)"
            ]
        )
    }

    public func saveRelocationManifestEntry(_ entry: RelocationManifestEntry, sessionID: WorkSessionID) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO relocation_manifest_entries (
                session_id, sequence, asset_id,
                original_from_path, original_to_path,
                sidecar_from_path, sidecar_to_path, created_at
            )
            VALUES (
                ?,
                (SELECT COALESCE(MAX(sequence), -1) + 1 FROM relocation_manifest_entries WHERE session_id = ?),
                ?, ?, ?, ?, ?, ?
            )
            ON CONFLICT(session_id, asset_id) DO UPDATE SET
                original_from_path = excluded.original_from_path,
                original_to_path = excluded.original_to_path,
                sidecar_from_path = excluded.sidecar_from_path,
                sidecar_to_path = excluded.sidecar_to_path
            """,
            bindings: [
                sessionID.rawValue,
                sessionID.rawValue,
                entry.assetID.rawValue,
                entry.originalFrom.path,
                entry.originalTo.path,
                entry.sidecarFrom?.path ?? "",
                entry.sidecarTo?.path ?? "",
                now
            ]
        )
    }

    public func relocationManifestEntries(sessionID: WorkSessionID) throws -> [RelocationManifestEntry] {
        let rows = try database.rows(
            "SELECT * FROM relocation_manifest_entries WHERE session_id = ? ORDER BY sequence ASC",
            bindings: [sessionID.rawValue]
        )
        return try rows.map(decodeRelocationManifestEntry)
    }

    public func deleteRelocationManifest(sessionID: WorkSessionID) throws {
        try database.execute(
            "DELETE FROM relocation_manifest_entries WHERE session_id = ?",
            bindings: [sessionID.rawValue]
        )
    }

    private func decodeRelocationManifestEntry(_ row: [String: String]) throws -> RelocationManifestEntry {
        guard let assetID = row["asset_id"],
              let originalFrom = row["original_from_path"],
              let originalTo = row["original_to_path"] else {
            throw CatalogError.sqlite("relocation manifest row is missing required columns")
        }
        return RelocationManifestEntry(
            assetID: AssetID(rawValue: assetID),
            originalFrom: URL(fileURLWithPath: originalFrom),
            originalTo: URL(fileURLWithPath: originalTo),
            sidecarFrom: row["sidecar_from_path"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
            sidecarTo: row["sidecar_to_path"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
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

    public func workSessions(matching text: String, limit: Int) throws -> [WorkSession] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, limit > 0 else { return [] }
        let pattern = Self.likePattern(containing: trimmed)
        let rows = try database.rows(
            """
            SELECT * FROM work_sessions
            WHERE LOWER(id) LIKE LOWER(?) ESCAPE '\\'
               OR LOWER(kind) LIKE LOWER(?) ESCAPE '\\'
               OR LOWER(intent) LIKE LOWER(?) ESCAPE '\\'
               OR LOWER(title) LIKE LOWER(?) ESCAPE '\\'
               OR LOWER(detail) LIKE LOWER(?) ESCAPE '\\'
               OR LOWER(status) LIKE LOWER(?) ESCAPE '\\'
            ORDER BY updated_at DESC
            LIMIT ?
            """,
            bindings: Array(repeating: pattern, count: 6) + ["\(limit)"]
        )
        return try rows.map(decodeWorkSession)
    }

    public func workSessions(kind: WorkSessionKind, statuses: [WorkSessionStatus]) throws -> [WorkSession] {
        guard !statuses.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: statuses.count).joined(separator: ", ")
        let rows = try database.rows(
            """
            SELECT * FROM work_sessions
            WHERE kind = ?
              AND status IN (\(placeholders))
            ORDER BY updated_at DESC
            """,
            bindings: [kind.rawValue] + statuses.map(\.rawValue)
        )
        return try rows.map(decodeWorkSession)
    }

    public func save(_ proposals: [AutopilotProposal]) throws {
        guard !proposals.isEmpty else { return }
        try database.transaction {
            for proposal in proposals {
                try database.execute(
                    """
                    INSERT INTO autopilot_proposals (
                        id,
                        run_id,
                        asset_id,
                        kind,
                        keyword,
                        rationale,
                        confidence,
                        status,
                        created_at,
                        updated_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        run_id = excluded.run_id,
                        asset_id = excluded.asset_id,
                        kind = excluded.kind,
                        keyword = excluded.keyword,
                        rationale = excluded.rationale,
                        confidence = excluded.confidence,
                        status = excluded.status,
                        updated_at = excluded.updated_at
                    """,
                    bindings: [
                        proposal.id.rawValue,
                        proposal.runID.rawValue,
                        proposal.assetID.rawValue,
                        proposal.kind.rawValue,
                        proposal.keyword ?? "",
                        proposal.rationale,
                        "\(proposal.confidence)",
                        proposal.status.rawValue,
                        "\(proposal.createdAt.timeIntervalSince1970)",
                        "\(proposal.updatedAt.timeIntervalSince1970)"
                    ]
                )
            }
        }
    }

    public func autopilotProposals(runID: AutopilotRunID) throws -> [AutopilotProposal] {
        let rows = try database.rows(
            "SELECT * FROM autopilot_proposals WHERE run_id = ? ORDER BY created_at ASC, id ASC",
            bindings: [runID.rawValue]
        )
        return try rows.map(decodeAutopilotProposal)
    }

    public func autopilotProposals(status: AutopilotProposalStatus) throws -> [AutopilotProposal] {
        let rows = try database.rows(
            "SELECT * FROM autopilot_proposals WHERE status = ? ORDER BY created_at ASC, id ASC",
            bindings: [status.rawValue]
        )
        return try rows.map(decodeAutopilotProposal)
    }

    public func updateAutopilotProposalStatus(ids: [AutopilotProposalID], to status: AutopilotProposalStatus) throws {
        guard !ids.isEmpty else { return }
        let now = "\(Date().timeIntervalSince1970)"
        try database.transaction {
            for id in ids {
                try database.execute(
                    "UPDATE autopilot_proposals SET status = ?, updated_at = ? WHERE id = ?",
                    bindings: [status.rawValue, now, id.rawValue]
                )
            }
        }
    }

    public func pendingAutopilotProposalCount() throws -> Int {
        let rows = try database.rows(
            "SELECT COUNT(*) AS proposal_count FROM autopilot_proposals WHERE status = ?",
            bindings: [AutopilotProposalStatus.pending.rawValue]
        )
        return rows.first.flatMap { $0["proposal_count"] }.flatMap(Int.init) ?? 0
    }

    public func deleteAutopilotProposals(runID: AutopilotRunID) throws {
        try database.execute(
            "DELETE FROM autopilot_proposals WHERE run_id = ?",
            bindings: [runID.rawValue]
        )
    }

    private func decodeAutopilotProposal(_ row: [String: String]) throws -> AutopilotProposal {
        guard let id = row["id"],
              let runID = row["run_id"],
              let assetID = row["asset_id"],
              let kindRawValue = row["kind"],
              let kind = AutopilotProposalKind(rawValue: kindRawValue),
              let rationale = row["rationale"],
              let confidenceValue = row["confidence"],
              let confidence = Double(confidenceValue),
              let statusRawValue = row["status"],
              let status = AutopilotProposalStatus(rawValue: statusRawValue),
              let createdAtValue = row["created_at"],
              let createdAtInterval = TimeInterval(createdAtValue),
              let updatedAtValue = row["updated_at"],
              let updatedAtInterval = TimeInterval(updatedAtValue) else {
            throw CatalogError.sqlite("autopilot proposal row is missing required columns")
        }
        let keywordValue = row["keyword"] ?? ""
        return AutopilotProposal(
            id: AutopilotProposalID(rawValue: id),
            runID: AutopilotRunID(rawValue: runID),
            assetID: AssetID(rawValue: assetID),
            kind: kind,
            keyword: keywordValue.isEmpty ? nil : keywordValue,
            rationale: rationale,
            confidence: confidence,
            status: status,
            createdAt: Date(timeIntervalSince1970: createdAtInterval),
            updatedAt: Date(timeIntervalSince1970: updatedAtInterval)
        )
    }

    public func recordEvaluationSignals(_ signals: [EvaluationSignal]) throws {
        guard !signals.isEmpty else { return }
        try database.transaction {
            for signal in signals {
                try recordEvaluationSignal(signal)
                try clearEvaluationFailure(assetID: signal.assetID, provider: signal.provenance.provider)
            }
        }
    }

    public func evaluationSignals(assetID: AssetID) throws -> [EvaluationSignal] {
        let rows = try database.rows(
            """
            SELECT asset_id, kind, value_json, confidence, provenance_json
            FROM evaluation_signals
            WHERE asset_id = ?
              AND \(Self.currentScaleSignalSQL)
            ORDER BY rowid ASC
            """,
            bindings: [assetID.rawValue]
        )
        return try rows.map(decodeEvaluationSignal)
    }

    public func recordEvaluationFailure(assetID: AssetID, provider: String, message: String) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO evaluation_failures (
                asset_id,
                provider,
                message,
                failed_at,
                updated_at
            )
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(asset_id, provider) DO UPDATE SET
                message = excluded.message,
                failed_at = excluded.failed_at,
                updated_at = excluded.updated_at
            """,
            bindings: [
                assetID.rawValue,
                provider,
                message,
                now,
                now
            ]
        )
    }

    public func clearEvaluationFailure(assetID: AssetID, provider: String) throws {
        try database.execute(
            """
            DELETE FROM evaluation_failures
            WHERE asset_id = ?
              AND provider = ?
            """,
            bindings: [
                assetID.rawValue,
                provider
            ]
        )
    }

    public func evaluationFailures(assetID: AssetID) throws -> [CatalogEvaluationFailure] {
        let rows = try database.rows(
            """
            SELECT asset_id, provider, message, failed_at
            FROM evaluation_failures
            WHERE asset_id = ?
            ORDER BY provider ASC
            """,
            bindings: [assetID.rawValue]
        )
        return try rows.map(decodeEvaluationFailure)
    }

    public func evaluationKindSummaries() throws -> [CatalogEvaluationKindSummary] {
        let rows = try database.rows(
            """
            SELECT kind, COUNT(DISTINCT asset_id) AS asset_count
            FROM evaluation_signals
            WHERE NOT (
                kind IN ('faceCount', 'faceQuality')
                AND (
                    EXISTS (
                        SELECT 1
                        FROM dismissed_face_assets
                        WHERE dismissed_face_assets.asset_id = evaluation_signals.asset_id
                    )
                    OR EXISTS (
                        SELECT 1
                        FROM person_assets
                        WHERE person_assets.asset_id = evaluation_signals.asset_id
                    )
                )
            )
            GROUP BY kind
            ORDER BY kind COLLATE NOCASE ASC
            """
        )
        return try rows.map { row in
            guard let kindRawValue = row["kind"],
                  let kind = EvaluationKind(rawValue: kindRawValue),
                  let assetCountValue = row["asset_count"],
                  let assetCount = Int(assetCountValue) else {
                throw CatalogError.sqlite("evaluation kind summary row is missing required columns")
            }
            return CatalogEvaluationKindSummary(kind: kind, assetCount: assetCount)
        }
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

    public func reconnectSourceRoot(from oldRoot: URL, to newRoot: URL) throws -> SourceRootReconnectResult {
        let oldRootPath = Self.normalizedDirectoryPath(oldRoot)
        let newRootPath = Self.normalizedDirectoryPath(newRoot)
        let rows = try database.rows(
            """
            SELECT * FROM assets
            WHERE original_path = ?
               OR original_path LIKE ? ESCAPE '\\'
            ORDER BY rowid ASC
            """,
            bindings: [
                oldRootPath,
                "\(Self.escapedLikePattern(oldRootPath == "/" ? "/" : oldRootPath + "/"))%"
            ]
        )
        var result = SourceRootReconnectResult(scannedAssetCount: rows.count)

        try database.transaction {
            for asset in try rows.map(decodeAsset) {
                guard let relativePath = Self.relativePath(for: asset.originalURL, under: oldRootPath) else {
                    continue
                }
                let candidateURL = URL(fileURLWithPath: newRootPath, isDirectory: true)
                    .appendingPathComponent(relativePath)
                guard let candidateFingerprint = Self.fingerprint(for: candidateURL) else {
                    result.missingFileCount += 1
                    continue
                }
                guard asset.fingerprint.matches(candidateFingerprint) else {
                    result.fingerprintMismatchCount += 1
                    continue
                }

                var reconnectedAsset = asset
                reconnectedAsset.originalURL = candidateURL
                reconnectedAsset.volumeIdentifier = Self.volumeIdentifier(for: candidateURL)
                reconnectedAsset.availability = .online
                try upsert(reconnectedAsset)
                try updateMetadataSyncSidecarPathIfPresent(
                    assetID: asset.id,
                    sidecarURL: XMPSidecarStore().sidecarURL(forOriginalAt: candidateURL)
                )
                result.reconnectedAssetCount += 1
            }
        }

        if result.reconnectedAssetCount > 0 {
            try recordSourceRoot(newRoot)
        }

        return result
    }

    /// Rewrites one asset's path after Teststrip itself has moved the file's
    /// bytes to `newOriginalURL`. Adopts the destination's fingerprint (rather
    /// than requiring a match) because this is a deliberate, catalog-authored
    /// move, and updates the sidecar sync path so a pending XMP write follows
    /// the file. One transaction: the row and its sync state move together.
    public func relocateOriginal(assetID: AssetID, to newOriginalURL: URL) throws {
        let asset = try asset(id: assetID)
        guard let destinationFingerprint = Self.fingerprint(for: newOriginalURL) else {
            throw TeststripError.io("relocation destination is unreadable \(newOriginalURL.path)")
        }
        try database.transaction {
            var relocatedAsset = asset
            relocatedAsset.originalURL = newOriginalURL
            relocatedAsset.volumeIdentifier = Self.volumeIdentifier(for: newOriginalURL)
            relocatedAsset.fingerprint = destinationFingerprint
            relocatedAsset.availability = .online
            try upsert(relocatedAsset)
            try updateMetadataSyncSidecarPathIfPresent(
                assetID: assetID,
                sidecarURL: XMPSidecarStore().sidecarURL(forOriginalAt: newOriginalURL)
            )
        }
    }

    public func catalogGeneration(assetID: AssetID) throws -> Int {
        let rows = try database.rows("SELECT catalog_generation FROM assets WHERE id = ?", bindings: [assetID.rawValue])
        guard let value = rows.first?["catalog_generation"], let intValue = Int(value) else {
            throw CatalogError.notFound(assetID.rawValue)
        }
        return intValue
    }

    public func recordMetadataSyncPending(_ item: MetadataSyncItem) throws {
        // Once a sidecar has been synced, catalog_generation and
        // last_synced_fingerprint record the generation and content it reflects.
        // Recording the intent to sync a newer edit must not advance them, or
        // the worker's planner reads the pending target generation as "already
        // synced," concludes nothing changed, and marks the row synced without
        // ever rewriting the sidecar. Before any sync has landed (empty
        // fingerprint) there is nothing to preserve, so a fresh pending write
        // coalesces forward to the latest generation.
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
                catalog_generation = CASE
                    WHEN metadata_sync_state.last_synced_fingerprint != ''
                    THEN metadata_sync_state.catalog_generation
                    ELSE excluded.catalog_generation
                END,
                last_synced_fingerprint = CASE
                    WHEN metadata_sync_state.last_synced_fingerprint != ''
                    THEN metadata_sync_state.last_synced_fingerprint
                    ELSE excluded.last_synced_fingerprint
                END,
                status = excluded.status,
                updated_at = excluded.updated_at
            """,
            bindings: [
                item.assetID.rawValue,
                item.sidecarURL.path,
                "\(item.catalogGeneration)",
                item.lastSyncedFingerprint ?? "",
                "pending",
                now
            ]
        )
    }

    public func pendingMetadataSyncItems(limit: Int? = nil) throws -> [MetadataSyncItem] {
        try metadataSyncItems(status: "pending", limit: limit)
    }

    public func pendingMetadataSyncItemCount() throws -> Int {
        try metadataSyncItemCount(status: "pending")
    }

    public func pendingMetadataSyncItem(assetID: AssetID) throws -> MetadataSyncItem? {
        try metadataSyncItem(assetID: assetID, status: "pending")
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

    public func recordPreviewGenerationPending(_ items: [PreviewGenerationItem]) throws {
        guard !items.isEmpty else { return }
        try database.transaction {
            for item in items {
                try recordPreviewGenerationPending(item)
            }
        }
    }

    public func recordPreviewGenerationFailure(
        assetID: AssetID,
        level: PreviewLevel,
        errorMessage: String
    ) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            INSERT INTO preview_generation_queue (
                asset_id,
                level,
                attempt_count,
                last_error,
                last_attempted_at,
                updated_at
            )
            VALUES (?, ?, 1, ?, ?, ?)
            ON CONFLICT(asset_id, level) DO UPDATE SET
                attempt_count = preview_generation_queue.attempt_count + 1,
                last_error = excluded.last_error,
                last_attempted_at = excluded.last_attempted_at,
                updated_at = excluded.updated_at
            """,
            bindings: [
                assetID.rawValue,
                level.rawValue,
                errorMessage,
                now,
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

    public func pendingPreviewGenerationItems(
        limit: Int? = nil,
        maximumAttemptCount: Int? = nil,
        requiresAvailableOriginal: Bool = false
    ) throws -> [PreviewGenerationItem] {
        if let limit, limit <= 0 {
            return []
        }
        if let maximumAttemptCount, maximumAttemptCount <= 0 {
            return []
        }
        var sql = """
        SELECT preview_generation_queue.asset_id, preview_generation_queue.level
        FROM preview_generation_queue
        """
        if requiresAvailableOriginal {
            sql += """

            INNER JOIN assets ON assets.id = preview_generation_queue.asset_id
            """
        }
        var bindings: [String] = []
        var clauses: [String] = []
        if let maximumAttemptCount {
            clauses.append("preview_generation_queue.attempt_count < ?")
            bindings.append("\(maximumAttemptCount)")
        }
        if requiresAvailableOriginal {
            clauses.append("assets.availability NOT IN (?, ?, ?)")
            bindings.append(SourceAvailability.offline.rawValue)
            bindings.append(SourceAvailability.missing.rawValue)
            bindings.append(SourceAvailability.moved.rawValue)
        }
        if !clauses.isEmpty {
            sql += "\nWHERE \(clauses.joined(separator: " AND "))"
        }
        sql += """

        ORDER BY preview_generation_queue.updated_at ASC
        """
        if let limit {
            sql += " LIMIT ?"
            bindings.append("\(limit)")
        }
        let rows = try database.rows(sql, bindings: bindings)
        return try rows.map(decodePreviewGenerationItem)
    }

    public func previewGenerationQueueState(assetID: AssetID, level: PreviewLevel) throws -> PreviewGenerationQueueState? {
        let rows = try database.rows(
            """
            SELECT asset_id, level, attempt_count, last_error, last_attempted_at
            FROM preview_generation_queue
            WHERE asset_id = ? AND level = ?
            LIMIT 1
            """,
            bindings: [assetID.rawValue, level.rawValue]
        )
        return try rows.first.map(decodePreviewGenerationQueueState)
    }

    public func previewGenerationQueueStates(limit: Int? = nil) throws -> [PreviewGenerationQueueState] {
        if let limit, limit <= 0 {
            return []
        }
        var sql = """
        SELECT asset_id, level, attempt_count, last_error, last_attempted_at
        FROM preview_generation_queue
        ORDER BY updated_at ASC
        """
        var bindings: [String] = []
        if let limit {
            sql += " LIMIT ?"
            bindings.append("\(limit)")
        }
        let rows = try database.rows(sql, bindings: bindings)
        return try rows.map(decodePreviewGenerationQueueState)
    }

    public func previewGenerationFailureAssetCount(assetIDs: [AssetID]) throws -> Int {
        guard !assetIDs.isEmpty else { return 0 }
        var seenAssetIDs = Set<AssetID>()
        let uniqueAssetIDs = assetIDs.filter { seenAssetIDs.insert($0).inserted }
        var count = 0
        for chunk in Self.chunks(uniqueAssetIDs, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                """
                SELECT COUNT(DISTINCT asset_id) AS count
                FROM preview_generation_queue
                WHERE asset_id IN (\(placeholders))
                    AND attempt_count > 0
                    AND COALESCE(last_error, '') != ''
                """,
                bindings: chunk.map(\.rawValue)
            )
            guard let countString = rows.first?["count"], let chunkCount = Int(countString) else {
                throw CatalogError.sqlite("preview generation failure count query returned no count")
            }
            count += chunkCount
        }
        return count
    }

    public func previewGenerationPendingAssetCount(assetIDs: [AssetID]) throws -> Int {
        guard !assetIDs.isEmpty else { return 0 }
        var seenAssetIDs = Set<AssetID>()
        let uniqueAssetIDs = assetIDs.filter { seenAssetIDs.insert($0).inserted }
        var count = 0
        for chunk in Self.chunks(uniqueAssetIDs, size: 500) {
            let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ", ")
            let rows = try database.rows(
                """
                SELECT COUNT(DISTINCT asset_id) AS count
                FROM preview_generation_queue
                WHERE asset_id IN (\(placeholders))
                """,
                bindings: chunk.map(\.rawValue)
            )
            guard let countString = rows.first?["count"], let chunkCount = Int(countString) else {
                throw CatalogError.sqlite("preview generation pending count query returned no count")
            }
            count += chunkCount
        }
        return count
    }

    public func metadataSyncConflictItems(limit: Int? = nil) throws -> [MetadataSyncItem] {
        try metadataSyncItems(status: "conflict", limit: limit)
    }

    public func metadataSyncConflictItemCount() throws -> Int {
        try metadataSyncItemCount(status: "conflict")
    }

    public func metadataSyncConflictItem(assetID: AssetID) throws -> MetadataSyncItem? {
        try metadataSyncItem(assetID: assetID, status: "conflict")
    }

    public func metadataSyncItem(assetID: AssetID) throws -> MetadataSyncItem? {
        let rows = try database.rows(
            """
            SELECT asset_id, sidecar_path, catalog_generation, last_synced_fingerprint, status, updated_at
            FROM metadata_sync_state
            WHERE asset_id = ?
            LIMIT 1
            """,
            bindings: [assetID.rawValue]
        )
        return try rows.first.map(decodeMetadataSyncItem)
    }

    public func metadataSyncStateUpdatedAt(assetID: AssetID) throws -> Date? {
        let rows = try database.rows(
            "SELECT updated_at FROM metadata_sync_state WHERE asset_id = ? LIMIT 1",
            bindings: [assetID.rawValue]
        )
        guard let updatedAtValue = rows.first?["updated_at"],
              let updatedAt = TimeInterval(updatedAtValue) else {
            return nil
        }
        return Date(timeIntervalSince1970: updatedAt)
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

        let issuesJSON = row["issues_json"] ?? "[]"
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
            issues: try decode([WorkSessionIssue].self, from: issuesJSON),
            starred: starred == "1",
            createdAt: Date(timeIntervalSince1970: createdAtInterval),
            updatedAt: Date(timeIntervalSince1970: updatedAtInterval)
        )
    }

    // Focus-family scores (focus, motionBlur, eyeSharpness) changed scale in
    // the 2026-07-06 calibration: rows written by the recalibrated providers
    // at any other provenance version are raw-scale, and mixing the two
    // scales poisons the likelyIssue/likelyPick queues, flaw badges, and
    // stack rankings. Every read treats those rows as absent, so affected
    // assets honestly report no focus-family read until re-evaluated.
    private static let focusFamilyKinds: [EvaluationKind] = [.focus, .motionBlur, .eyeSharpness]

    private static let calibratedFocusFamilyProviders: [(name: String, version: String)] = [
        (LocalImageMetricsEvaluationProvider.providerName, LocalImageMetricsEvaluationProvider.provenanceVersion),
        (FaceExpressionEvaluationProvider.providerName, FaceExpressionEvaluationProvider.provenanceVersion)
    ]

    /// SQL condition that is true for evaluation_signals rows on the current
    /// score scale; superseded raw-scale focus-family rows fail it.
    private static let currentScaleSignalSQL: String = {
        let kinds = focusFamilyKinds.map { "'\($0.rawValue)'" }.joined(separator: ", ")
        let staleProviders = calibratedFocusFamilyProviders
            .map { "(provider = '\($0.name)' AND version <> '\($0.version)')" }
            .joined(separator: " OR ")
        return "NOT (kind IN (\(kinds)) AND (\(staleProviders)))"
    }()

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
        // A provider's newer version supersedes its older rows for the same
        // kind. The primary key includes version, so without this prune a
        // version bump would leave stale rows beside fresh ones forever and
        // re-evaluation could never clear them.
        try database.execute(
            """
            DELETE FROM evaluation_signals
            WHERE asset_id = ?
              AND kind = ?
              AND provider = ?
              AND version <> ?
            """,
            bindings: [
                signal.assetID.rawValue,
                signal.kind.rawValue,
                signal.provenance.provider,
                signal.provenance.version
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

    private func decodeEvaluationFailure(_ row: [String: String]) throws -> CatalogEvaluationFailure {
        guard let assetID = row["asset_id"],
              let provider = row["provider"],
              let message = row["message"],
              let failedAtValue = row["failed_at"],
              let failedAt = Double(failedAtValue) else {
            throw CatalogError.sqlite("evaluation failure row is missing required columns")
        }

        return CatalogEvaluationFailure(
            assetID: AssetID(rawValue: assetID),
            provider: provider,
            message: message,
            failedAt: Date(timeIntervalSince1970: failedAt)
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
                let pattern = Self.likePattern(containing: trimmed)
                clauses.append(
                    """
                    (
                        LOWER(original_path) LIKE LOWER(?) ESCAPE '\\'
                        OR EXISTS (
                            SELECT 1
                            FROM evaluation_signals
                            WHERE evaluation_signals.asset_id = assets.id
                              AND (
                                LOWER(COALESCE(json_extract(value_json, '$.label._0'), '')) LIKE LOWER(?) ESCAPE '\\'
                                OR LOWER(COALESCE(json_extract(value_json, '$.text._0'), '')) LIKE LOWER(?) ESCAPE '\\'
                                OR EXISTS (
                                    SELECT 1
                                    FROM json_each(value_json, '$.labels._0')
                                    WHERE LOWER(json_each.value) LIKE LOWER(?) ESCAPE '\\'
                                )
                              )
                        )
                    )
                    """
                )
                bindings.append(contentsOf: [pattern, pattern, pattern, pattern])
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
            case .person(let name):
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                clauses.append(
                    """
                    EXISTS (
                        SELECT 1
                        FROM person_assets
                        JOIN people ON people.id = person_assets.person_id
                        WHERE person_assets.asset_id = assets.id
                          AND people.name = ? COLLATE NOCASE
                    )
                    """
                )
                bindings.append(trimmed)
            case .missingKeywords:
                clauses.append("NOT EXISTS (SELECT 1 FROM json_each(metadata_json, '$.keywords'))")
            case .availability(let availability):
                clauses.append("availability = ?")
                bindings.append(availability.rawValue)
            case .folderPrefix(let prefix):
                let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                clauses.append("original_path LIKE ? ESCAPE '\\'")
                bindings.append(Self.likePattern(prefix: trimmed))
            case .camera(let camera):
                let trimmed = camera.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                clauses.append(
                    """
                    (json_valid(technical_metadata_json) AND LOWER(COALESCE(json_extract(technical_metadata_json, '$.cameraMake'), '') || ' ' || COALESCE(json_extract(technical_metadata_json, '$.cameraModel'), '')) LIKE LOWER(?) ESCAPE '\\')
                    """
                )
                bindings.append(Self.likePattern(containing: trimmed))
            case .lens(let lens):
                let trimmed = lens.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                clauses.append(
                    "(json_valid(technical_metadata_json) AND LOWER(COALESCE(json_extract(technical_metadata_json, '$.lensModel'), '')) LIKE LOWER(?) ESCAPE '\\')"
                )
                bindings.append(Self.likePattern(containing: trimmed))
            case .isoAtLeast(let iso):
                guard iso > 0 else { continue }
                clauses.append(
                    "(json_valid(technical_metadata_json) AND CAST(json_extract(technical_metadata_json, '$.isoSpeed') AS INTEGER) >= ?)"
                )
                bindings.append("\(iso)")
            case .capturedAtOrAfter(let date):
                clauses.append(
                    "(json_valid(technical_metadata_json) AND CAST(json_extract(technical_metadata_json, '$.capturedAt') AS REAL) >= ?)"
                )
                bindings.append("\(date.timeIntervalSince1970)")
            case .capturedBefore(let date):
                clauses.append(
                    "(json_valid(technical_metadata_json) AND CAST(json_extract(technical_metadata_json, '$.capturedAt') AS REAL) < ?)"
                )
                bindings.append("\(date.timeIntervalSince1970)")
            case .withinGeoBounds(let bounds):
                clauses.append(
                    """
                    (json_valid(technical_metadata_json)
                     AND \(Self.latitudeExpressionSQL) BETWEEN ? AND ?
                     AND \(Self.longitudeExpressionSQL) BETWEEN ? AND ?)
                    """
                )
                bindings.append(contentsOf: [
                    "\(bounds.minLatitude)", "\(bounds.maxLatitude)",
                    "\(bounds.minLongitude)", "\(bounds.maxLongitude)"
                ])
            case .evaluationKind(let kind):
                if kind == .faceCount || kind == .faceQuality {
                    clauses.append(
                        """
                        EXISTS (SELECT 1 FROM evaluation_signals WHERE evaluation_signals.asset_id = assets.id AND kind = ?)
                        AND NOT EXISTS (
                            SELECT 1
                            FROM dismissed_face_assets
                            WHERE dismissed_face_assets.asset_id = assets.id
                        )
                        AND NOT EXISTS (
                            SELECT 1
                            FROM person_assets
                            WHERE person_assets.asset_id = assets.id
                        )
                        """
                    )
                } else {
                    clauses.append(
                        "EXISTS (SELECT 1 FROM evaluation_signals WHERE evaluation_signals.asset_id = assets.id AND kind = ?)"
                    )
                }
                bindings.append(kind.rawValue)
            case .unevaluated:
                clauses.append(
                    "NOT EXISTS (SELECT 1 FROM evaluation_signals WHERE evaluation_signals.asset_id = assets.id)"
                )
            case .likelyIssue:
                // Defect terms per the 2026-07-06 calibration study: focus
                // defect at the calibrated p5 (raw 0.06 / 0.15 = 0.4); no
                // motionBlur term (it is exactly 1 - focus, pure redundancy);
                // eyesOpen only when 0.0 - fractional CIDetector reads are
                // noise on tiny/occluded faces and rank rather than flag;
                // faceQuality defect at its own p5 (0.1) - below likelyPick's
                // 0.45 strong anchor, so one value can never be both a strong
                // read and a defect (the old 0.5 line flagged ~82% of face
                // photos and sat above the strong anchor).
                // Superseded raw-scale focus rows sit entirely below the
                // calibrated defect anchor and must not count as defects.
                clauses.append(
                    """
                    EXISTS (
                        SELECT 1
                        FROM evaluation_signals
                        WHERE evaluation_signals.asset_id = assets.id
                          AND \(Self.currentScaleSignalSQL)
                          AND (
                            (kind = 'focus' AND CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.4)
                            OR (
                                kind = 'exposure'
                                AND (
                                    CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.12
                                    OR CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.88
                                )
                            )
                            OR (
                                kind = 'eyesOpen'
                                AND CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.0
                            )
                            OR (
                                kind = 'faceQuality'
                                AND CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.1
                                AND NOT EXISTS (
                                    SELECT 1
                                    FROM dismissed_face_assets
                                    WHERE dismissed_face_assets.asset_id = assets.id
                                )
                                AND NOT EXISTS (
                                    SELECT 1
                                    FROM person_assets
                                    WHERE person_assets.asset_id = assets.id
                                )
                            )
                          )
                    )
                    """
                )
            case .likelyPick:
                // Strong-read thresholds are per kind because the three kinds
                // live on incompatible scales (2026-07-06 calibration study):
                // calibrated focus >= 0.8 (raw p75 0.12 / 0.15 ceiling),
                // aesthetics >= 0.65 (calibrated p90), and Vision faceQuality
                // >= 0.45 (p75) - each anchors "strong" at that kind's top
                // quartile-to-decile on the study corpus.
                clauses.append(
                    """
                    json_extract(metadata_json, '$.flag') IS NULL
                    AND EXISTS (
                        SELECT 1
                        FROM evaluation_signals
                        WHERE evaluation_signals.asset_id = assets.id
                          AND \(Self.currentScaleSignalSQL)
                          AND (
                            (kind = 'focus' AND CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.8)
                            OR (kind = 'aesthetics' AND CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.65)
                            OR (kind = 'faceQuality' AND CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.45)
                          )
                    )
                    AND NOT EXISTS (
                        SELECT 1
                        FROM evaluation_signals
                        WHERE evaluation_signals.asset_id = assets.id
                          AND \(Self.currentScaleSignalSQL)
                          AND (
                            (kind = 'focus' AND CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.4)
                            OR (
                                kind = 'exposure'
                                AND (
                                    CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.12
                                    OR CAST(json_extract(value_json, '$.score._0') AS REAL) >= 0.88
                                )
                            )
                            OR (kind = 'eyesOpen' AND CAST(json_extract(value_json, '$.score._0') AS REAL) <= 0.0)
                          )
                    )
                    """
                )
            case .evaluationFailure:
                clauses.append(
                    "EXISTS (SELECT 1 FROM evaluation_failures WHERE evaluation_failures.asset_id = assets.id)"
                )
            case .metadataSyncPending:
                clauses.append(
                    """
                    EXISTS (
                        SELECT 1
                        FROM metadata_sync_state
                        WHERE metadata_sync_state.asset_id = assets.id
                          AND metadata_sync_state.status = 'pending'
                    )
                    """
                )
            case .metadataSyncConflict:
                clauses.append(
                    """
                    EXISTS (
                        SELECT 1
                        FROM metadata_sync_state
                        WHERE metadata_sync_state.asset_id = assets.id
                          AND metadata_sync_state.status = 'conflict'
                    )
                    """
                )
            case .importBatch(let batchID):
                let trimmed = batchID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    clauses.append("0 = 1")
                    continue
                }
                let setIDColumnNames = ["output_set_ids_json"]
                let dynamicAssetIDs = try workSessionDynamicAssetIDs(
                    sessionID: trimmed,
                    includesInputSets: false,
                    includesOutputSets: true
                )
                Self.appendWorkSessionMembershipClause(
                    setIDColumnNames: setIDColumnNames,
                    sessionID: trimmed,
                    dynamicAssetIDs: dynamicAssetIDs,
                    to: &clauses,
                    bindings: &bindings
                )
            case .workSession(let sessionID):
                let trimmed = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    clauses.append("0 = 1")
                    continue
                }
                let setIDColumnNames = ["input_set_ids_json", "output_set_ids_json"]
                let dynamicAssetIDs = try workSessionDynamicAssetIDs(
                    sessionID: trimmed,
                    includesInputSets: true,
                    includesOutputSets: true
                )
                Self.appendWorkSessionMembershipClause(
                    setIDColumnNames: setIDColumnNames,
                    sessionID: trimmed,
                    dynamicAssetIDs: dynamicAssetIDs,
                    to: &clauses,
                    bindings: &bindings
                )
            }
        }

        guard !clauses.isEmpty else {
            return ("", [])
        }
        return (" WHERE " + clauses.joined(separator: " AND "), bindings)
    }

    private func workSessionDynamicAssetIDs(
        sessionID: String,
        includesInputSets: Bool,
        includesOutputSets: Bool
    ) throws -> [AssetID] {
        let rows = try database.rows("SELECT input_set_ids_json, output_set_ids_json FROM work_sessions WHERE id = ?", bindings: [sessionID])
        guard let row = rows.first else { return [] }
        var assetIDs: [AssetID] = []
        var seenAssetIDs: Set<AssetID> = []
        var setIDs: [AssetSetID] = []
        if includesInputSets, let inputJSON = row["input_set_ids_json"] {
            setIDs.append(contentsOf: try Self.decodeAssetSetIDs(inputJSON))
        }
        if includesOutputSets, let outputJSON = row["output_set_ids_json"] {
            setIDs.append(contentsOf: try Self.decodeAssetSetIDs(outputJSON))
        }
        for setID in setIDs {
            let set: AssetSet
            do {
                set = try assetSet(id: setID)
            } catch CatalogError.notFound {
                continue
            }
            guard case .dynamic(let query) = set.membership else {
                continue
            }
            for assetID in try self.assetIDs(matching: query) where seenAssetIDs.insert(assetID).inserted {
                assetIDs.append(assetID)
            }
        }
        return assetIDs
    }

    private static func decodeAssetSetIDs(_ json: String) throws -> [AssetSetID] {
        let data = Data(json.utf8)
        return try JSONDecoder().decode([AssetSetID].self, from: data)
    }

    private static func appendWorkSessionMembershipClause(
        setIDColumnNames: [String],
        sessionID: String,
        dynamicAssetIDs: [AssetID],
        to clauses: inout [String],
        bindings: inout [String]
    ) {
        var membershipClauses = [workSessionAssetMembershipClause(setIDColumnNames: setIDColumnNames)]
        bindings.append(contentsOf: Array(repeating: sessionID, count: setIDColumnNames.count * 2))
        if !dynamicAssetIDs.isEmpty {
            membershipClauses.append("assets.id IN (\(Array(repeating: "?", count: dynamicAssetIDs.count).joined(separator: ", ")))")
            bindings.append(contentsOf: dynamicAssetIDs.map(\.rawValue))
        }
        clauses.append("(\(membershipClauses.joined(separator: " OR ")))")
    }

    private static func workSessionAssetMembershipClause(setIDColumnNames: [String]) -> String {
        let membershipSelectors = setIDColumnNames.flatMap { columnName in
            [
                workSessionAssetMembershipSelector(setIDColumnName: columnName, membershipPath: "$.manual._0"),
                workSessionAssetMembershipSelector(setIDColumnName: columnName, membershipPath: "$.snapshot._0")
            ]
        }
        return "assets.id IN (\n\(membershipSelectors.joined(separator: "\nUNION\n"))\n)"
    }

    private static func workSessionAssetMembershipSelector(setIDColumnName: String, membershipPath: String) -> String {
        """
        SELECT json_extract(session_assets.value, '$.rawValue')
        FROM work_sessions
        JOIN json_each(work_sessions.\(setIDColumnName)) session_sets
        JOIN asset_sets ON asset_sets.id = json_extract(session_sets.value, '$.rawValue')
        JOIN json_each(asset_sets.membership_json, '\(membershipPath)') session_assets
        WHERE work_sessions.id = ?
        """
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

    private static func folderPath(forOriginalPath originalPath: String) -> String {
        let folderURL = URL(fileURLWithPath: originalPath).deletingLastPathComponent()
        var path = folderURL.path.isEmpty ? "/" : folderURL.path
        if !path.hasSuffix("/") {
            path.append("/")
        }
        return path
    }

    private static func folderName(forFolderPath folderPath: String) -> String {
        let trimmedPath = folderPath == "/" ? folderPath : String(folderPath.dropLast(folderPath.hasSuffix("/") ? 1 : 0))
        let name = URL(fileURLWithPath: trimmedPath).lastPathComponent
        return name.isEmpty ? folderPath : name
    }

    private static func normalizedDirectoryPath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        guard path != "/" else { return path }
        return path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func assetCounts(underSourceRootPath rootPath: String) throws -> (assetCount: Int, unavailableAssetCount: Int) {
        let rows = try database.rows(
            """
            SELECT
                COUNT(*) AS asset_count,
                COALESCE(SUM(CASE WHEN availability != ? THEN 1 ELSE 0 END), 0) AS unavailable_asset_count
            FROM assets
            WHERE original_path = ?
               OR original_path LIKE ? ESCAPE '\\'
            """,
            bindings: [
                SourceAvailability.online.rawValue,
                rootPath,
                "\(Self.escapedLikePattern(rootPath == "/" ? "/" : rootPath + "/"))%"
            ]
        )
        guard let row = rows.first,
              let assetCountValue = row["asset_count"],
              let assetCount = Int(assetCountValue),
              let unavailableAssetCountValue = row["unavailable_asset_count"],
              let unavailableAssetCount = Int(unavailableAssetCountValue) else {
            throw CatalogError.sqlite("source root asset count query returned no count")
        }
        return (assetCount, unavailableAssetCount)
    }

    private static func relativePath(for originalURL: URL, under rootPath: String) -> String? {
        let path = originalURL.standardizedFileURL.path
        guard path != rootPath else { return "" }
        let prefix = rootPath == "/" ? "/" : "\(rootPath)/"
        guard path.hasPrefix(prefix) else { return nil }
        return String(path.dropFirst(prefix.count))
    }

    private static func escapedLikePattern(_ value: String) -> String {
        var escaped = ""
        for character in value {
            switch character {
            case "%", "_", "\\":
                escaped.append("\\")
                escaped.append(character)
            default:
                escaped.append(character)
            }
        }
        return escaped
    }

    private static func fingerprint(for url: URL) -> FileFingerprint? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }
        return FileFingerprint(
            size: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            modificationDate: attributes[.modificationDate] as? Date ?? Date(timeIntervalSince1970: 0)
        )
    }

    private static func volumeIdentifier(for url: URL) -> String? {
        guard let identifier = try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier else {
            return nil
        }
        if let data = identifier as? Data {
            return data.base64EncodedString()
        }
        if let data = identifier as? NSData {
            return data.base64EncodedString()
        }
        if let string = identifier as? String {
            return string
        }
        return String(describing: identifier)
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

    private func metadataSyncItem(assetID: AssetID, status: String) throws -> MetadataSyncItem? {
        let rows = try database.rows(
            """
            SELECT asset_id, sidecar_path, catalog_generation, last_synced_fingerprint, status, updated_at
            FROM metadata_sync_state
            WHERE asset_id = ? AND status = ?
            LIMIT 1
            """,
            bindings: [assetID.rawValue, status]
        )
        return try rows.first.map(decodeMetadataSyncItem)
    }

    private func metadataSyncItemCount(status: String) throws -> Int {
        let rows = try database.rows(
            """
            SELECT COUNT(*) AS count
            FROM metadata_sync_state
            WHERE status = ?
            """,
            bindings: [status]
        )
        guard let countString = rows.first?["count"], let count = Int(countString) else {
            throw CatalogError.sqlite("metadata sync count query returned no count")
        }
        return count
    }

    private func metadataSyncItems(status: String, limit: Int? = nil) throws -> [MetadataSyncItem] {
        if let limit, limit <= 0 {
            return []
        }
        var sql = """
        SELECT asset_id, sidecar_path, catalog_generation, last_synced_fingerprint, status, updated_at
        FROM metadata_sync_state
        WHERE status = ?
        ORDER BY updated_at ASC
        """
        var bindings = [status]
        if let limit {
            sql += " LIMIT ?"
            bindings.append("\(limit)")
        }
        let rows = try database.rows(sql, bindings: bindings)
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
        let lastSyncedAt: Date?
        if row["status"] == "synced",
           let updatedAtValue = row["updated_at"],
           let updatedAt = TimeInterval(updatedAtValue) {
            lastSyncedAt = Date(timeIntervalSince1970: updatedAt)
        } else {
            lastSyncedAt = nil
        }
        return MetadataSyncItem(
            assetID: AssetID(rawValue: assetID),
            sidecarURL: URL(fileURLWithPath: sidecarPath),
            catalogGeneration: generation,
            lastSyncedFingerprint: fingerprint.isEmpty ? nil : fingerprint,
            lastSyncedAt: lastSyncedAt
        )
    }

    private func updateMetadataSyncSidecarPathIfPresent(assetID: AssetID, sidecarURL: URL) throws {
        let now = "\(Date().timeIntervalSince1970)"
        try database.execute(
            """
            UPDATE metadata_sync_state
            SET sidecar_path = ?,
                updated_at = ?
            WHERE asset_id = ?
            """,
            bindings: [
                sidecarURL.path,
                now,
                assetID.rawValue
            ]
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

    private func decodePreviewGenerationQueueState(_ row: [String: String]) throws -> PreviewGenerationQueueState {
        let item = try decodePreviewGenerationItem(row)
        guard let attemptCountString = row["attempt_count"],
              let attemptCount = Int(attemptCountString) else {
            throw CatalogError.sqlite("preview generation state row is missing attempt_count")
        }
        let lastAttemptedAt = row["last_attempted_at"]
            .flatMap(Double.init)
            .map(Date.init(timeIntervalSince1970:))
        return PreviewGenerationQueueState(
            item: item,
            attemptCount: attemptCount,
            lastErrorMessage: row["last_error"],
            lastAttemptedAt: lastAttemptedAt
        )
    }

    private struct FaceObservationPayload: Codable {
        var boundingBox: FaceBoundingBox
        var captureQuality: Double?
        var embedding: [Double]
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
