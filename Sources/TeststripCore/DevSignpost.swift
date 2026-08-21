import Foundation
import os.signpost

/// Dev-mode signpost instrumentation for diagnosing main-thread beachballs.
///
/// In DEBUG builds, wraps `os_signpost` so Instruments and `log show` can trace
/// every expensive operation. In release builds, compiles to nothing — no
/// runtime cost, no import overhead.
///
/// Usage:
/// ```swift
/// let token = DevSignpost.begin("buildSidebarSections")
/// // ... work ...
/// DevSignpost.end(token)
/// ```
///
/// Or for a full function:
/// ```swift
/// DevSignpost.trace("reload") {
///     try reload()
/// }
/// ```
///
/// View in Instruments → Points of Interest, or:
/// ```sh
/// log show --predicate 'subsystem == "com.teststrip.app" AND category == "dev-signpost"' --info
/// ```

#if DEBUG
public enum DevSignpost {
    private static let log = OSLog(
        subsystem: "com.teststrip.app",
        category: "dev-signpost"
    )

    static let enabled: Bool = {
        // Allow disabling via env var for targeted profiling sessions.
        ProcessInfo.processInfo.environment["TESTSTRIP_DISABLE_SIGNPOSTS"] == nil
    }()

    @inline(__always)
    public static func begin(_ name: StaticString) -> OSSignpostID {
        guard enabled else { return .invalid }
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    @inline(__always)
    public static func end(_ id: OSSignpostID, _ name: StaticString) {
        guard enabled, id != .invalid else { return }
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    @inline(__always)
    public static func trace<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        guard enabled else { return try body() }
        let id = begin(name)
        defer { end(id, name) }
        return try body()
    }

    @inline(__always)
    public static func trace<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        guard enabled else { return try await body() }
        let id = begin(name)
        defer { end(id, name) }
        return try await body()
    }
}
#else
public enum DevSignpost {
    @inline(__always)
    public static func begin(_ name: StaticString) -> Int { 0 }

    @inline(__always)
    public static func end(_ id: Int, _ name: StaticString) {}

    @inline(__always)
    public static func trace<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        try body()
    }

    @inline(__always)
    public static func trace<T>(_ name: StaticString, _ body: () async throws -> T) async rethrows -> T {
        try await body()
    }
}
#endif
