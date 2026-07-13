import Foundation
import TeststripCore

let runtimeArguments = Array(CommandLine.arguments.dropFirst())
let output = SerializedOutput()
let executorProvider = LazyWorkerExecutor(arguments: runtimeArguments)

let loop = WorkerCommandLoop(
    execute: { request in
        do {
            let executor = try executorProvider.shared()
            let result = try executor.execute(request.command) { progress in
                guard let itemID = request.itemID else { return }
                output.write(.progress(
                    itemID: itemID,
                    completedUnitCount: progress.completedUnitCount,
                    totalUnitCount: progress.totalUnitCount,
                    detail: progress.detail,
                    catalogedAssetIDs: progress.catalogedAssetIDs
                ))
            }
            return (try? WorkerProtocolEncoder.encode(result.event(itemID: request.itemID))) ?? failedLine(request: request)
        } catch {
            return failedLine(request: request, error: error)
        }
    },
    writeLine: { line in
        output.writeRaw(line)
    }
)

// Reads and decodes on the main thread; a decode failure is unstructured and goes
// to stderr, while control commands (pause/resume/cancelAll) are acknowledged
// inline so they never wait behind an in-flight command. Everything else is
// submitted to the loop, which runs commands concurrently across lanes. After
// stdin closes, `drain()` waits for in-flight commands so no output is lost.
while let line = readLine() {
    do {
        let request = try WorkerProtocolEncoder.decodeRequest(line)
        if let controlKind = request.command.controlKind {
            output.write(.accepted(itemID: request.itemID, message: controlKind.rawValue))
        } else {
            loop.submit(request)
        }
    } catch {
        writeError(error)
    }
}
loop.drain()

/// Builds the shared `WorkerCommandExecutor` exactly once, safely across the
/// concurrent lanes. Init opens the catalog and constructs the providers, so a
/// single instance is shared: `CatalogDatabase`'s lock (Task B1) only serializes
/// lanes when they all point at one handle. Failure leaves the executor unbuilt so
/// a later command retries, matching the original lazy behavior.
final class LazyWorkerExecutor: @unchecked Sendable {
    private let lock = NSLock()
    private let arguments: [String]
    private var executor: WorkerCommandExecutor?

    init(arguments: [String]) {
        self.arguments = arguments
    }

    func shared() throws -> WorkerCommandExecutor {
        lock.lock()
        defer { lock.unlock() }
        if let executor {
            return executor
        }
        let built = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(arguments: arguments))
        executor = built
        return built
    }
}

/// The single serialized stdout sink. Every line — terminal events, `.progress`
/// events emitted mid-command, and control acknowledgements — passes through the
/// same lock so concurrently finishing commands never interleave a partial line.
final class SerializedOutput: @unchecked Sendable {
    private let lock = NSLock()

    func write(_ event: WorkerEvent) {
        guard let line = try? WorkerProtocolEncoder.encode(event) else { return }
        writeRaw(line)
    }

    func writeRaw(_ line: String) {
        let data = Data(line.utf8)
        lock.lock()
        FileHandle.standardOutput.write(data)
        lock.unlock()
    }
}

private func failedLine(request: WorkerCommandRequest, error: Error? = nil) -> String {
    let message = error?.localizedDescription ?? "worker could not encode result"
    return (try? WorkerProtocolEncoder.encode(.failed(itemID: request.itemID, message: message))) ?? ""
}

private extension WorkerCommandResult {
    func event(itemID: WorkSessionID?) -> WorkerEvent {
        switch self {
        case .accepted(let message):
            return .accepted(itemID: itemID, message: message)
        case .completed(let message):
            return .completed(itemID: itemID, message: message)
        case .completedImport(
            let message,
            let importedAssetIDs,
            let newAssetCount,
            let existingAssetCount,
            let skippedSourceFileCount,
            let skippedSourceFiles
        ):
            return .completedImport(
                itemID: itemID,
                message: message,
                importedAssetIDs: importedAssetIDs,
                newAssetCount: newAssetCount,
                existingAssetCount: existingAssetCount,
                skippedSourceFileCount: skippedSourceFileCount,
                skippedSourceFiles: skippedSourceFiles
            )
        }
    }
}

private func writeError(_ error: Error) {
    FileHandle.standardError.write(Data("error \(error.localizedDescription)\n".utf8))
}
