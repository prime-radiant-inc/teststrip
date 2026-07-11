import Foundation
import TeststripCore

/// The Library grid cell's right-click context menu (persona-2 item 5): star
/// ratings, Pick/Reject flags, and color labels previously only reachable via
/// keyboard shortcuts (0-5/p/x/u) or the hidden Inspector (⌘I). This mirrors
/// the batch-aware selection resolution `cullSelection(anchoredOn:)` already
/// uses for "Cull These": if the right-clicked cell is part of the current
/// batch selection, the action applies to the whole batch; otherwise it
/// applies to just the clicked cell (which becomes the new selection).
public enum AssetGridCellContextMenuPresentation {
    /// Which assets a menu action fired from `rightClicked` should apply to,
    /// given the grid's current batch selection.
    public static func targetAssetIDs(
        rightClicked assetID: AssetID,
        batchSelectedAssetIDs: Set<AssetID>
    ) -> Set<AssetID> {
        batchSelectedAssetIDs.contains(assetID) ? batchSelectedAssetIDs : [assetID]
    }

    /// The Rate submenu's items: "Rate 1"…"Rate 5" plus "Clear Rating".
    public static let ratingMenuTitles: [String] = (1...5).map { "Rate \($0)" } + ["Clear Rating"]

    /// The Flag submenu's items.
    public static let flagMenuTitles: [String] = ["Pick", "Reject", "Unflag"]

    /// The Label submenu's items: one per `ColorLabel` plus "Clear Label".
    public static let labelMenuTitles: [String] = ColorLabel.allCases.map(\.rawValue.capitalized) + ["Clear Label"]
}
