import Foundation
import TeststripCore

struct SourceReconnectPathDraft: Equatable {
    var oldRootPath: String {
        didSet {
            if oldRootPath != oldValue {
                errorMessage = nil
            }
        }
    }
    var newRootPath: String {
        didSet {
            if newRootPath != oldValue {
                errorMessage = nil
            }
        }
    }
    private(set) var errorMessage: String?

    init(oldRootPath: String = "", newRootPath: String = "", errorMessage: String? = nil) {
        self.oldRootPath = oldRootPath
        self.newRootPath = newRootPath
        self.errorMessage = errorMessage
    }

    mutating func reset() {
        oldRootPath = ""
        newRootPath = ""
        errorMessage = nil
    }

    mutating func recordError(_ message: String) {
        errorMessage = message
    }

    @MainActor
    mutating func resolveRootURLs() throws -> (oldRoot: URL, newRoot: URL) {
        do {
            let oldRoot = try sourceRootURL(fromPath: oldRootPath, emptyMessage: "Enter old source root")
            let newRoot = try existingSourceRootURL(fromPath: newRootPath)
            errorMessage = nil
            return (oldRoot, newRoot)
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    private func sourceRootURL(fromPath path: String, emptyMessage: String) throws -> URL {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            throw TeststripError.invalidState(emptyMessage)
        }
        let expandedPath = (trimmedPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath, isDirectory: true).standardizedFileURL
    }

    private func existingSourceRootURL(fromPath path: String) throws -> URL {
        let url = try sourceRootURL(fromPath: path, emptyMessage: "Enter new source root")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw TeststripError.invalidState("New source root does not exist")
        }
        return url
    }
}
