import Testing
@testable import TeststripApp

/// SheetScaffold is the one template for every sheet/dialog, per spec §2c
/// (docs/superpowers/specs/2026-07-11-trash-and-ux-coherence-design.md).
struct SheetScaffoldPresentationTests {

    @Test
    func rejectsGenericPrimaryLabels() {
        #expect(!SheetScaffoldPresentation.isValidPrimaryLabel("OK"))
        #expect(!SheetScaffoldPresentation.isValidPrimaryLabel("Confirm"))
    }

    @Test
    func acceptsVerbObjectPrimaryLabels() {
        #expect(SheetScaffoldPresentation.isValidPrimaryLabel("Import 240 Photos"))
        #expect(SheetScaffoldPresentation.isValidPrimaryLabel("Move 71 to Trash"))
        #expect(SheetScaffoldPresentation.isValidPrimaryLabel("Create Person"))
    }

    @Test
    func optionsStartCollapsed() {
        #expect(SheetScaffoldPresentation.optionsStartExpanded == false)
    }
}
