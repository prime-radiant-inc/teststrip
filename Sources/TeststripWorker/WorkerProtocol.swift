import Foundation

public enum WorkerProtocolEncoder {
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public static func encode(_ command: WorkerCommand) throws -> String {
        let data = try encoder.encode(command)
        return String(data: data, encoding: .utf8)! + "\n"
    }

    public static func decode(_ line: String) throws -> WorkerCommand {
        try decoder.decode(WorkerCommand.self, from: Data(line.utf8))
    }
}
