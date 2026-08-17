import Foundation
import TeststripCore

/// In-memory tracking for the current cull run, behind the completion
/// summary's skipped/neverViewed counts: which frames the run's navigation
/// actually landed on (`viewedAssetIDs`, recorded at AppModel's single
/// selection choke point), and which were Space-skipped while still
/// undecided (`skippedAssetIDs`, recorded only by the `.nextPhoto` arm).
/// Reset when the cull source/batch changes — a new run — but NOT on `S`
/// scope cycling: changing the lens mid-run doesn't unsee anything.
/// Codable for JSON file persistence (never the catalog — the tracker is
/// UI state, not operational truth).
struct CullRunTracker: Codable, Equatable {
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

extension CullRunTracker {
    enum Persistence {
        static func save(_ tracker: CullRunTracker, to url: URL) throws {
            let data = try JSONEncoder().encode(tracker)
            try data.write(to: url, options: .atomic)
        }

        static func load(from url: URL) -> CullRunTracker? {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(CullRunTracker.self, from: data)
        }
    }
}
