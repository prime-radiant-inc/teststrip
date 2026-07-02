import AppKit
import XCTest
@testable import TeststripApp

final class PreviewImageLoaderTests: XCTestCase {
    func testLoadDataReadsPreviewBytes() async throws {
        let directory = try makeTemporaryDirectory(named: "preview-loader")
        let previewURL = directory.appendingPathComponent("preview.jpg")
        let expected = Data([0x01, 0x02, 0x03])
        try expected.write(to: previewURL)

        let loaded = await PreviewImageDataLoader.loadData(from: previewURL)

        XCTAssertEqual(loaded, expected)
    }

    func testLoadDataReturnsNilForMissingPreview() async throws {
        let directory = try makeTemporaryDirectory(named: "preview-loader-missing")
        let previewURL = directory.appendingPathComponent("missing.jpg")

        let loaded = await PreviewImageDataLoader.loadData(from: previewURL)

        XCTAssertNil(loaded)
    }

    func testLoadImageDecodesPreviewImage() async throws {
        let directory = try makeTemporaryDirectory(named: "preview-image-loader")
        let previewURL = directory.appendingPathComponent("preview.png")
        try writeSolidPNG(to: previewURL, width: 4, height: 3)

        let image = await PreviewImageDataLoader.loadImage(from: previewURL)

        XCTAssertEqual(image?.size.width, 4)
        XCTAssertEqual(image?.size.height, 3)
    }

    func testLoadImageReturnsNilForInvalidPreviewBytes() async throws {
        let directory = try makeTemporaryDirectory(named: "preview-image-loader-invalid")
        let previewURL = directory.appendingPathComponent("preview.jpg")
        try Data("not an image".utf8).write(to: previewURL)

        let image = await PreviewImageDataLoader.loadImage(from: previewURL)

        XCTAssertNil(image)
    }

    private func makeTemporaryDirectory(named name: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writeSolidPNG(to url: URL, width: Int, height: Int) throws {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw NSError(domain: "PreviewImageLoaderTests", code: 1)
        }
        context.setFillColor(NSColor.systemBlue.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cgImage = context.makeImage() else {
            throw NSError(domain: "PreviewImageLoaderTests", code: 2)
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "PreviewImageLoaderTests", code: 3)
        }
        try data.write(to: url)
    }
}
