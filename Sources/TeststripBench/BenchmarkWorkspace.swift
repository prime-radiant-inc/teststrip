import Foundation

public enum BenchmarkWorkspace {
    public static func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "teststrip-bench-\(UUID().uuidString)",
            isDirectory: true
        )
    }
}
