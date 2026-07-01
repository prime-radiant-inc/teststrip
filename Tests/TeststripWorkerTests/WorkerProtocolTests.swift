import XCTest
@testable import TeststripCore
@testable import TeststripWorker

final class WorkerProtocolTests: XCTestCase {
    func testWorkerCommandRoundTripsThroughJSONLine() throws {
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .large)

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
    }

    func testPauseAndCancelCommandsAreExplicit() throws {
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.pause)).controlKind, .pause)
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.cancelAll)).controlKind, .cancelAll)
    }
}
