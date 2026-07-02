enum CatalogMigrations {
    static let version = 7

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
            technical_metadata_json TEXT,
            catalog_generation INTEGER NOT NULL DEFAULT 1,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE UNIQUE INDEX IF NOT EXISTS idx_assets_original_path_unique ON assets(original_path)",
        "CREATE INDEX IF NOT EXISTS idx_assets_availability ON assets(availability)",
        """
        CREATE TABLE IF NOT EXISTS metadata_sync_state (
            asset_id TEXT PRIMARY KEY NOT NULL,
            sidecar_path TEXT NOT NULL,
            catalog_generation INTEGER NOT NULL,
            last_synced_fingerprint TEXT NOT NULL,
            status TEXT NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_metadata_sync_status ON metadata_sync_state(status)",
        """
        CREATE TABLE IF NOT EXISTS preview_generation_queue (
            asset_id TEXT NOT NULL,
            level TEXT NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (asset_id, level)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_preview_generation_queue_updated_at ON preview_generation_queue(updated_at)",
        """
        CREATE TABLE IF NOT EXISTS asset_sets (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            membership_json TEXT NOT NULL,
            starred INTEGER NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_asset_sets_starred ON asset_sets(starred)",
        """
        CREATE TABLE IF NOT EXISTS evaluation_signals (
            asset_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            value_json TEXT NOT NULL,
            confidence REAL NOT NULL,
            provenance_json TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            version TEXT NOT NULL,
            settings_hash TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (asset_id, kind, provider, model, version, settings_hash)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_evaluation_signals_asset ON evaluation_signals(asset_id)",
        """
        CREATE TABLE IF NOT EXISTS work_sessions (
            id TEXT PRIMARY KEY NOT NULL,
            kind TEXT NOT NULL,
            intent TEXT NOT NULL,
            title TEXT NOT NULL,
            detail TEXT NOT NULL,
            status TEXT NOT NULL,
            input_set_ids_json TEXT NOT NULL,
            output_set_ids_json TEXT NOT NULL,
            completed_unit_count INTEGER NOT NULL,
            total_unit_count TEXT NOT NULL,
            failure_count INTEGER NOT NULL,
            starred INTEGER NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_work_sessions_updated_at ON work_sessions(updated_at)",
        "CREATE INDEX IF NOT EXISTS idx_work_sessions_starred ON work_sessions(starred)"
    ]
}
