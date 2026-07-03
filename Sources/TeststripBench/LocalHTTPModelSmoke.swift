import Foundation
import TeststripCore

public struct LocalHTTPModelSmokeResult: Equatable {
    public var signalCount: Int
    public var signalKinds: [EvaluationKind]

    public init(signalCount: Int, signalKinds: [EvaluationKind]) {
        self.signalCount = signalCount
        self.signalKinds = signalKinds
    }
}

public struct LocalHTTPModelSmoke {
    public var endpoint: URL
    public var model: String
    public var imageURL: URL
    public var timeout: TimeInterval
    private let transport: any LocalHTTPModelTransport

    public init(
        endpoint: URL,
        model: String,
        imageURL: URL,
        timeout: TimeInterval = 30,
        transport: any LocalHTTPModelTransport = URLSessionLocalHTTPModelTransport()
    ) {
        self.endpoint = endpoint
        self.model = model
        self.imageURL = imageURL
        self.timeout = timeout
        self.transport = transport
    }

    public func run() throws -> LocalHTTPModelSmokeResult {
        let provider = LocalHTTPModelProvider(
            endpoint: endpoint,
            model: model,
            timeout: timeout,
            transport: transport
        )
        let assetID = AssetID(rawValue: imageURL.deletingPathExtension().lastPathComponent)
        let signals = try provider.evaluate(assetID: assetID, previewURL: imageURL)
        return LocalHTTPModelSmokeResult(
            signalCount: signals.count,
            signalKinds: signals.map(\.kind)
        )
    }
}
