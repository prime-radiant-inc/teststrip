import Foundation
import SQLite3

public final class CatalogDatabase: @unchecked Sendable {
    private let handle: OpaquePointer

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
        return CatalogDatabase(handle: handle)
    }

    public func migrate() throws {
        for statement in CatalogMigrations.statements {
            try execute(statement)
        }
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

    func rows(_ sql: String, bindings: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw CatalogError.sqlite(lastError)
        }
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement)

        var result: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let value = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: value)
                }
            }
            result.append(row)
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
}
