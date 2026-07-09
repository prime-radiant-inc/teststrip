import Foundation

public protocol WorkerTransport: AnyObject {
    var isRunning: Bool { get }
    var outputHandler: ((String) -> Void)? { get set }
    var errorHandler: ((String) -> Void)? { get set }
    /// Invoked when the worker process exits on its own — a crash, an OOM kill,
    /// or the OS reaping it — rather than through an explicit `terminate()`.
    var terminationHandler: (() -> Void)? { get set }

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
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var errorBuffer = Data()
    private let outputQueue = DispatchQueue(label: "teststrip.worker-output")
    private var isTerminatingIntentionally = false

    public var outputHandler: ((String) -> Void)?
    public var errorHandler: ((String) -> Void)?
    public var terminationHandler: (() -> Void)?

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
        let errorPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.outputQueue.async { [weak self] in
                self?.receiveOutput(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.outputQueue.async { [weak self] in
                self?.receiveError(data)
            }
        }
        process.terminationHandler = { [weak self] _ in
            self?.handleProcessTermination()
        }

        isTerminatingIntentionally = false
        try process.run()

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
    }

    public func writeLine(_ line: String) throws {
        guard isRunning, let inputPipe else {
            throw TeststripError.invalidState("worker process is not running")
        }
        var data = Data(line.utf8)
        if !line.hasSuffix("\n") {
            data.append(0x0A)
        }
        inputPipe.fileHandleForWriting.write(data)
    }

    public func terminate() {
        isTerminatingIntentionally = true
        if process?.isRunning == true {
            process?.terminate()
        }
        process?.terminationHandler = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? inputPipe?.fileHandleForWriting.close()
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
    }

    deinit {
        terminate()
    }

    private func handleProcessTermination() {
        guard !isTerminatingIntentionally else { return }
        terminationHandler?()
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

    private func receiveError(_ data: Data) {
        errorBuffer.append(data)
        while let newlineIndex = errorBuffer.firstIndex(of: 0x0A) {
            let lineData = errorBuffer[..<newlineIndex]
            errorBuffer.removeSubrange(...newlineIndex)
            guard let line = String(data: lineData, encoding: .utf8) else {
                continue
            }
            errorHandler?(line.trimmingCharacters(in: CharacterSet(charactersIn: "\r")))
        }
    }
}
