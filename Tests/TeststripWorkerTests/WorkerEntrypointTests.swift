import XCTest

final class WorkerEntrypointTests: XCTestCase {
    func testMalformedCommandWritesUnstructuredErrorToStderr() throws {
        let workerURL = try builtWorkerExecutableURL()
        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = workerURL
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        inputPipe.fileHandleForWriting.write(Data("not-json\n".utf8))
        inputPipe.fileHandleForWriting.closeFile()
        process.waitUntilExit()

        let stdout = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(stdout, "")
        XCTAssertTrue(stderr.hasPrefix("error "))
    }

    private func builtWorkerExecutableURL() throws -> URL {
        let packageRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/TeststripWorker"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/TeststripWorker")
        ]

        guard let url = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) else {
            throw XCTSkip("TeststripWorker executable is not built")
        }
        return url
    }
}
