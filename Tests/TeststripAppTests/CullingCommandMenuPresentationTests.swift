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
            CullingCommandMenuItem(title: "Accept Stack Selection", shortcut: .acceptStackSelection, key: .returnKey)
        ])
    }
}
