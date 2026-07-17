import TeststripCore

/// In-memory tracking for the current cull run, behind the completion
/// summary's skipped/neverViewed counts: which frames the run's navigation
/// actually landed on (`viewedAssetIDs`, recorded at AppModel's single
/// selection choke point), and which were Space-skipped while still
/// undecided (`skippedAssetIDs`, recorded only by the `.nextPhoto` arm).
/// Reset when the cull source/batch changes — a new run — but NOT on `S`
/// scope cycling: changing the lens mid-run doesn't unsee anything.
/// In-memory only; persistence for exact resume is out of scope (SP-D).
struct CullRunTracker: Equatable {
    private(set) var viewedAssetIDs: Set<AssetID> = []
    private(set) var skippedAssetIDs: Set<AssetID> = []

    mutating func recordViewed(_ assetID: AssetID) {
        viewedAssetIDs.insert(assetID)
    }

    /// The skipped set is RAW: a skipped-then-decided asset stays recorded
    /// here and is subtracted at presentation time (skipped ∖ decided in
    /// `CullCompletionPresentation.summary`), so a late decision never needs
    /// a write-back into the tracker.
    mutating func recordSkipped(_ assetID: AssetID) {
        skippedAssetIDs.insert(assetID)
    }

    mutating func reset() {
        viewedAssetIDs = []
        skippedAssetIDs = []
    }
}
