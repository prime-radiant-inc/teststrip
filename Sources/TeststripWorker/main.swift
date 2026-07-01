import Foundation
import TeststripCore

while let line = readLine() {
    do {
        let command = try WorkerProtocolEncoder.decode(line)
        let response = "accepted \(command)\n"
        FileHandle.standardOutput.write(Data(response.utf8))
    } catch {
        let response = "error \(error)\n"
        FileHandle.standardError.write(Data(response.utf8))
    }
}
