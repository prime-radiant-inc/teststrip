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
        var encoded = ""

        for byte in rawValue.utf8 {
            if isAllowedAssetDirectoryByte(byte) {
                encoded.append(Character(UnicodeScalar(byte)))
            } else {
                encoded.append("_")
                let hex = String(byte, radix: 16, uppercase: true)
                if hex.count == 1 {
                    encoded.append("0")
                }
                encoded.append(hex)
            }
        }

        if encoded.isEmpty {
            return stableFallbackDirectoryName(for: rawValue)
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

    private static func stableFallbackDirectoryName(for rawValue: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037

        for byte in rawValue.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        return "asset-\(String(hash, radix: 16))"
    }
}
