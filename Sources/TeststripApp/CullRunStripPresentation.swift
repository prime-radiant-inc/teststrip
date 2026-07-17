import TeststripCore

/// The culling loupe's run strip: one stop per auto-grouped stack from
/// `AppModel.allCullingStacks(for:)` (which partitions every asset in scope,
/// including singletons) — a pill for a multi-frame stack, a single frame
/// for a standalone. Replaces the old flat filmstrip, where a burst of a
/// dozen near-duplicates cost a dozen tiles; here it costs one stop.
struct CullRunStripPresentation {
    static let defaultVisibleLimit = 12

    struct Stop: Equatable, Identifiable {
        var id: AssetID
        var assetIDs: [AssetID]
        var label: String
        var isCurrent: Bool
        var isDone: Bool
        var sparkleCount: Int
        var isStandalone: Bool
        var leadAssetID: AssetID
    }

    /// Builds one stop per entry in `stacks` (already in capture/scope
    /// order), then windows the result so at most `visibleLimit` stops are
    /// returned, centered on the current stop. `windowStart` is that
    /// window's offset into the full (unwindowed) stop sequence.
    static func stops(
        assets: [Asset],
        stacks: [AssetStack],
        selectedAssetID: AssetID?,
        pendingSparkleAssetIDs: Set<AssetID>,
        visibleLimit: Int = defaultVisibleLimit
    ) -> (stops: [Stop], windowStart: Int) {
        let assetsByID = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
        let allStops: [Stop] = stacks.compactMap { stack in
            guard let leadAssetID = stack.assetIDs.first else { return nil }
            let stackAssets = stack.assetIDs.compactMap { assetsByID[$0] }
            guard !stackAssets.isEmpty else { return nil }
            let isCurrent = selectedAssetID.map { stack.assetIDs.contains($0) } ?? false
            let isDone = stackAssets.allSatisfy { $0.metadata.confirmedProjection.flag != nil }
            let sparkleCount = stack.assetIDs.filter { pendingSparkleAssetIDs.contains($0) }.count
            return Stop(
                id: leadAssetID,
                assetIDs: stack.assetIDs,
                label: CullStackLabelPresentation.label(for: stackAssets),
                isCurrent: isCurrent,
                isDone: isDone,
                sparkleCount: sparkleCount,
                isStandalone: stack.assetIDs.count <= 1,
                leadAssetID: leadAssetID
            )
        }

        let currentIndex = allStops.firstIndex(where: \.isCurrent) ?? 0
        let window = CullStripWindowing.centeredWindow(count: allStops.count, anchorIndex: currentIndex, limit: visibleLimit)
        return (Array(allStops[window]), window.lowerBound)
    }
}

/// Centers a `limit`-sized window around `anchorIndex` within a sequence of
/// `count` items, clamped to the sequence's bounds. Shared by the run strip's
/// stop windowing above and the A/B compare filmstrip's raw-asset windowing
/// (`LibraryGridView.windowedAssets`) — one algorithm, so the two can never
/// drift apart on the centering math.
enum CullStripWindowing {
    static func centeredWindow(count: Int, anchorIndex: Int, limit: Int) -> Range<Int> {
        let boundedLimit = max(1, limit)
        guard count > boundedLimit else { return 0..<count }
        let proposedStart = anchorIndex - boundedLimit / 2
        let start = min(max(proposedStart, 0), count - boundedLimit)
        return start..<(start + boundedLimit)
    }
}
