import Foundation

public protocol WorkerTransport: AnyObject {
    var isRunning: Bool { get }
    var outputHandler: ((String) -> Void)? { get set }

    func launch() throws
    func writeLine(_ line: String) throws
    func terminate()
}

public final class FoundationWorkerTransport: WorkerTransport, @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var outputBuffer = Data()
    private let outputQueue = DispatchQueue(label: "teststrip.worker-output")

    public var outputHandler: ((String) -> Void)?

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
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = Pipe()
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.outputQueue.async { [weak self] in
                self?.receiveOutput(data)
            }
        }

        try process.run()

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
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
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        try? inputPipe?.fileHandleForWriting.close()
        inputPipe = nil
        outputPipe = nil
    }

    deinit {
        terminate()
    }

    private func receiveOutput(_ data: Data) {
        outputBuffer.append(data)
        while let newlineIndex = outputBuffer.firstIndex(of: 0x0A) {
            let lineData = outputBuffer[..<newlineIndex]
            outputBuffer.removeSubrange(...newlineIndex)
            guard let line = String(data: lineData, encoding: .utf8) else {
                continue
            }
            outputHandler?(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
        }
    }
}
