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

    func testImagePixelSizePrefersAssetTechnicalDimensions() {
        XCTAssertEqual(
            LoupeZoomGeometry.imagePixelSize(
                technicalPixelWidth: 6000,
                technicalPixelHeight: 4000,
                fallback: CGSize(width: 3200, height: 2133)
            ),
            CGSize(width: 6000, height: 4000)
        )
    }

    func testImagePixelSizeFallsBackToLoadedImagePixelsWhenDimensionsUnknownOrInvalid() {
        XCTAssertEqual(
            LoupeZoomGeometry.imagePixelSize(
                technicalPixelWidth: nil,
                technicalPixelHeight: nil,
                fallback: CGSize(width: 3200, height: 2133)
            ),
            CGSize(width: 3200, height: 2133)
        )
        XCTAssertEqual(
            LoupeZoomGeometry.imagePixelSize(
                technicalPixelWidth: 0,
                technicalPixelHeight: 4000,
                fallback: CGSize(width: 3200, height: 2133)
            ),
            CGSize(width: 3200, height: 2133)
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

    func testMaxScaleIsRatioOfActualToFitted() {
        // 4000x2000 image in 1000x800 viewport at displayScale 1:
        // fitted = min(1000/4000, 800/2000) * 4000x2000 = 1000x500
        // actual = 4000x2000
        // maxScale = 4000/1000 = 4.0
        let g = makeGeometry(displayScale: 1)
        XCTAssertEqual(g.maxScale, 4.0, accuracy: 0.001)
    }

    func testDisplaySizeAtScale1IsFitted() {
        let g = makeGeometry(displayScale: 1)
        assertEqual(g.displaySize(for: 1.0), g.fittedDisplaySize)
    }

    func testDisplaySizeAtMaxScaleIsActualSize() {
        let g = makeGeometry(displayScale: 1)
        assertEqual(g.displaySize(for: g.maxScale), g.actualSizeDisplaySize)
    }

    func testDisplaySizeAtIntermediateScale() {
        // scale 2.0 on 4000x2000 in 1000x800 at ds=1:
        // fitted = 1000x500, so displaySize(2.0) = 2000x1000
        let g = makeGeometry(displayScale: 1)
        assertEqual(g.displaySize(for: 2.0), CGSize(width: 2000, height: 1000))
    }

    func testOffsetScalesWithScale() {
        // At scale 1.0 (fitted), offset should be zero (image fills viewport)
        // At scale 2.0, focus center → offset 0 (centered)
        // At scale 2.0, displaySize = 2000x1000 in viewport 1000x800
        // focus (1,1) clamped: x: halfViewport=1000/2000/2=0.25 → clamp(1,0.25,0.75)=0.75
        //                     y: halfViewport=800/1000/2=0.4 → clamp(1,0.4,0.6)=0.6
        // offset = (0.5-0.75)*2000, (0.5-0.6)*1000 = -500, -100
        let g = makeGeometry(displayScale: 1)
        let centerOffset = g.offset(for: .center, scale: 2.0)
        assertEqual(centerOffset, .zero)
        let cornerOffset = g.offset(for: LoupeZoomFocus(x: 1, y: 1), scale: 2.0)
        assertEqual(cornerOffset, CGSize(width: -500, height: -100))
    }

    func testFocusPannedByScalesWithDisplaySize() {
        // At scale 2.0, displaySize = 2000x1000; pan 50pt right and down
        // → focus delta = 50/2000 = 0.025 on x, 50/1000 = 0.05 on y
        // → 0.5-0.025=0.475 on x, 0.5-0.05=0.45 on y
        // clamped: x: clamp(0.475, 0.25, 0.75)=0.475; y: clamp(0.45, 0.4, 0.6)=0.45
        let g = makeGeometry(displayScale: 1)
        let result = g.focus(pannedBy: CGSize(width: 50, height: 50), from: .center, scale: 2.0)
        XCTAssertEqual(result.x, 0.475, accuracy: 0.001)
        XCTAssertEqual(result.y, 0.45, accuracy: 0.001)
    }

    func testClampedFocusScalesWithDisplaySize() {
        // At scale 2.0, displaySize = 2000x1000 in viewport 1000x800
        // x-axis: imageExtent(2000) > viewportExtent(1000) → halfViewport=0.25, clamp(0,0.25,0.75)=0.25
        // y-axis: imageExtent(1000) > viewportExtent(800) → halfViewport=0.4, clamp(0,0.4,0.6)=0.4
        let g = makeGeometry(displayScale: 1)
        let clamped = g.clampedFocus(LoupeZoomFocus(x: 0.0, y: 0.0), scale: 2.0)
        XCTAssertEqual(clamped.x, 0.25, accuracy: 0.001)
        XCTAssertEqual(clamped.y, 0.4, accuracy: 0.001)
    }
}
