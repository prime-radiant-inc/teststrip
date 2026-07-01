import Foundation

public struct PreviewCacheKey: Hashable, Sendable {
    public var assetID: AssetID
    public var level: PreviewLevel

    public init(assetID: AssetID, level: PreviewLevel) {
        self.assetID = assetID
        self.level = level
    }
}

public struct PreviewCache: Sendable {
    public var root: URL

    public init(root: URL) {
        self.root = root
    }

    public func url(for key: PreviewCacheKey) -> URL {
        let assetDirectoryName = Self.safeAssetDirectoryName(for: key.assetID.rawValue)

        return root
            .appendingPathComponent(assetDirectoryName, isDirectory: true)
            .appendingPathComponent("\(key.level.rawValue).jpg")
    }

    private static func safeAssetDirectoryName(for rawValue: String) -> String {
        if !rawValue.isEmpty && rawValue.utf8.allSatisfy(isAllowedAssetDirectoryByte) {
            return rawValue
        }

        var encoded = "~"

        for byte in rawValue.utf8 {
            let hex = String(byte, radix: 16, uppercase: true)
            if hex.count == 1 {
                encoded.append("0")
            }
            encoded.append(hex)
        }

        return encoded
    }

    private static func isAllowedAssetDirectoryByte(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) ||
            (97...122).contains(byte) ||
            (48...57).contains(byte) ||
            byte == 45 ||
            byte == 95
    }
}
