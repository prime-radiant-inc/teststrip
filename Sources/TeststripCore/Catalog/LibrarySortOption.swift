import Foundation

public enum LibrarySortOption: String, CaseIterable, Codable, Equatable, Sendable {
    case importOrder
    case captureTimeNewestFirst
    case captureTimeOldestFirst
    case filename
}
