import Foundation
import TeststripCore

let runtimeArguments = Array(CommandLine.arguments.dropFirst())
var executor: WorkerCommandExecutor?

while let line = readLine() {
    do {
        let command = try WorkerProtocolEncoder.decode(line)
        let result = try execute(command)
        FileHandle.standardOutput.write(Data((result.responseLine + "\n").utf8))
    } catch {
        let response = "error \(error)\n"
        FileHandle.standardError.write(Data(response.utf8))
    }
}

@MainActor
private func execute(_ command: WorkerCommand) throws -> WorkerCommandResult {
    if let controlKind = command.controlKind {
        return .accepted(controlKind.rawValue)
    }

    if executor == nil {
        executor = try WorkerCommandExecutor(configuration: WorkerRuntimeConfiguration(arguments: runtimeArguments))
    }
    return try executor!.execute(command)
}
