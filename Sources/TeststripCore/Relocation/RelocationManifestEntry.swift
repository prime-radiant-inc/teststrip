import Foundation

/// One file's move recorded for reversal: where the original (and its sidecar,
/// if any) came from and went to. The reversal replays these to → from.
public struct RelocationManifestEntry: Equatable, Sendable {
    public var assetID: AssetID
    public var originalFrom: URL
    public var originalTo: URL
    public var sidecarFrom: URL?
    public var sidecarTo: URL?

    public init(
        assetID: AssetID,
        originalFrom: URL,
        originalTo: URL,
        sidecarFrom: URL?,
        sidecarTo: URL?
    ) {
        self.assetID = assetID
        self.originalFrom = originalFrom
        self.originalTo = originalTo
        self.sidecarFrom = sidecarFrom
        self.sidecarTo = sidecarTo
    }
}
