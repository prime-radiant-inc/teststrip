import Foundation

enum PreviewCacheFileCounter {
    static func count(root: URL) throws -> Int {
        guard FileManager.default.fileExists(atPath: root.path) else { return 0 }
        let assetDirectories = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try assetDirectories.reduce(0) { count, assetDirectory in
            count + (try FileManager.default.contentsOfDirectory(
                at: assetDirectory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ).filter { $0.pathExtension == "jpg" }.count)
        }
    }
}
