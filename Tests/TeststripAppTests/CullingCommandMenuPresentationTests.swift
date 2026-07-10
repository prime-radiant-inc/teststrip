import XCTest
@testable import TeststripApp

final class CullingCommandMenuPresentationTests: XCTestCase {
    func testNavigationSectionExposesPhotoAndStackShortcuts() {
        let navigation = CullingCommandMenuPresentation.sections.first

        XCTAssertEqual(navigation?.items, [
            CullingCommandMenuItem(title: "Previous Photo", shortcut: .previousPhoto, key: .leftArrow),
            CullingCommandMenuItem(title: "Next Photo", shortcut: .nextPhoto, key: .rightArrow),
            CullingCommandMenuItem(title: "Previous Stack", shortcut: .previousStack, key: .upArrow),
            CullingCommandMenuItem(title: "Next Stack", shortcut: .nextStack, key: .downArrow),
            CullingCommandMenuItem(title: "Promote Frame & Reject Siblings", shortcut: .promoteAndRejectSiblings, key: .returnKey)
        ])
    }

    func testLoupeSectionExposesZoomToggleShortcut() {
        let loupe = CullingCommandMenuPresentation.sections.first { $0.title == "Loupe" }

        XCTAssertEqual(loupe?.items, [
            CullingCommandMenuItem(title: "Toggle 1:1 Zoom", shortcut: .toggleZoom, key: .character("z"))
        ])
    }
}
