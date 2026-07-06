import Foundation
import TeststripCore

let runtimeArguments = Array(CommandLine.arguments.dropFirst())
var executor: WorkerCommandExecutor?

while let line = readLine() {
    do {
        let request = try WorkerProtocolEncoder.decodeRequest(line)
        do {
            let result = try execute(request.command, itemID: request.itemID)
            try write(result.event(itemID: request.itemID))
        } catch {
            try write(.failed(itemID: request.itemID, message: error.localizedDescription))
        }
    } catch {
        writeError(error)
    }
}

@MainActor
private func execute(_ command: WorkerCommand, itemID: WorkSessionID?) throws -> WorkerCommandResult {
    if let controlKind = command.controlKind {
        return .accepted(controlKind.rawValue)
    }

    if executor == nil {
        executor = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(arguments: runtimeArguments))
    }
    return try executor!.execute(command) { progress in
        guard let itemID else { return }
        try? write(.progress(
            itemID: itemID,
            completedUnitCount: progress.completedUnitCount,
            totalUnitCount: progress.totalUnitCount,
            detail: progress.detail,
            catalogedAssetIDs: progress.catalogedAssetIDs
        ))
    }
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

private func write(_ event: WorkerEvent) throws {
    FileHandle.standardOutput.write(Data(try WorkerProtocolEncoder.encode(event).utf8))
}

private func writeError(_ error: Error) {
    FileHandle.standardError.write(Data("error \(error.localizedDescription)\n".utf8))
}
