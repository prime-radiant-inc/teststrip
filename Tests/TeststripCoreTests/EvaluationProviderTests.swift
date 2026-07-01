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
