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

    func testImportFolderCommandRoundTripsThroughJSONLine() throws {
        let root = URL(fileURLWithPath: "/Volumes/Card/DCIM", isDirectory: true)
        let command = WorkerCommand.importFolder(root: root, duplicateHandling: .skipCatalogedContent)

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
        let body = String(line.dropLast())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "importFolder")
        XCTAssertEqual(json["rootURL"] as? String, root.path)
        XCTAssertEqual(json["duplicateHandling"] as? String, "skipCatalogedContent")
    }

    func testImportCardCommandRoundTripsThroughJSONLine() throws {
        let source = URL(fileURLWithPath: "/Volumes/Card/DCIM", isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: "/Photos/Ingested", isDirectory: true)
        let command = WorkerCommand.importCard(
            source: source,
            destinationRoot: destinationRoot,
            destinationPolicy: .flat,
            secondCopyDestination: nil,
            duplicateHandling: .importAll
        )

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
        let body = String(line.dropLast())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "importCard")
        XCTAssertEqual(json["sourceURL"] as? String, source.path)
        XCTAssertEqual(json["destinationRootURL"] as? String, destinationRoot.path)
        XCTAssertEqual(json["destinationPolicy"] as? String, "flat")
        XCTAssertNil(json["secondCopyDestinationRootURL"])
        XCTAssertEqual(json["duplicateHandling"] as? String, "importAll")
    }

    func testImportCardCommandRoundTripsDatedPolicyAndSecondCopyThroughJSONLine() throws {
        let source = URL(fileURLWithPath: "/Volumes/Card/DCIM", isDirectory: true)
        let destinationRoot = URL(fileURLWithPath: "/Photos/Ingested", isDirectory: true)
        let secondCopyDestination = URL(fileURLWithPath: "/Volumes/Backup", isDirectory: true)
        let command = WorkerCommand.importCard(
            source: source,
            destinationRoot: destinationRoot,
            destinationPolicy: .capturedDate,
            secondCopyDestination: secondCopyDestination,
            duplicateHandling: .skipCatalogedContent
        )

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
        let body = String(line.dropLast())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["destinationPolicy"] as? String, "capturedDate")
        XCTAssertEqual(json["secondCopyDestinationRootURL"] as? String, secondCopyDestination.path)
        XCTAssertEqual(json["duplicateHandling"] as? String, "skipCatalogedContent")
    }

    func testImportCardCommandDecodeDefaultsToFlatPolicyWithoutOptionalFields() throws {
        let line = """
        {"command":"importCard","sourceURL":"/Volumes/Card/DCIM","destinationRootURL":"/Photos/Ingested"}

        """

        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, .importCard(
            source: URL(fileURLWithPath: "/Volumes/Card/DCIM", isDirectory: true),
            destinationRoot: URL(fileURLWithPath: "/Photos/Ingested", isDirectory: true),
            destinationPolicy: .flat,
            secondCopyDestination: nil,
            duplicateHandling: .importAll
        ))
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

    func testImportCompletionEventRoundTripsImportedAssetIDs() throws {
        let event = WorkerEvent.completedImport(
            itemID: WorkSessionID(rawValue: "import-work"),
            message: "imported 2 photos from photos",
            importedAssetIDs: [AssetID(rawValue: "asset-1"), AssetID(rawValue: "asset-2")],
            newAssetCount: 1,
            existingAssetCount: 1,
            skippedSourceFileCount: 2,
            skippedSourceFiles: [
                LibrarySkippedSourceFile(
                    sourceURL: URL(fileURLWithPath: "/Photos/two.cr2"),
                    message: "could not fingerprint /Photos/two.cr2"
                )
            ]
        )

        let line = try WorkerProtocolEncoder.encode(event)
        let decoded = try WorkerProtocolEncoder.decodeEvent(line)

        XCTAssertEqual(decoded, event)
        let body = String(line.dropLast())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["event"] as? String, "completed")
        XCTAssertEqual(json["importedAssetIDs"] as? [String], ["asset-1", "asset-2"])
        XCTAssertEqual(json["newAssetCount"] as? Int, 1)
        XCTAssertEqual(json["existingAssetCount"] as? Int, 1)
        XCTAssertEqual(json["skippedSourceFileCount"] as? Int, 2)
        let skippedSourceFiles = try XCTUnwrap(json["skippedSourceFiles"] as? [[String: String]])
        XCTAssertEqual(skippedSourceFiles.first?["sourceURL"], "file:///Photos/two.cr2")
        XCTAssertEqual(skippedSourceFiles.first?["message"], "could not fingerprint /Photos/two.cr2")
    }

    func testProgressEventRoundTripsThroughJSONLine() throws {
        let event = WorkerEvent.progress(
            itemID: WorkSessionID(rawValue: "import-work"),
            completedUnitCount: 3,
            totalUnitCount: 8,
            detail: "Cataloged 3 photos",
            catalogedAssetIDs: [AssetID(rawValue: "asset-1"), AssetID(rawValue: "asset-2")]
        )

        let line = try WorkerProtocolEncoder.encode(event)
        let decoded = try WorkerProtocolEncoder.decodeEvent(line)

        XCTAssertEqual(decoded, event)
        let body = String(line.dropLast())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["event"] as? String, "progress")
        XCTAssertEqual(json["completedUnitCount"] as? Int, 3)
        XCTAssertEqual(json["totalUnitCount"] as? Int, 8)
        XCTAssertEqual(json["message"] as? String, "Cataloged 3 photos")
        XCTAssertEqual(json["catalogedAssetIDs"] as? [String], ["asset-1", "asset-2"])
    }

    func testWorkerCommandRoundTripsThroughJSONLine() throws {
        let command = WorkerCommand.generatePreview(assetID: AssetID(rawValue: "asset-1"), level: .large)

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
    }

    func testRefreshAvailabilityCommandRoundTripsThroughJSONLine() throws {
        let command = WorkerCommand.refreshAvailability(assetID: AssetID(rawValue: "asset-1"))

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
        let body = String(line.dropLast())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "refreshAvailability")
        XCTAssertEqual(json["assetID"] as? String, "asset-1")
    }

    func testRefreshAvailabilityBatchCommandRoundTripsThroughJSONLine() throws {
        let command = WorkerCommand.refreshAvailabilityBatch(assetIDs: [
            AssetID(rawValue: "asset-1"),
            AssetID(rawValue: "asset-2")
        ])

        let line = try WorkerProtocolEncoder.encode(command)
        let decoded = try WorkerProtocolEncoder.decode(line)

        XCTAssertEqual(decoded, command)
        let body = String(line.dropLast())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
        XCTAssertEqual(json["command"] as? String, "refreshAvailabilityBatch")
        XCTAssertEqual(json["assetIDs"] as? [String], ["asset-1", "asset-2"])
    }

    func testPauseResumeAndCancelCommandsAreExplicit() throws {
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.pause)).controlKind, .pause)
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.resume)).controlKind, .resume)
        XCTAssertEqual(try WorkerProtocolEncoder.decode(try WorkerProtocolEncoder.encode(.cancelAll)).controlKind, .cancelAll)
    }
}
