public enum SourceAvailability: String, Codable, Sendable {
    case online
    case offline
    case missing
    case moved
    case stale
}
