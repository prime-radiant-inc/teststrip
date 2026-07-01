import Foundation

public struct LocalHTTPModelProvider: Sendable {
    public var endpoint: URL
    public var model: String

    public init(endpoint: URL, model: String) {
        self.endpoint = endpoint
        self.model = model
    }

    public func request(for imageURL: URL, prompt: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "text", "text": "image_path:\(imageURL.path)"]
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
}
