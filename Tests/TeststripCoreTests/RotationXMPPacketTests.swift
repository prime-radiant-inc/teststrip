import XCTest
@testable import TeststripCore

final class RotationXMPPacketTests: XCTestCase {
    func testRotationWrittenToXMPWhenNonZero() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 90)
        let data = try packet.xmlData()
        let xmlString = String(data: data, encoding: .utf8)!
        XCTAssertTrue(xmlString.contains("ts:Rotation"))
        XCTAssertTrue(xmlString.contains("90"))
    }

    func testRotationNotWrittenToXMPWhenZero() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 0)
        let data = try packet.xmlData()
        let xmlString = String(data: data, encoding: .utf8)!
        XCTAssertFalse(xmlString.contains("ts:Rotation"))
    }

    func testRotationNotWrittenToXMPWhenNil() throws {
        let packet = XMPPacket(metadata: AssetMetadata())
        let data = try packet.xmlData()
        let xmlString = String(data: data, encoding: .utf8)!
        XCTAssertFalse(xmlString.contains("ts:Rotation"))
    }

    func testParseReadsRotationFromXMP() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 90)
        let data = try packet.xmlData()
        let parsed = try XMPPacket.parse(data)
        XCTAssertEqual(parsed.rotation, 90)
    }

    func testParseReturnsNilRotationWhenAbsent() throws {
        let packet = XMPPacket(metadata: AssetMetadata())
        let data = try packet.xmlData()
        let parsed = try XMPPacket.parse(data)
        XCTAssertNil(parsed.rotation)
    }

    func testRoundTripRotation180() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 180)
        let parsed = try XMPPacket.parse(try packet.xmlData())
        XCTAssertEqual(parsed.rotation, 180)
    }

    func testRoundTripRotation270() throws {
        let packet = XMPPacket(metadata: AssetMetadata(), rotation: 270)
        let parsed = try XMPPacket.parse(try packet.xmlData())
        XCTAssertEqual(parsed.rotation, 270)
    }

    func testMergeRotationIntoExistingSidecar() throws {
        let existing = try XMPPacket(metadata: AssetMetadata(rating: 3), rotation: 90).xmlData()
        let merged = try XMPPacket(metadata: AssetMetadata(rating: 3), rotation: 180).xmlData(mergingInto: existing)
        let parsed = try XMPPacket.parse(merged)
        XCTAssertEqual(parsed.rotation, 180)
        XCTAssertEqual(parsed.metadata.rating, 3)
    }

    func testRemoveRotationWhenSetToZero() throws {
        let existing = try XMPPacket(metadata: AssetMetadata(), rotation: 90).xmlData()
        let merged = try XMPPacket(metadata: AssetMetadata(), rotation: 0).xmlData(mergingInto: existing)
        let parsed = try XMPPacket.parse(merged)
        XCTAssertNil(parsed.rotation)
    }

    func testSidecarWriteIncludesRotation() throws {
        let store = XMPSidecarStore()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("rotation-xmp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let originalURL = tmpDir.appendingPathComponent("test.jpg")
        try Data().write(to: originalURL)
        let result = try store.write(metadata: AssetMetadata(), rotation: 90, forOriginalAt: originalURL)
        let sidecarData = try Data(contentsOf: result.sidecarURL)
        let parsed = try XMPPacket.parse(sidecarData)
        XCTAssertEqual(parsed.rotation, 90)
    }

    func testSidecarWriteOmitsRotationWhenZero() throws {
        let store = XMPSidecarStore()
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("rotation-xmp-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }
        let originalURL = tmpDir.appendingPathComponent("test.jpg")
        try Data().write(to: originalURL)
        let result = try store.write(metadata: AssetMetadata(), rotation: 0, forOriginalAt: originalURL)
        let sidecarData = try Data(contentsOf: result.sidecarURL)
        let xmlString = String(data: sidecarData, encoding: .utf8)!
        XCTAssertFalse(xmlString.contains("ts:Rotation"))
    }

    func testMetadataSyncPlannerWritesWhenRotationOnly() throws {
        let planner = MetadataSyncPlanner()
        let decision = try planner.decision(
            catalogMetadata: AssetMetadata(),
            catalogRotation: 90,
            catalogGeneration: 1,
            lastSynced: nil,
            sidecarData: nil
        )
        XCTAssertEqual(decision, .writeCatalog)
    }

    func testMetadataSyncPlannerUpToDateWhenNoRotationAndNoMetadata() throws {
        let planner = MetadataSyncPlanner()
        let decision = try planner.decision(
            catalogMetadata: AssetMetadata(),
            catalogRotation: 0,
            catalogGeneration: 1,
            lastSynced: nil,
            sidecarData: nil
        )
        XCTAssertEqual(decision, .upToDate)
    }
}
