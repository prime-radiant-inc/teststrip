import Foundation
import XCTest
@testable import TeststripCore
@testable import TeststripWorker

final class WorkerProtocolTests: XCTestCase {
    func testDecodesLiteralGeneratePreviewCommandEnvelope() throws {
        let line = #"{ "command": "generatePreview", "assetID": "asset-1", "level": "large" }"# + "\n"

        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, .generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .large))
    }

    func testDecodesLiteralPauseCommandEnvelope() throws {
        let line = #"{ "command": "pause" }"# + "\n"

        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded.controlKind, .pause)
    }

    func testEncodesRunEvaluationAsStableCommandEnvelope() throws {
        let line = try WorkerProtocolEncoder.encode(.runEvaluation(assetID: AssetID(rawValue: "asset-1"), provider: "local"))

        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(line.hasSuffix("\n"))

        let body = String(line.dropLast())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])

        XCTAssertEqual(json["command"] as? String, "runEvaluation")
        XCTAssertEqual(json["assetID"] as? String, "asset-1")
        XCTAssertEqual(json["provider"] as? String, "local")
    }

    func testCommandRequestRoundTripsItemID() throws {
        let itemID = WorkSessionID(rawValue: "work-1")
        let command = WorkerCommand.runEvaluation(assetID: AssetID(rawValue: "asset-1"), provider: "local")

        let request = try WorkerProtocolEncoder.decodeRequest(try WorkerProtocolEncoder.encode(command, itemID: itemID))

        XCTAssertEqual(request.command, command)
        XCTAssertEqual(request.itemID, itemID)
    }

    func testWorkerEventRoundTripsThroughJSONLine() throws {
        let event = WorkerEvent.completed(
            itemID: WorkSessionID(rawValue: "work-1"),
            message: "generated grid preview"
        )

        let line = try WorkerProtocolEncoder.encode(event)
        let decoded = try WorkerProtocolEncoder.decodeEvent(line)

        XCTAssertEqual(line.filter { $0 == "\n" }.count, 1)
        XCTAssertTrue(line.hasSuffix("\n"))
        XCTAssertEqual(decoded, event)
    }

    func testWorkerCommandRoundTripsThroughJSONLine() throws {
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .large)

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
    }

    func testPauseResumeAndCancelCommandsAreExplicit() throws {
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.pause)).controlKind, .pause)
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.resume)).controlKind, .resume)
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.cancelAll)).controlKind, .cancelAll)
    }
}
