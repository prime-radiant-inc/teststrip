import Foundation

public protocol EvaluationProvider: Sendable {
    var name: String { get }
    func evaluate(assetID: AssetID, previewURL: URL) async throws -> [EvaluationSignal]
}
