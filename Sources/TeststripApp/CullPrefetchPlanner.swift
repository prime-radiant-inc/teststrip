import TeststripCore

// SP-C: the warm set for blaze-through culling. Pure — AppModel's driver
// turns these into gated queue requests. Order is priority order: the
// staged burst radiating outward (forward first, since culling moves
// forward), then the next stacks' landing frames so → lands warm, then one
// landing back so a single ← does too.
enum CullPrefetchPlanner {
    static func warmAssetIDs(
        stops: [AssetStack],
        stagedAssetID: AssetID,
        nextStackCount: Int = 3,
        landingAssetID: (AssetStack) -> AssetID?
    ) -> [AssetID] {
        guard let stopIndex = stops.firstIndex(where: { $0.assetIDs.contains(stagedAssetID) }) else {
            return []
        }
        var ordered: [AssetID] = [stagedAssetID]
        let frames = stops[stopIndex].assetIDs
        if let frameIndex = frames.firstIndex(of: stagedAssetID) {
            ordered.append(contentsOf: frames[(frameIndex + 1)...])
            ordered.append(contentsOf: frames[..<frameIndex].reversed())
        }
        if nextStackCount > 0 {
            for nextIndex in (stopIndex + 1)...(stopIndex + nextStackCount) where stops.indices.contains(nextIndex) {
                if let landing = landingAssetID(stops[nextIndex]) {
                    ordered.append(landing)
                }
            }
        }
        if stops.indices.contains(stopIndex - 1), let landing = landingAssetID(stops[stopIndex - 1]) {
            ordered.append(landing)
        }
        var seen = Set<AssetID>()
        return ordered.filter { seen.insert($0).inserted }
    }
}
