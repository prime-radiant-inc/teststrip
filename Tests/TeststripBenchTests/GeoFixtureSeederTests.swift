import XCTest
import TeststripCore
@testable import TeststripBench

final class GeoFixtureSeederTests: XCTestCase {
    func testSeedGeoFixturesCommandParsesDirectoryAndCount() throws {
        let command = BenchmarkCommand.parse(["TeststripBench", "seed-geo-fixtures", "/tmp/geo", "8"])
        XCTAssertEqual(
            command,
            .seedGeoFixtures(directory: URL(fileURLWithPath: "/tmp/geo"), count: 8)
        )
    }

    func testSeededGpsFixturesRoundTripThroughImageIODecodeProvider() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let seeder = GeoFixtureSeeder(directory: directory, count: 8)
        let result = try seeder.run()

        XCTAssertEqual(result.totalCount, 8)
        XCTAssertGreaterThan(result.gpsBearingCount, 0)
        XCTAssertLessThan(result.gpsBearingCount, result.totalCount)

        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertEqual(files.count, 8)

        let provider = ImageIODecodeProvider()
        var gpsBearing = 0
        var withoutGPS = 0
        for file in files {
            let metadata = try provider.metadata(for: file)
            if let latitude = metadata.latitude, let longitude = metadata.longitude {
                XCTAssertEqual(latitude, GeoFixtureSeeder.eiffelLatitude, accuracy: 0.0001)
                XCTAssertEqual(longitude, GeoFixtureSeeder.eiffelLongitude, accuracy: 0.0001)
                gpsBearing += 1
            } else {
                withoutGPS += 1
            }
        }
        XCTAssertEqual(gpsBearing, result.gpsBearingCount)
        XCTAssertEqual(withoutGPS, result.totalCount - result.gpsBearingCount)
    }

    private func makeScratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("teststrip-geo-fixtures-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
