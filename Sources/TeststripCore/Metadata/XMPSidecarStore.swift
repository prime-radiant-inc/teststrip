import CryptoKit
import Foundation

public struct XMPSidecarWriteResult: Equatable, Sendable {
    public var sidecarURL: URL
    public var fingerprint: String

    public init(sidecarURL: URL, fingerprint: String) {
        self.sidecarURL = sidecarURL
        self.fingerprint = fingerprint
    }
}

public struct XMPSidecarStore: Sendable {
    public init() {}

    public func sidecarURL(forOriginalAt originalURL: URL) -> URL {
        originalURL.appendingPathExtension("xmp")
    }

    public func write(metadata: AssetMetadata, forOriginalAt originalURL: URL) throws -> XMPSidecarWriteResult {
        let sidecarURL = sidecarURL(forOriginalAt: originalURL)
        let data = try XMPPacket(metadata: metadata).xmlData()
        try data.write(to: sidecarURL, options: [.atomic])
        return XMPSidecarWriteResult(sidecarURL: sidecarURL, fingerprint: Self.fingerprint(for: data))
    }

    public static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
