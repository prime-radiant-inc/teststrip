import Foundation

public enum LibrarySortOption: String, CaseIterable, Codable, Equatable, Sendable {
    case importOrder
    case captureTimeNewestFirst
    case captureTimeOldestFirst
    case ratingHighestFirst
    case ratingLowestFirst
    case filename
}
