import Foundation
import SQLite3

public final class CatalogDatabase: @unchecked Sendable {
    private static let busyTimeoutMilliseconds: Int32 = 5_000

    private let handle: OpaquePointer
    var rowQueryObserver: ((String) -> Void)?

    private init(handle: OpaquePointer) {
        self.handle = handle
    }

    deinit {
        sqlite3_close(handle)
    }

    public static func open(at url: URL) throws -> CatalogDatabase {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
            throw CatalogError.sqlite("unable to open catalog database")
        }
        guard sqlite3_busy_timeout(handle, busyTimeoutMilliseconds) == SQLITE_OK else {
            let message = String(cString: sqlite3_errmsg(handle))
            sqlite3_close(handle)
            throw CatalogError.sqlite(message)
        }
        return CatalogDatabase(handle: handle)
    }

    public func migrate() throws {
        for statement in CatalogMigrations.statements {
            try execute(statement)
        }
        try addColumnIfMissing(table: "assets", column: "technical_metadata_json", definition: "TEXT")
        try addColumnIfMissing(table: "source_roots", column: "security_scoped_bookmark_base64", definition: "TEXT")
        try addColumnIfMissing(table: "work_sessions", column: "issues_json", definition: "TEXT NOT NULL DEFAULT '[]'")
        try addColumnIfMissing(
            table: "preview_generation_queue",
            column: "attempt_count",
            definition: "INTEGER NOT NULL DEFAULT 0"
        )
        try addColumnIfMissing(table: "preview_generation_queue", column: "last_error", definition: "TEXT")
        try addColumnIfMissing(table: "preview_generation_queue", column: "last_attempted_at", definition: "REAL")
        try execute(
            "INSERT OR REPLACE INTO catalog_meta (key, value) VALUES ('schema_version', ?)",
            bindings: ["\(CatalogMigrations.version)"]
        )
    }

    func execute(_ sql: String, bindings: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogError.sqlite(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw CatalogError.sqlite(lastError)
        }
    }

    func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            try work()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func rows(_ sql: String, bindings: [String] = []) throws -> [[String: String]] {
        rowQueryObserver?(sql)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogError.sqlite(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var result: [[String: String]] = []
        var stepResult = sqlite3_step(statement)
        while stepResult == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let value = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: value)
                }
            }
            result.append(row)
            stepResult = sqlite3_step(statement)
        }
        guard stepResult == SQLITE_DONE else {
            throw CatalogError.sqlite(lastError)
        }
        return result
    }

    private func bind(_ bindings: [String], to statement: OpaquePointer?) throws {
        for (index, value) in bindings.enumerated() {
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) == SQLITE_OK else {
                throw CatalogError.sqlite(lastError)
            }
        }
    }

    private var lastError: String {
        String(cString: sqlite3_errmsg(handle))
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) throws {
        let columns = try rows("PRAGMA table_info(\(table))")
        guard !columns.contains(where: { $0["name"] == column }) else { return }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }
}
