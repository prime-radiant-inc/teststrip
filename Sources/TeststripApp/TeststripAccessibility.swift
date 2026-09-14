import Foundation

/// Accessible names and automation identifiers for the import sheet.
///
/// A live AX pass found the import selection sheet produced no reachable
/// window/sheet elements at all: its controls had no accessible labels or
/// identifiers, so assistive tech and automation had nothing to address. The
/// strings here are the single source of truth the view applies, so the sheet
/// (and its filter, count, and footer actions) can be named and driven.
enum ImportSheetAccessibility {
    static let sheetLabel = "Import Photos"
    static let sheetIdentifier = "importSelection.sheet"
    static let filterLabel = "Import selection filter"
    static let filterIdentifier = "importSelection.filter"
    static let countIdentifier = "importSelection.countSummary"
    static let gridLabel = "Photos to import"
    static let gridIdentifier = "importSelection.grid"
    static let selectAllIdentifier = "importSelection.selectAll"
    static let selectNoneIdentifier = "importSelection.selectNone"
    static let cancelIdentifier = "importSelection.cancel"
    static let importIdentifier = "importSelection.import"
    static let cellIdentifierPrefix = "importSelection.cell."

    /// The count summary ("3 of 5 selected") is a static Text; its content is
    /// the accessible value, so give it a stable name to address it by.
    static func countSummaryLabel(selectedCount: Int, totalCount: Int) -> String {
        "\(selectedCount) of \(totalCount) selected"
    }

    static func cellLabel(filename: String) -> String {
        filename
    }

    /// A thumbnail cell's selection/duplicate state, exposed as the
    /// accessible value so automation can tell a checked cell from an
    /// unchecked one and a duplicate from a new photo without reading pixels.
    static func cellValue(isSelected: Bool, isDuplicate: Bool) -> String {
        var segments = [isSelected ? "Selected" : "Not selected"]
        if isDuplicate {
            segments.append("Duplicate")
        }
        return segments.joined(separator: ", ")
    }

    static func cellIdentifier(filename: String) -> String {
        "\(cellIdentifierPrefix)\(filename)"
    }

    static func importButtonLabel(selectedCount: Int) -> String {
        "Import \(selectedCount) Photos"
    }
}

/// Accessible names for the Library grid's icon-only search/filter chrome.
///
/// An AX probe matched the "Clear filters" help text to an element described
/// only as "Close" (the raw `xmark.circle` symbol), and the thumbnail-size
/// control announced "square.grid.3x3" with its meaning living only in
/// AXHelp. Every icon-only control here gets a real name; the help text stays.
enum GridChromeAccessibility {
    static let thumbnailSizeLabel = "Thumbnail size"
    static let refreshSourceStatusLabel = "Refresh source status"
    static let retryMetadataSyncLabel = "Retry pending metadata sync"
    static let clearFiltersLabel = "Clear filters"
    static let smartCollectionNameLabel = "Smart Collection name"
    static let smartCollectionNameIdentifier = "smartCollection.name"
    static let smartCollectionRuleLabel = "Smart Collection rule"
    static let smartCollectionRuleIdentifier = "smartCollection.rule"

    /// Suggestion chips in the result header and active-filter chips share one
    /// verb + object vocabulary: "Add filter X" / "Remove filter X".
    static func filterChipAddLabel(for display: String) -> String {
        "Add filter \(display)"
    }

    static func filterChipRemoveLabel(for display: String) -> String {
        "Remove filter \(display)"
    }
}

/// Accessible naming for Teststrip's tentative, AI-derived state.
///
/// AGENTS.md: `origin=ai` is never a decision until confirmed. The ✨ marker
/// (DesignGlyph.ai) is the only visual cue for that tentative state, and an
/// `Image` alone announces its raw symbol name — so every unconfirmed AI
/// surface carries this explicit name instead.
enum AITentativeAccessibility {
    /// Spoken for the ✨ marker on an unconfirmed AI-suggested value.
    static let unconfirmedMarkerLabel = "AI-suggested, unconfirmed"

    /// The full accessible name for an unconfirmed AI value: the marker's
    /// tentative state plus the value itself.
    static func unconfirmedValueLabel(_ value: String) -> String {
        "\(value), \(unconfirmedMarkerLabel)"
    }
}
