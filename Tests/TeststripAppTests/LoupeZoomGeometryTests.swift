import XCTest
@testable import TeststripApp

final class LoupeZoomGeometryTests: XCTestCase {
    private func assertEqual(
        _ actual: CGSize,
        _ expected: CGSize,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.width, expected.width, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, accuracy: 0.0001, file: file, line: line)
    }

    private func makeGeometry(
        imagePixelSize: CGSize = CGSize(width: 4000, height: 2000),
        viewportSize: CGSize = CGSize(width: 1000, height: 800),
        displayScale: CGFloat = 1
    ) -> LoupeZoomGeometry {
        LoupeZoomGeometry(
            imagePixelSize: imagePixelSize,
            viewportSize: viewportSize,
            displayScale: displayScale
        )
    }

    func testActualSizeDisplaySizeMapsOneImagePixelToOneScreenPixel() {
        XCTAssertEqual(
            makeGeometry(displayScale: 1).actualSizeDisplaySize,
            CGSize(width: 4000, height: 2000)
        )
        XCTAssertEqual(
            makeGeometry(displayScale: 2).actualSizeDisplaySize,
            CGSize(width: 2000, height: 1000)
        )
    }

    func testFittedDisplaySizeAspectFitsWithinViewport() {
        XCTAssertEqual(makeGeometry().fittedDisplaySize, CGSize(width: 1000, height: 500))
        XCTAssertEqual(
            makeGeometry(imagePixelSize: CGSize(width: 500, height: 400)).fittedDisplaySize,
            CGSize(width: 1000, height: 800)
        )
    }

    func testOffsetForCenterFocusIsZero() {
        XCTAssertEqual(makeGeometry().offset(for: .center), .zero)
    }

    func testOffsetClampsSoImageEdgesNeverEnterViewport() {
        let geometry = makeGeometry()

        // Focus (1, 1) clamps to (0.875, 0.8): the viewport half-extents are
        // 500/4000 and 400/2000 of the image, so the image's bottom-right
        // corner lands exactly on the viewport's bottom-right corner.
        assertEqual(geometry.offset(for: LoupeZoomFocus(x: 1, y: 1)), CGSize(width: -1500, height: -600))
        assertEqual(geometry.offset(for: LoupeZoomFocus(x: 0, y: 0)), CGSize(width: 1500, height: 600))
    }

    func testOffsetCentersAxesWhereImageFitsInsideViewport() {
        let geometry = makeGeometry(imagePixelSize: CGSize(width: 800, height: 600))

        XCTAssertEqual(geometry.offset(for: LoupeZoomFocus(x: 0, y: 1)), .zero)
    }

    func testOffsetAccountsForDisplayScale() {
        let geometry = makeGeometry(displayScale: 2)

        // At 2x the image draws at 2000x1000 points, so the pannable range
        // halves: focus 1 clamps to (1 - 500/2000/2, 1 - 400/1000/2).
        assertEqual(geometry.offset(for: LoupeZoomFocus(x: 1, y: 1)), CGSize(width: -500, height: -100))
    }

    func testFocusAtViewportPointMapsThroughFittedImageRect() {
        let geometry = makeGeometry()

        // Fitted image is 1000x500, centered with a 150pt band above/below.
        XCTAssertEqual(
            geometry.focus(atFittedViewportPoint: CGPoint(x: 250, y: 275)),
            LoupeZoomFocus(x: 0.25, y: 0.25)
        )
        XCTAssertEqual(
            geometry.focus(atFittedViewportPoint: CGPoint(x: 500, y: 400)),
            .center
        )
    }

    func testFocusAtViewportPointClampsOutsideFittedImage() {
        let geometry = makeGeometry()

        XCTAssertEqual(
            geometry.focus(atFittedViewportPoint: CGPoint(x: -10, y: 100)),
            LoupeZoomFocus(x: 0, y: 0)
        )
        XCTAssertEqual(
            geometry.focus(atFittedViewportPoint: CGPoint(x: 1200, y: 700)),
            LoupeZoomFocus(x: 1, y: 1)
        )
    }

    func testPanMovesFocusAgainstDragDirection() {
        let geometry = makeGeometry()

        // Dragging the image left/down by (-400, 100) reveals content to the
        // right/above: focus moves by (+400/4000, -100/2000).
        XCTAssertEqual(
            geometry.focus(pannedBy: CGSize(width: -400, height: 100), from: .center),
            LoupeZoomFocus(x: 0.6, y: 0.45)
        )
    }

    func testPanClampsFocusAtImageEdges() {
        let geometry = makeGeometry()

        XCTAssertEqual(
            geometry.focus(pannedBy: CGSize(width: -10_000, height: -10_000), from: .center),
            LoupeZoomFocus(x: 0.875, y: 0.8)
        )
        XCTAssertEqual(
            geometry.focus(pannedBy: CGSize(width: 10_000, height: 10_000), from: .center),
            LoupeZoomFocus(x: 0.125, y: 0.2)
        )
    }

    func testDegenerateSizesFallBackToCenteredFit() {
        let geometry = makeGeometry(imagePixelSize: .zero, displayScale: 0)

        XCTAssertEqual(geometry.actualSizeDisplaySize, .zero)
        XCTAssertEqual(geometry.fittedDisplaySize, .zero)
        XCTAssertEqual(geometry.offset(for: LoupeZoomFocus(x: 1, y: 0)), .zero)
        XCTAssertEqual(geometry.focus(atFittedViewportPoint: CGPoint(x: 10, y: 10)), .center)
        XCTAssertEqual(
            geometry.focus(pannedBy: CGSize(width: 50, height: 50), from: LoupeZoomFocus(x: 1, y: 1)),
            .center
        )
    }
}
