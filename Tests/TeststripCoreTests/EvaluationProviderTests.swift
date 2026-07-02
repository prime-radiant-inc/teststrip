import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import TeststripCore

final class EvaluationProviderTests: XCTestCase {
    func testSignalStoresTypedValueAndProvenance() {
        let signal = EvaluationSignal(
            assetID: AssetID(rawValue: "asset-1"),
            kind: .focus,
            value: .score(0.92),
            confidence: 0.8,
            provenance: ProviderProvenance(provider: "AppleVision", model: "focus", version: "1", settingsHash: "default")
        )

        XCTAssertEqual(signal.kind, .focus)
        XCTAssertEqual(signal.value, .score(0.92))
        XCTAssertEqual(signal.provenance.provider, "AppleVision")
    }

    func testLocalHTTPProviderBuildsOpenAICompatibleRequest() throws {
        let provider = LocalHTTPModelProvider(
            endpoint: URL(string: "http://localhost:11434/v1/chat/completions")!,
            model: "llava"
        )

        let request = try provider.request(for: URL(fileURLWithPath: "/tmp/frame.jpg"), prompt: "Describe culling signals")

        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["model"] as? String, "llava")

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let firstMessage = try XCTUnwrap(messages.first)
        XCTAssertEqual(firstMessage["role"] as? String, "user")

        let content = try XCTUnwrap(firstMessage["content"] as? [[String: Any]])
        let textValues = content.compactMap { $0["text"] as? String }
        XCTAssertTrue(textValues.contains("Describe culling signals"))
        XCTAssertTrue(textValues.contains { $0.contains("/tmp/frame.jpg") })
    }

    func testLocalImageMetricsProviderEmitsExposureAndColorSignalsFromPreview() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-image-metrics")
        let previewURL = directory.appendingPathComponent("preview.png")
        try writeSolidPNG(to: previewURL, width: 1200, height: 800, red: 0.2, green: 0.4, blue: 0.8)
        let provider = LocalImageMetricsEvaluationProvider()
        let assetID = AssetID(rawValue: "asset-1")

        let signals = try provider.evaluate(assetID: assetID, previewURL: previewURL)

        XCTAssertEqual(signals.map(\.kind), [.exposure, .colorPalette])
        XCTAssertEqual(signals.map(\.assetID), [assetID, assetID])
        XCTAssertEqual(signals.map(\.provenance.provider), ["local-image-metrics", "local-image-metrics"])

        guard case .score(let exposure)? = signals.first?.value else {
            return XCTFail("expected exposure score")
        }

        guard case .vector(let color)? = signals.last?.value else {
            return XCTFail("expected color vector")
        }
        XCTAssertEqual(color.count, 3)
        XCTAssertTrue(color.allSatisfy { (0.0...1.0).contains($0) })
        XCTAssertLessThan(color[0], color[1])
        XCTAssertLessThan(color[1], color[2])
        XCTAssertEqual(exposure, 0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2], accuracy: 0.0001)
    }

    func testEvaluationValuesRoundTripThroughJSON() throws {
        let values: [EvaluationValue] = [
            .score(0.92),
            .label("keeper"),
            .text("sharp foreground"),
            .vector([0.1, 0.2, 0.3])
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(EvaluationValue.self, from: data)

            XCTAssertEqual(decoded, value)
        }
    }

    func testEvaluationSignalRoundTripsThroughJSON() throws {
        let signal = EvaluationSignal(
            assetID: AssetID(rawValue: "asset-1"),
            kind: .aesthetics,
            value: .label("portfolio"),
            confidence: 0.74,
            provenance: ProviderProvenance(provider: "LocalHTTP", model: "llava", version: "1", settingsHash: "default")
        )

        let data = try JSONEncoder().encode(signal)
        let decoded = try JSONDecoder().decode(EvaluationSignal.self, from: data)

        XCTAssertEqual(decoded, signal)
    }
}

private func writeSolidPNG(to url: URL, width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        throw TeststripError.io("could not create test bitmap context")
    }
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TeststripError.io("could not create test png")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TeststripError.io("could not write test png")
    }
}
