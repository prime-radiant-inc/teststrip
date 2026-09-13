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
        existingSidecarURL(forOriginalAt: originalURL) ?? defaultSidecarURL(forOriginalAt: originalURL)
    }

    public func defaultSidecarURL(forOriginalAt originalURL: URL) -> URL {
        originalURL.appendingPathExtension("xmp")
    }

    public func existingSidecarURL(forOriginalAt originalURL: URL) -> URL? {
        let primarySidecarURL = defaultSidecarURL(forOriginalAt: originalURL)
        if FileManager.default.fileExists(atPath: primarySidecarURL.path) {
            return primarySidecarURL
        }

        guard let adobeStyleSidecarURL = adobeStyleSidecarURL(forOriginalAt: originalURL),
              FileManager.default.fileExists(atPath: adobeStyleSidecarURL.path) else {
            return nil
        }
        let claimedExtension = claimedSidecarExtension(at: adobeStyleSidecarURL)
        let originalExtension = originalURL.pathExtension.lowercased()
        if hasSiblingWithSameBasename(as: originalURL) {
            // Ambiguous basename: bind only when the sidecar explicitly
            // claims this original.
            return claimedExtension == originalExtension ? adobeStyleSidecarURL : nil
        }
        // Unambiguous basename: bind unless the sidecar explicitly claims a
        // different original (e.g. a culled RAW+JPEG sibling), so plain
        // attribute-free frame.xmp sidecars keep working.
        return claimedExtension == nil || claimedExtension == originalExtension
            ? adobeStyleSidecarURL
            : nil
    }

    public func write(metadata: AssetMetadata, rotation: Int? = nil, forOriginalAt originalURL: URL) throws -> XMPSidecarWriteResult {
        let sidecarURL = sidecarURL(forOriginalAt: originalURL)
        let data: Data
        if FileManager.default.fileExists(atPath: sidecarURL.path) {
            data = try XMPPacket(metadata: metadata, rotation: rotation).xmlData(mergingInto: Data(contentsOf: sidecarURL))
        } else {
            data = try XMPPacket(metadata: metadata, rotation: rotation).xmlData()
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

    private func adobeStyleSidecarURL(forOriginalAt originalURL: URL) -> URL? {
        let primarySidecarURL = defaultSidecarURL(forOriginalAt: originalURL)
        let adobeStyleSidecarURL = originalURL.deletingPathExtension().appendingPathExtension("xmp")
        guard adobeStyleSidecarURL.path != primarySidecarURL.path else {
            return nil
        }
        return adobeStyleSidecarURL
    }

    /// Adobe tools record which basename-shared original a sidecar belongs to via
    /// `photoshop:SidecarForExtension`. Returns the claimed extension lowercased, or nil
    /// when the sidecar is unreadable or carries no claim.
    private func claimedSidecarExtension(at sidecarURL: URL) -> String? {
        guard let sidecarData = try? Data(contentsOf: sidecarURL) else {
            return nil
        }
        return XMPPacket.sidecarForExtension(in: sidecarData)?.lowercased()
    }

    private func hasSiblingWithSameBasename(as originalURL: URL) -> Bool {
        let fileManager = FileManager.default
        let directoryURL = originalURL.deletingLastPathComponent()
        let originalPath = originalURL.standardizedFileURL.path
        let originalBasename = originalURL.deletingPathExtension().lastPathComponent

        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return true
        }

        return contents.contains { candidateURL in
            guard candidateURL.standardizedFileURL.path != originalPath else {
                return false
            }
            guard candidateURL.deletingPathExtension().lastPathComponent == originalBasename else {
                return false
            }
            // Only another catalogable original makes the basename ambiguous.
            // A same-stem file Teststrip would never import as a photo — a
            // Live Photo's `.MOV`, Apple's `.AAE` adjustments sidecar, a
            // layered `.PSD` edit — sits in the directory too but cannot own
            // the photo's XMP, so it must not block binding the sidecar that
            // is right there beside the original.
            return ImageIODecodeProvider.catalogableExtensions
                .contains(candidateURL.pathExtension.lowercased())
        }
    }
}
