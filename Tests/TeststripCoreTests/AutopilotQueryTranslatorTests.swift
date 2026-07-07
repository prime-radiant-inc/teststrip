import XCTest
@testable import TeststripCore

final class AutopilotQueryTranslatorTests: XCTestCase {
    func testLocalHTTPTranslatorExtractsCanonicalQueryFromChatResponse() throws {
        let json = """
        {"choices":[{"message":{"content":"{\\"query\\":\\"rating:4 keyword:dog\\"}"}}]}
        """
        let transport = StubTransport(response: LocalHTTPModelHTTPResponse(statusCode: 200, data: Data(json.utf8)))
        let translator = LocalHTTPQueryTranslator(
            configuration: AutopilotQueryTranslatorConfiguration(
                endpoint: URL(string: "http://127.0.0.1:1234/v1/chat/completions")!,
                model: "qwen", timeout: 5
            ),
            transport: transport
        )

        let query = try translator.translate("my four star dog photos")

        // The translator emits the deterministic parser's canonical field
        // syntax, so App-side parsing yields the same removable chips.
        XCTAssertEqual(query, "rating:4 keyword:dog")
    }

    private struct StubTransport: LocalHTTPModelTransport {
        var response: LocalHTTPModelHTTPResponse
        func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse { response }
    }
}
