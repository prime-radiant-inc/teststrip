public enum SourceAvailability: String, Codable, Hashable, Sendable {
    case online
    case offline
    case missing
    case moved
    case stale
}
