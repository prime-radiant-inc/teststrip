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
        let data: Data
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            data = try XMPPacket(metadata: metadata).xmlData(mergingInto: Data(contentsOf: sidecarURL))
        } else {
            data = try XMPPacket(metadata: metadata).xmlData()
        }
        try data.write(to: sidecarURL, options: [.atomic])
        return XMPSidecarWriteResult(sidecarURL: sidecarURL, fingerprint: Self.fingerprint(for: data))
    }

    public func modificationDate(forSidecarAt sidecarURL: URL) throws -> Date {
        let attributes = try FileManager.default.attributesOfItem(atPath: sidecarURL.path)
        guard let modificationDate = attributes[.modificationDate] as? Date else {
            throw TeststripError.io("missing XMP modification date \(sidecarURL.path)")
        }
        return modificationDate
    }

    public static func fingerprint(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
