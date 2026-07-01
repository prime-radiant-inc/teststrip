enum CatalogMigrations {
    static let version = 1

    static let statements = [
        """
        CREATE TABLE IF NOT EXISTS catalog_meta (
            key TEXT PRIMARY KEY NOT NULL,
            value TEXT NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS assets (
            id TEXT PRIMARY KEY NOT NULL,
            original_path TEXT NOT NULL,
            volume_identifier TEXT,
            fingerprint_json TEXT NOT NULL,
            availability TEXT NOT NULL,
            metadata_json TEXT NOT NULL,
            catalog_generation INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_assets_original_path ON assets(original_path)",
        "CREATE INDEX IF NOT EXISTS idx_assets_availability ON assets(availability)"
    ]
}
