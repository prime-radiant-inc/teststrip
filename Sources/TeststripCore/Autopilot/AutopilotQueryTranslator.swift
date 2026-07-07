import Foundation

public struct AutopilotQueryTranslatorConfiguration: Equatable, Sendable {
    public var endpoint: URL
    public var model: String
    public var timeout: TimeInterval

    public init(endpoint: URL, model: String, timeout: TimeInterval) {
        self.endpoint = endpoint
        self.model = model
        self.timeout = timeout
    }
}

/// Translates a natural-language Ask into the deterministic library-search
/// field syntax. Implementations return a canonical query string (e.g.
/// `"rating:4 keyword:dog"`) that the App feeds to `LibrarySearchIntent.parse`,
/// so translated and hand-typed queries share ONE predicate/chip vocabulary.
public protocol AutopilotQueryTranslator: Sendable {
    func translate(_ naturalLanguage: String) throws -> String
}

/// Opt-in translator that POSTs the Ask to an OpenAI-compatible local endpoint
/// (LM Studio / Ollama-style), reusing the `LocalHTTPModelTransport` seam. It
/// introduces no build-time dependency and is only used when the App wires a
/// configured translator; with none, the deterministic parser is the sole path.
public struct LocalHTTPQueryTranslator: AutopilotQueryTranslator {
    public var configuration: AutopilotQueryTranslatorConfiguration
    private let transport: any LocalHTTPModelTransport

    public init(
        configuration: AutopilotQueryTranslatorConfiguration,
        transport: any LocalHTTPModelTransport = URLSessionLocalHTTPModelTransport()
    ) {
        self.configuration = configuration
        self.transport = transport
    }

    public func translate(_ naturalLanguage: String) throws -> String {
        let request = try Self.request(configuration: configuration, naturalLanguage: naturalLanguage)
        let response = try transport.response(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw TeststripError.io("query translation failed with status \(response.statusCode)")
        }
        let completion = try JSONDecoder().decode(ChatCompletionResponse.self, from: response.data)
        guard let content = completion.choices.first?.message.content else {
            throw TeststripError.invalidState("query translation response did not include message content")
        }
        let translated = try JSONDecoder().decode(TranslatedQuery.self, from: Self.jsonData(from: content))
        return translated.query
    }

    static func request(
        configuration: AutopilotQueryTranslatorConfiguration,
        naturalLanguage: String
    ) throws -> URLRequest {
        var request = URLRequest(url: configuration.endpoint, timeoutInterval: configuration.timeout)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": naturalLanguage]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static let systemPrompt = """
    You translate a photographer's natural-language photo request into Teststrip's \
    library-search field syntax. Return ONLY JSON shaped as {"query":"<field syntax>"}. \
    Use only these tokens: rating:, keyword:, person:, folder:, camera:, lens:, iso:, \
    from:, before:, date:, color:, source:, signal:, xmp:, and the bare words pick, \
    reject, unevaluated. Combine tokens with spaces. Do not invent fields; if a request \
    has no matching field, put the words in the query as plain text.
    """

    private static func jsonData(from content: String) -> Data {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "{"),
           let end = trimmed.lastIndex(of: "}"),
           start <= end {
            return Data(trimmed[start...end].utf8)
        }
        return Data(trimmed.utf8)
    }

    private struct ChatCompletionResponse: Decodable {
        var choices: [Choice]

        struct Choice: Decodable {
            var message: Message
        }

        struct Message: Decodable {
            var content: String
        }
    }

    private struct TranslatedQuery: Decodable {
        var query: String
    }
}
