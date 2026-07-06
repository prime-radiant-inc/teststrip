import Foundation

public struct LocalHTTPModelHTTPResponse: Sendable {
    public var statusCode: Int
    public var data: Data

    public init(statusCode: Int, data: Data) {
        self.statusCode = statusCode
        self.data = data
    }
}

public protocol LocalHTTPModelTransport: Sendable {
    func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse
}

public struct LocalHTTPModelProviderConfiguration: Equatable, Sendable {
    public var endpoint: URL
    public var model: String
    public var timeout: TimeInterval

    public init(endpoint: URL, model: String, timeout: TimeInterval = 30) {
        self.endpoint = endpoint
        self.model = model
        self.timeout = timeout
    }
}

public struct URLSessionLocalHTTPModelTransport: LocalHTTPModelTransport {
    public init() {}

    public func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse {
        let semaphore = DispatchSemaphore(value: 0)
        let box = URLSessionResponseBox()
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                box.store(.failure(error))
            } else {
                box.store(.success(LocalHTTPModelHTTPResponse(
                    statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
                    data: data ?? Data()
                )))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        guard let result = box.load() else {
            throw TeststripError.io("HTTP model request did not return a response")
        }
        return try result.get()
    }
}

public struct LocalHTTPModelProvider: EvaluationProvider {
    private static let maxResponseAttempts = 3

    public var endpoint: URL
    public var model: String
    public var prompt: String
    public var timeout: TimeInterval
    private let transport: any LocalHTTPModelTransport

    public var name: String { "local-http-model" }

    public init(
        endpoint: URL,
        model: String,
        prompt: String = LocalHTTPModelProvider.defaultPrompt,
        timeout: TimeInterval = 30,
        transport: any LocalHTTPModelTransport = URLSessionLocalHTTPModelTransport()
    ) {
        self.endpoint = endpoint
        self.model = model
        self.prompt = prompt
        self.timeout = timeout
        self.transport = transport
    }

    public init(
        configuration: LocalHTTPModelProviderConfiguration,
        prompt: String = LocalHTTPModelProvider.defaultPrompt,
        transport: any LocalHTTPModelTransport = URLSessionLocalHTTPModelTransport()
    ) {
        self.init(
            endpoint: configuration.endpoint,
            model: configuration.model,
            prompt: prompt,
            timeout: configuration.timeout,
            transport: transport
        )
    }

    public func request(for imageURL: URL, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let dataURL = try Self.dataURL(forImageAt: imageURL)
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": dataURL]]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    public func evaluate(assetID: AssetID, previewURL: URL) throws -> [EvaluationSignal] {
        let response = try response(for: try request(for: previewURL, prompt: prompt))
        let completion = try JSONDecoder().decode(OpenAIChatCompletionResponse.self, from: response.data)
        guard let content = completion.choices.first?.message.content else {
            throw TeststripError.invalidState("HTTP model response did not include message content")
        }
        let contentData = Self.modelJSONData(from: content)
        let modelResponse = try JSONDecoder().decode(LocalHTTPModelEvaluationResponse.self, from: contentData)
        let provenance = ProviderProvenance(provider: name, model: model, version: "1", settingsHash: "default")
        return try modelResponse.signals.map { try $0.evaluationSignal(assetID: assetID, provenance: provenance) }
    }

    private static func modelJSONData(from content: String) -> Data {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmedContent.firstIndex(of: "{"),
           let end = trimmedContent.lastIndex(of: "}"),
           start <= end {
            return Data(trimmedContent[start...end].utf8)
        }
        return Data(trimmedContent.utf8)
    }

    private func response(for request: URLRequest) throws -> LocalHTTPModelHTTPResponse {
        var lastTransportError: Error?
        for attempt in 1...Self.maxResponseAttempts {
            let response: LocalHTTPModelHTTPResponse
            do {
                response = try transport.response(for: request)
            } catch {
                guard attempt < Self.maxResponseAttempts else {
                    throw error
                }
                lastTransportError = error
                continue
            }
            if (200..<300).contains(response.statusCode) {
                return response
            }
            guard Self.shouldRetry(statusCode: response.statusCode), attempt < Self.maxResponseAttempts else {
                throw TeststripError.io("HTTP model request failed with status \(response.statusCode)")
            }
        }
        throw lastTransportError ?? TeststripError.io("HTTP model request did not return a response")
    }

    private static func shouldRetry(statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500..<600).contains(statusCode)
    }

    public static let defaultPrompt = """
    Evaluate this photo for culling. Return only JSON shaped as {"signals":[{"kind":"aesthetics","label":"keeper","confidence":0.0},{"kind":"framing","label":"balanced composition","confidence":0.0},{"kind":"focus","score":0.0,"confidence":0.0},{"kind":"faceCount","count":1,"confidence":0.0}]}.
    Use Teststrip signal kinds when possible: focus, motionBlur, exposure, aesthetics, framing, object, faceCount, faceQuality, ocrText, colorPalette, novelty, visualSimilarity.
    """

    private static func dataURL(forImageAt url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        return "data:\(mimeType(for: url));base64,\(data.base64EncodedString())"
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "webp":
            return "image/webp"
        default:
            return "application/octet-stream"
        }
    }
}

private final class URLSessionResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<LocalHTTPModelHTTPResponse, Error>?

    func store(_ result: Result<LocalHTTPModelHTTPResponse, Error>) {
        lock.lock()
        self.result = result
        lock.unlock()
    }

    func load() -> Result<LocalHTTPModelHTTPResponse, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return result
    }
}

private struct OpenAIChatCompletionResponse: Decodable {
    var choices: [Choice]

    struct Choice: Decodable {
        var message: Message
    }

    struct Message: Decodable {
        var content: String
    }
}

private struct LocalHTTPModelEvaluationResponse: Decodable {
    var signals: [LocalHTTPModelSignal]
}

private struct LocalHTTPModelSignal: Decodable {
    var kind: EvaluationKind
    var confidence: Double?
    var score: Double?
    var label: String?
    var labels: [String]?
    var text: String?
    var count: Int?
    var vector: [Double]?

    func evaluationSignal(assetID: AssetID, provenance: ProviderProvenance) throws -> EvaluationSignal {
        EvaluationSignal(
            assetID: assetID,
            kind: kind,
            value: try value(),
            confidence: confidence ?? 1.0,
            provenance: provenance
        )
    }

    private func value() throws -> EvaluationValue {
        if let score {
            return .score(score)
        }
        if let label {
            return .label(label)
        }
        if let labels {
            return .labels(labels)
        }
        if let text {
            return .text(text)
        }
        if let count {
            return .count(count)
        }
        if let vector {
            return .vector(vector)
        }
        throw TeststripError.invalidState("HTTP model signal did not include a supported value")
    }
}
