import SwiftUI

/// Single source of truth for SF Symbol names used across Teststrip's UI, per
/// the icon inventory in spec §2d
/// (docs/superpowers/specs/2026-07-11-trash-and-ux-coherence-design.md). Each
/// case maps a concept to exactly one symbol so that a symbol never means two
/// different things on screen (enforced by `DesignGlyphTests`).
public enum DesignGlyph: String, CaseIterable {
    case pick = "flag.fill"
    case reject = "xmark"
    case rating = "star.fill"
    case colorLabel = "circle.fill"
    case stack = "rectangle.stack"
    case ai = "sparkles"
    case importPhotos = "square.and.arrow.down"
    case exportPhotos = "square.and.arrow.up"
    case trashRejects = "trash"
    case filterMenu = "line.3.horizontal.decrease"
    case sort = "arrow.up.arrow.down"
    case activityIdle = "bell"
    case searchSubmit = "magnifyingglass"

    // Availability family (externaldrive.* per spec §2d).
    case availabilityOnline = "externaldrive.fill.badge.checkmark"
    case availabilityOffline = "externaldrive.badge.xmark"
    case availabilityStale = "externaldrive.badge.exclamationmark"
    case availabilityReconnect = "externaldrive.badge.plus"

    public var symbolName: String { rawValue }

    public var image: Image { Image(systemName: symbolName) }
}
