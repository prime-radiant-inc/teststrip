public enum SourceAvailability: String, Codable, Hashable, Sendable {
    case online
    case offline
    case missing
    case moved
    case stale
}

extension SourceAvailability {
    // The exact set `WorkerCommandExecutor.markPreviewBlockingAvailabilityIfNeeded`
    // refuses to render from -- the states `SourceAvailabilityProbe` can
    // actually produce for a blocked original. Used by
    // `CatalogRepository.updateAvailability` to detect a recovery (a
    // blocking -> non-blocking transition) and reset the preview-generation
    // retry cap so automatic generation can resume once the original is
    // reachable and unchanged again (kata #15).
    public var blocksPreviewGeneration: Bool {
        switch self {
        case .offline, .missing, .stale:
            return true
        case .online, .moved:
            return false
        }
    }
}
