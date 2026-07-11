import Testing
@testable import TeststripApp

/// DesignGlyph is the single source of truth for SF Symbol names, per spec
/// §2d (docs/superpowers/specs/2026-07-11-trash-and-ux-coherence-design.md).
/// These tests assert the two invariants the spec calls out: one glyph per
/// concept (uniqueness) and every table concept represented (completeness).
struct DesignGlyphTests {

    @Test
    func everyCaseHasAUniqueSymbol() {
        let symbols = DesignGlyph.allCases.map(\.symbolName)
        let uniqueSymbols = Set(symbols)
        #expect(symbols.count == uniqueSymbols.count, "two DesignGlyph cases share an SF Symbol name: \(symbols)")
    }

    @Test
    func pickAndRejectAreDistinctFromEachOther() {
        #expect(DesignGlyph.pick.symbolName == "flag.fill")
        #expect(DesignGlyph.reject.symbolName == "xmark")
    }

    @Test
    func rating() {
        #expect(DesignGlyph.rating.symbolName == "star.fill")
    }

    @Test
    func colorLabel() {
        #expect(DesignGlyph.colorLabel.symbolName == "circle.fill")
    }

    @Test
    func stack() {
        #expect(DesignGlyph.stack.symbolName == "rectangle.stack")
    }

    @Test
    func aiIsSparkles() {
        #expect(DesignGlyph.ai.symbolName == "sparkles")
    }

    @Test
    func importAndExport() {
        #expect(DesignGlyph.importPhotos.symbolName == "square.and.arrow.down")
        #expect(DesignGlyph.exportPhotos.symbolName == "square.and.arrow.up")
    }

    @Test
    func trashRejects() {
        #expect(DesignGlyph.trashRejects.symbolName == "trash")
    }

    @Test
    func searchAndFilterMenuAreDistinct() {
        #expect(DesignGlyph.searchSubmit.symbolName == "magnifyingglass")
        #expect(DesignGlyph.filterMenu.symbolName == "line.3.horizontal.decrease")
        #expect(DesignGlyph.searchSubmit.symbolName != DesignGlyph.filterMenu.symbolName)
    }

    @Test
    func sort() {
        #expect(DesignGlyph.sort.symbolName == "arrow.up.arrow.down")
    }

    @Test
    func activityIdle() {
        #expect(DesignGlyph.activityIdle.symbolName == "bell")
    }

    @Test
    func availabilityFamilyIsAllExternalDrive() {
        let family: [DesignGlyph] = [.availabilityOnline, .availabilityOffline, .availabilityStale, .availabilityReconnect]
        for glyph in family {
            #expect(glyph.symbolName.hasPrefix("externaldrive"), "\(glyph) should be in the externaldrive.* family")
        }
    }

    /// Completeness: every concept row in spec §2d's inventory table must be
    /// represented by at least one DesignGlyph case. This enumerates the
    /// table rows directly rather than trusting the enum to be exhaustive.
    @Test
    func everySpecTableConceptIsRepresented() {
        let allSymbols = Set(DesignGlyph.allCases.map(\.symbolName))
        let specTableSymbols: [String] = [
            "flag.fill",              // Pick / keep
            "xmark",                  // Reject / cut
            "star.fill",              // Rating
            "circle.fill",            // Color label
            "rectangle.stack",        // Stack / set
            "sparkles",               // AI / provisional
            "square.and.arrow.down",  // Import
            "square.and.arrow.up",    // Export
            "trash",                  // Trash rejects
            "bell",                   // Activity/status (idle)
            "magnifyingglass",        // Search/query submit
            "line.3.horizontal.decrease", // Search/query filter menu
        ]
        for symbol in specTableSymbols {
            #expect(allSymbols.contains(symbol), "spec table concept with symbol \(symbol) missing from DesignGlyph")
        }
        // Availability family (externaldrive.* family row)
        #expect(allSymbols.contains { $0.hasPrefix("externaldrive") })
    }

    @Test
    func symbolNameMatchesRawValue() {
        for glyph in DesignGlyph.allCases {
            #expect(glyph.symbolName == glyph.rawValue)
        }
    }
}
