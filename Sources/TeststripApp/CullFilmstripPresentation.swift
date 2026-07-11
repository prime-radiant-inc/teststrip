import TeststripCore

/// A stack-aware filmstrip: frames grouped by the same auto-grouped stacks
/// that feed `CullSidebarView`, with a divider exactly between adjacent
/// stacks (never at the ends, never within a stack).
struct CullFilmstripPresentation: Equatable {
    enum Item: Equatable {
        case frame(AssetID)
        case stackDivider
    }

    var items: [Item]
    var positionText: String

    init(assets: [Asset], stacks: [AssetStack], selectedAssetID: AssetID?) {
        var items: [Item] = []
        for (index, stack) in stacks.enumerated() {
            if index > 0 {
                items.append(.stackDivider)
            }
            items.append(contentsOf: stack.assetIDs.map(Item.frame))
        }
        self.items = items
        self.positionText = Self.positionText(assets: assets, stacks: stacks, selectedAssetID: selectedAssetID)
    }

    private static func positionText(assets: [Asset], stacks: [AssetStack], selectedAssetID: AssetID?) -> String {
        let totalFrames = assets.count
        guard totalFrames > 0,
              let selectedAssetID,
              let frameIndex = assets.firstIndex(where: { $0.id == selectedAssetID }),
              let stackIndex = stacks.firstIndex(where: { $0.assetIDs.contains(selectedAssetID) }) else {
            return "\(totalFrames) \(totalFrames == 1 ? "frame" : "frames")"
        }
        return "frame \(frameIndex + 1) / \(totalFrames) · stack \(stackIndex + 1) / \(stacks.count)"
    }
}

/// A transient toast summarizing the last culling decision, driven by the
/// same `CullingMetadataDecisionFeedback` that backs `CullingDecisionFeedbackPresentation`.
/// Auto-fades on a timer in the view; this struct only computes the text.
struct CullDecisionToastPresentation: Equatable {
    var text: String

    init(feedback: CullingMetadataDecisionFeedback) {
        if feedback.isInformational {
            // No metadata changed, so no ✓/✕/★ symbol and no "⌘Z undoes" —
            // there's nothing to undo (item 4).
            text = feedback.decisionText
            return
        }
        let symbol = Self.symbol(for: feedback.decisionText)
        let lowercasedDecision = feedback.decisionText.prefix(1).lowercased() + feedback.decisionText.dropFirst()
        text = "\(symbol) \(feedback.filename) \(lowercasedDecision) — ⌘Z undoes"
    }

    private static func symbol(for decisionText: String) -> String {
        if decisionText.hasPrefix("Rejected") { return "✕" }
        if decisionText.hasPrefix("Picked") { return "✓" }
        if decisionText.hasPrefix("Rated") { return "★" }
        if decisionText.hasPrefix("Cleared") { return "○" }
        return "●"
    }
}
