import Foundation

/// Where a relocation moves rejects to: a user-chosen folder (files stay on
/// disk, catalog rows are repointed) or the platform Trash (files become
/// recoverable via Finder "Put Back", catalog rows are removed and snapshotted
/// for restore).
public enum RelocationMode: Equatable, Sendable {
    case folder(URL)
    case trash
}

/// One file's move recorded for reversal: where the original (and its sidecar,
/// if any) came from and went to. The reversal replays these to → from.
///
/// For trash-mode entries, `originalTo`/`sidecarTo` hold the resulting Trash
/// URL(s) `Recycler.trash(_:)` returned, and `assetSnapshot` carries the full
/// catalog row (metadata + source linkage) removed from the catalog when the
/// asset was trashed, so Move Back can re-insert it verbatim. The preview
/// cache key for an asset's cached previews is derivable from `assetID` alone
/// (`PreviewCache` keys every level beneath one per-asset directory), so no
/// separate field is needed.
public struct RelocationManifestEntry: Equatable, Sendable {
    public var assetID: AssetID
    public var originalFrom: URL
    public var originalTo: URL
    public var sidecarFrom: URL?
    public var sidecarTo: URL?
    public var assetSnapshot: Asset?

    public init(
        assetID: AssetID,
        originalFrom: URL,
        originalTo: URL,
        sidecarFrom: URL?,
        sidecarTo: URL?,
        assetSnapshot: Asset? = nil
    ) {
        self.assetID = assetID
        self.originalFrom = originalFrom
        self.originalTo = originalTo
        self.sidecarFrom = sidecarFrom
        self.sidecarTo = sidecarTo
        self.assetSnapshot = assetSnapshot
    }
}
