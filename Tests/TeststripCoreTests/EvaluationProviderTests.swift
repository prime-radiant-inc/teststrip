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

    func testDefaultPromptListsVisualSimilarityAndFramingSignalKinds() {
        XCTAssertTrue(LocalHTTPModelProvider.defaultPrompt.contains("visualSimilarity"))
        XCTAssertTrue(LocalHTTPModelProvider.defaultPrompt.contains("framing"))
    }

    func testLocalHTTPProviderBuildsOpenAICompatibleRequest() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-http-request")
        let previewURL = directory.appendingPathComponent("frame.jpg")
        let previewData = Data("preview bytes".utf8)
        try previewData.write(to: previewURL)
        let provider = LocalHTTPModelProvider(
            endpoint: URL(string: "http://localhost:11434/v1/chat/completions")!,
            model: "llava",
            timeout: 12
        )

        let request = try provider.request(for: previewURL, prompt: "Describe culling signals")

        XCTAssertEqual(request.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 12)
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
        let imageURL = try XCTUnwrap(content.compactMap { $0["image_url"] as? [String: Any] }.first)
        let dataURL = try XCTUnwrap(imageURL["url"] as? String)
        XCTAssertTrue(dataURL.hasPrefix("data:image/jpeg;base64,"))
        XCTAssertEqual(Data(base64Encoded: String(dataURL.dropFirst("data:image/jpeg;base64,".count))), previewData)
    }

    func testLocalHTTPProviderEvaluatesOpenAICompatibleResponse() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-http-evaluate")
        let previewURL = directory.appendingPathComponent("frame.jpg")
        try Data("preview bytes".utf8).write(to: previewURL)
        let transport = RecordingLocalHTTPTransport(response: .success(LocalHTTPModelHTTPResponse(
            statusCode: 200,
            data: try chatCompletionData(content: """
            {"signals":[{"kind":"aesthetics","label":"keeper","confidence":0.74},{"kind":"framing","label":"tight crop","confidence":0.7},{"kind":"focus","score":0.91,"confidence":0.82},{"kind":"faceCount","count":2,"confidence":0.9}]}
            """)
        )))
        let provider = LocalHTTPModelProvider(
            endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
            model: "llava",
            transport: transport
        )
        let assetID = AssetID(rawValue: "asset-1")

        let signals = try provider.evaluate(assetID: assetID, previewURL: previewURL)

        XCTAssertEqual(signals, [
            EvaluationSignal(
                assetID: assetID,
                kind: .aesthetics,
                value: .label("keeper"),
                confidence: 0.74,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .framing,
                value: .label("tight crop"),
                confidence: 0.7,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .focus,
                value: .score(0.91),
                confidence: 0.82,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .faceCount,
                value: .count(2),
                confidence: 0.9,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            )
        ])
        let request = try XCTUnwrap(transport.requests().first)
        XCTAssertEqual(request.url?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertNotNil(request.httpBody)
    }

    func testLocalHTTPProviderReportsHTTPFailure() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-http-failure")
        let previewURL = directory.appendingPathComponent("frame.jpg")
        try Data("preview bytes".utf8).write(to: previewURL)
        let provider = LocalHTTPModelProvider(
            endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
            model: "llava",
            transport: RecordingLocalHTTPTransport(response: .success(LocalHTTPModelHTTPResponse(
                statusCode: 500,
                data: Data("server error".utf8)
            )))
        )

        XCTAssertThrowsError(try provider.evaluate(
            assetID: AssetID(rawValue: "asset-1"),
            previewURL: previewURL
        )) { error in
            XCTAssertTrue(error.localizedDescription.contains("HTTP model request failed"))
        }
    }

    func testLocalHTTPProviderRetriesTransientHTTPFailure() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-http-retry-status")
        let previewURL = directory.appendingPathComponent("frame.jpg")
        try Data("preview bytes".utf8).write(to: previewURL)
        let transport = RecordingLocalHTTPTransport(responses: [
            .success(LocalHTTPModelHTTPResponse(statusCode: 500, data: Data("server busy".utf8))),
            .success(LocalHTTPModelHTTPResponse(
                statusCode: 200,
                data: try chatCompletionData(content: """
                {"signals":[{"kind":"focus","score":0.88,"confidence":0.91}]}
                """)
            ))
        ])
        let provider = LocalHTTPModelProvider(
            endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
            model: "llava",
            transport: transport
        )
        let assetID = AssetID(rawValue: "asset-1")

        let signals = try provider.evaluate(assetID: assetID, previewURL: previewURL)

        XCTAssertEqual(transport.requests().count, 2)
        XCTAssertEqual(signals, [
            EvaluationSignal(
                assetID: assetID,
                kind: .focus,
                value: .score(0.88),
                confidence: 0.91,
                provenance: ProviderProvenance(provider: "local-http-model", model: "llava", version: "1", settingsHash: "default")
            )
        ])
    }

    func testLocalHTTPProviderRetriesTransportFailure() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-http-retry-transport")
        let previewURL = directory.appendingPathComponent("frame.jpg")
        try Data("preview bytes".utf8).write(to: previewURL)
        let transport = RecordingLocalHTTPTransport(responses: [
            .failure(TeststripError.io("connection reset")),
            .success(LocalHTTPModelHTTPResponse(
                statusCode: 200,
                data: try chatCompletionData(content: """
                {"signals":[{"kind":"aesthetics","label":"keeper","confidence":0.73}]}
                """)
            ))
        ])
        let provider = LocalHTTPModelProvider(
            endpoint: URL(string: "http://localhost:1234/v1/chat/completions")!,
            model: "llava",
            transport: transport
        )

        let signals = try provider.evaluate(assetID: AssetID(rawValue: "asset-1"), previewURL: previewURL)

        XCTAssertEqual(transport.requests().count, 2)
        XCTAssertEqual(signals.map(\.kind), [.aesthetics])
    }

    func testLocalImageMetricsProviderEmitsExposureColorFocusAndMotionBlurSignalsFromPreview() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-image-metrics")
        let previewURL = directory.appendingPathComponent("preview.png")
        try writeSolidPNG(to: previewURL, width: 1200, height: 800, red: 0.2, green: 0.4, blue: 0.8)
        let provider = LocalImageMetricsEvaluationProvider()
        let assetID = AssetID(rawValue: "asset-1")

        let signals = try provider.evaluate(assetID: assetID, previewURL: previewURL)

        XCTAssertEqual(signals.map(\.kind), [.exposure, .colorPalette, .focus, .motionBlur, .framing, .aesthetics])
        XCTAssertEqual(signals.map(\.assetID), [assetID, assetID, assetID, assetID, assetID, assetID])
        XCTAssertEqual(signals.map(\.provenance.provider), ["local-image-metrics", "local-image-metrics", "local-image-metrics", "local-image-metrics", "local-image-metrics", "local-image-metrics"])

        guard case .score(let exposure)? = signals.first?.value else {
            return XCTFail("expected exposure score")
        }

        guard case .vector(let color)? = signals.first(where: { $0.kind == .colorPalette })?.value else {
            return XCTFail("expected color vector")
        }
        XCTAssertEqual(color.count, 3)
        XCTAssertTrue(color.allSatisfy { (0.0...1.0).contains($0) })
        XCTAssertLessThan(color[0], color[1])
        XCTAssertLessThan(color[1], color[2])
        XCTAssertEqual(exposure, 0.2126 * color[0] + 0.7152 * color[1] + 0.0722 * color[2], accuracy: 0.0001)

        guard case .score(let focus)? = signals.first(where: { $0.kind == .focus })?.value else {
            return XCTFail("expected focus score")
        }
        XCTAssertEqual(focus, 0, accuracy: 0.0001)

        guard case .score(let blur)? = signals.first(where: { $0.kind == .motionBlur })?.value else {
            return XCTFail("expected motion blur score")
        }
        XCTAssertGreaterThan(blur, 0.9)

        XCTAssertNotNil(signals.first { $0.kind == .framing })
        XCTAssertNotNil(signals.first { $0.kind == .aesthetics })
    }

    func testLocalImageMetricsFocusScoreReflectsPreviewEdgeDetail() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-image-focus")
        let flatURL = directory.appendingPathComponent("flat.png")
        let detailedURL = directory.appendingPathComponent("detailed.png")
        try writeSolidPNG(to: flatURL, width: 64, height: 64, red: 0.5, green: 0.5, blue: 0.5)
        try writeCheckerboardPNG(to: detailedURL, width: 64, height: 64, cellSize: 4)
        let provider = LocalImageMetricsEvaluationProvider()

        let flatFocus = try focusScore(from: provider.evaluate(assetID: AssetID(rawValue: "flat"), previewURL: flatURL))
        let detailedFocus = try focusScore(from: provider.evaluate(assetID: AssetID(rawValue: "detailed"), previewURL: detailedURL))

        XCTAssertLessThan(flatFocus, 0.01)
        XCTAssertGreaterThan(detailedFocus, flatFocus + 0.2)
    }

    func testLocalImageMetricsMotionBlurScoreFallsAsEdgeDetailRises() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-image-motion-blur")
        let flatURL = directory.appendingPathComponent("flat.png")
        let detailedURL = directory.appendingPathComponent("detailed.png")
        try writeSolidPNG(to: flatURL, width: 64, height: 64, red: 0.5, green: 0.5, blue: 0.5)
        try writeCheckerboardPNG(to: detailedURL, width: 64, height: 64, cellSize: 4)
        let provider = LocalImageMetricsEvaluationProvider()

        let flatBlur = try motionBlurScore(from: provider.evaluate(assetID: AssetID(rawValue: "flat"), previewURL: flatURL))
        let detailedBlur = try motionBlurScore(from: provider.evaluate(assetID: AssetID(rawValue: "detailed"), previewURL: detailedURL))

        XCTAssertGreaterThan(flatBlur, 0.9)
        XCTAssertLessThan(detailedBlur, flatBlur - 0.2)
    }

    func testLocalImageMetricsAestheticScoreRewardsDetailColorAndBalancedExposure() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "local-image-aesthetic")
        let flatURL = directory.appendingPathComponent("flat.png")
        let detailedURL = directory.appendingPathComponent("detailed.png")
        try writeSolidPNG(to: flatURL, width: 64, height: 64, red: 0.5, green: 0.5, blue: 0.5)
        try writeThirdsSubjectPNG(to: detailedURL, width: 96, height: 96)
        let provider = LocalImageMetricsEvaluationProvider()

        let flatSignals = try provider.evaluate(assetID: AssetID(rawValue: "flat"), previewURL: flatURL)
        let detailedSignals = try provider.evaluate(assetID: AssetID(rawValue: "detailed"), previewURL: detailedURL)

        let flatAesthetic = try score(from: flatSignals, kind: .aesthetics)
        let detailedAesthetic = try score(from: detailedSignals, kind: .aesthetics)
        let detailedFraming = try score(from: detailedSignals, kind: .framing)

        XCTAssertGreaterThan(detailedAesthetic, flatAesthetic + 0.1)
        XCTAssertGreaterThan(detailedFraming, 0.6)
    }

    func testAppleVisionProviderMapsAnalysisToSignals() throws {
        let provider = AppleVisionEvaluationProvider(analyzer: FakeAppleVisionAnalyzer(analysis: AppleVisionAnalysis(
            faceCount: 2,
            faceQualityScores: [0.6, 0.9],
            recognizedText: ["Invoice 123", "Total 45"],
            classificationLabels: [AppleVisionLabel(identifier: "document", confidence: 0.82)],
            imageFeaturePrintVector: [0.1, 0.2, 0.3]
        )))
        let assetID = AssetID(rawValue: "asset-1")

        let signals = try provider.evaluate(assetID: assetID, previewURL: URL(fileURLWithPath: "/tmp/preview.jpg"))

        XCTAssertEqual(signals, [
            EvaluationSignal(
                assetID: assetID,
                kind: .faceCount,
                value: .count(2),
                confidence: 0.9,
                provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .faceQuality,
                value: .score(0.75),
                confidence: 0.9,
                provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .ocrText,
                value: .text("Invoice 123\nTotal 45"),
                confidence: 1.0,
                provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .object,
                value: .label("document"),
                confidence: 0.82,
                provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
            ),
            EvaluationSignal(
                assetID: assetID,
                kind: .visualSimilarity,
                value: .vector([0.1, 0.2, 0.3]),
                confidence: 1.0,
                provenance: ProviderProvenance(provider: "apple-vision", model: "Vision", version: "1", settingsHash: "default")
            )
        ])
    }

    func testAppleVisionAnalyzerProducesImageFeaturePrintVector() throws {
        let directory = try TestDirectories.makeTemporaryDirectory(named: "apple-vision-feature-print")
        let previewURL = directory.appendingPathComponent("preview.jpg")
        try TestDirectories.writeTestJPEG(to: previewURL, width: 64, height: 64)

        let analysis = try AppleVisionAnalyzer().analyze(previewURL: previewURL)

        XCTAssertFalse(analysis.imageFeaturePrintVector.isEmpty)
    }

    func testEvaluationValuesRoundTripThroughJSON() throws {
        let values: [EvaluationValue] = [
            .score(0.92),
            .label("keeper"),
            .text("sharp foreground"),
            .count(3),
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

private struct FakeAppleVisionAnalyzer: AppleVisionAnalyzing {
    var analysis: AppleVisionAnalysis

    func analyze(previewURL: URL) throws -> AppleVisionAnalysis {
        analysis
    }
}

private final class RecordingLocalHTTPTransport: LocalHTTPModelTransport, @unchecked Sendable {
    private let responses: [Result<LocalHTTPModelHTTPResponse, Error>]
    private let lock = NSLock()
    private var recordedRequests: [URLRequest] = []

    init(response: Result<LocalHTTPModelHTTPResponse, Error>) {
        self.responses = [response]
    }

    init(responses: [Result<LocalHTTPModelHTTPResponse, Error>]) {
        precondition(!responses.isEmpty)
        self.responses = responses
    }

    func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse {
        lock.lock()
        recordedRequests.append(request)
        let response = responses[min(recordedRequests.count - 1, responses.count - 1)]
        lock.unlock()
        return try response.get()
    }

    func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }
}

private func chatCompletionData(content: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "choices": [
            [
                "message": [
                    "content": content
                ]
            ]
        ]
    ])
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

private func writeCheckerboardPNG(to url: URL, width: Int, height: Int, cellSize: Int) throws {
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
    for y in stride(from: 0, to: height, by: cellSize) {
        for x in stride(from: 0, to: width, by: cellSize) {
            let isLight = ((x / cellSize) + (y / cellSize)).isMultiple(of: 2)
            context.setFillColor(CGColor(gray: isLight ? 1.0 : 0.0, alpha: 1.0))
            context.fill(CGRect(x: x, y: y, width: cellSize, height: cellSize))
        }
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TeststripError.io("could not create test png")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TeststripError.io("could not write test png")
    }
}

private func writeThirdsSubjectPNG(to url: URL, width: Int, height: Int) throws {
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
    context.setFillColor(CGColor(red: 0.18, green: 0.28, blue: 0.55, alpha: 1.0))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(red: 0.92, green: 0.72, blue: 0.24, alpha: 1.0))
    context.fill(CGRect(x: width / 3 - 10, y: height / 3 - 10, width: 20, height: 20))
    for offset in stride(from: 0, to: width, by: 6) {
        context.setStrokeColor(CGColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1.0))
        context.move(to: CGPoint(x: offset, y: height))
        context.addLine(to: CGPoint(x: width, y: height - offset))
        context.strokePath()
    }
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw TeststripError.io("could not create test png")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw TeststripError.io("could not write test png")
    }
}

private func focusScore(from signals: [EvaluationSignal]) throws -> Double {
    let signal = try XCTUnwrap(signals.first { $0.kind == .focus })
    guard case .score(let score) = signal.value else {
        throw TeststripError.invalidState("expected focus score")
    }
    return score
}

private func motionBlurScore(from signals: [EvaluationSignal]) throws -> Double {
    let signal = try XCTUnwrap(signals.first { $0.kind == .motionBlur })
    guard case .score(let score) = signal.value else {
        throw TeststripError.invalidState("expected motion blur score")
    }
    return score
}

private func score(from signals: [EvaluationSignal], kind: EvaluationKind) throws -> Double {
    let signal = try XCTUnwrap(signals.first { $0.kind == kind })
    guard case .score(let score) = signal.value else {
        throw TeststripError.invalidState("expected \(kind.rawValue) score")
    }
    return score
}
