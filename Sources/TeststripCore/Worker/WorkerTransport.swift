import Foundation

public protocol WorkerTransport: AnyObject {
    var isRunning: Bool { get }

    func launch() throws
    func writeLine(_ line: String) throws
    func terminate()
}

public final class FoundationWorkerTransport: WorkerTransport {
    private let executableURL: URL
    private let arguments: [String]
    private var process: Process?
    private var inputPipe: Pipe?

    public init(executableURL: URL, arguments: [String] = []) {
        self.executableURL = executableURL
        self.arguments = arguments
    }

    public var isRunning: Bool {
        process?.isRunning ?? false
    }

    public func launch() throws {
        if isRunning {
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()

        self.process = process
        self.inputPipe = inputPipe
    }

    public func writeLine(_ line: String) throws {
        guard isRunning, let inputPipe else {
            throw TeststripError.invalidState("worker process is not running")
        }
        inputPipe.fileHandleForWriting.write(Data(line.utf8))
    }

    public func terminate() {
        if process?.isRunning == true {
            process?.terminate()
        }
        try? inputPipe?.fileHandleForWriting.close()
        inputPipe = nil
    }

    deinit {
        terminate()
    }
}
