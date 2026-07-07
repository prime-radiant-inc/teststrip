enum CatalogMigrations {
    static let version = 17

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
            attempt_count INTEGER NOT NULL DEFAULT 0,
            last_error TEXT,
            last_attempted_at REAL,
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
        "CREATE INDEX IF NOT EXISTS idx_evaluation_signals_kind_asset ON evaluation_signals(kind, asset_id)",
        """
        CREATE TABLE IF NOT EXISTS evaluation_failures (
            asset_id TEXT NOT NULL,
            provider TEXT NOT NULL,
            message TEXT NOT NULL,
            failed_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (asset_id, provider)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_evaluation_failures_asset ON evaluation_failures(asset_id)",
        "CREATE INDEX IF NOT EXISTS idx_evaluation_failures_updated_at ON evaluation_failures(updated_at)",
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
            issues_json TEXT NOT NULL DEFAULT '[]',
            starred INTEGER NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_work_sessions_updated_at ON work_sessions(updated_at)",
        "CREATE INDEX IF NOT EXISTS idx_work_sessions_starred ON work_sessions(starred)",
        """
        CREATE TABLE IF NOT EXISTS source_roots (
            path TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            security_scoped_bookmark_base64 TEXT,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_source_roots_updated_at ON source_roots(updated_at)",
        """
        CREATE TABLE IF NOT EXISTS people (
            id TEXT PRIMARY KEY NOT NULL,
            name TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_people_name ON people(name COLLATE NOCASE)",
        """
        CREATE TABLE IF NOT EXISTS person_assets (
            person_id TEXT NOT NULL,
            asset_id TEXT NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (person_id, asset_id)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_person_assets_asset ON person_assets(asset_id)",
        """
        CREATE TABLE IF NOT EXISTS dismissed_face_assets (
            asset_id TEXT PRIMARY KEY NOT NULL,
            created_at REAL NOT NULL
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS face_observations (
            asset_id TEXT NOT NULL,
            face_index INTEGER NOT NULL,
            face_json TEXT NOT NULL,
            provenance_json TEXT NOT NULL,
            provider TEXT NOT NULL,
            model TEXT NOT NULL,
            version TEXT NOT NULL,
            settings_hash TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL,
            PRIMARY KEY (asset_id, face_index, provider, model, version, settings_hash)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_face_observations_asset ON face_observations(asset_id)",
        """
        CREATE TABLE IF NOT EXISTS person_faces (
            person_id TEXT NOT NULL,
            asset_id TEXT NOT NULL,
            face_index INTEGER NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (asset_id, face_index)
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_person_faces_person ON person_faces(person_id)",
        """
        CREATE TABLE IF NOT EXISTS dismissed_faces (
            asset_id TEXT NOT NULL,
            face_index INTEGER NOT NULL,
            created_at REAL NOT NULL,
            PRIMARY KEY (asset_id, face_index)
        )
        """,
        """
        CREATE TABLE IF NOT EXISTS autopilot_proposals (
            id TEXT PRIMARY KEY NOT NULL,
            run_id TEXT NOT NULL,
            asset_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            keyword TEXT,
            rationale TEXT NOT NULL,
            confidence REAL NOT NULL,
            status TEXT NOT NULL,
            created_at REAL NOT NULL,
            updated_at REAL NOT NULL
        )
        """,
        "CREATE INDEX IF NOT EXISTS idx_autopilot_proposals_run ON autopilot_proposals(run_id)",
        "CREATE INDEX IF NOT EXISTS idx_autopilot_proposals_status ON autopilot_proposals(status)"
    ]
}
