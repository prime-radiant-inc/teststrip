public enum PreviewLevel: String, Codable, CaseIterable, Sendable {
    case micro
    case grid
    case medium
    case large
    case original

    public var maxPixelDimension: Int? {
        switch self {
        case .micro: return 160
        case .grid: return 512
        case .medium: return 1600
        case .large: return 3200
        case .original: return nil
        }
    }
}
