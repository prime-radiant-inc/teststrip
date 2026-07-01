public enum ColorLabel: String, Codable, Sendable, CaseIterable {
    case red
    case yellow
    case green
    case blue
    case purple
}

public enum PickFlag: String, Codable, Sendable {
    case pick
    case reject
}

public struct AssetMetadata: Codable, Equatable, Sendable {
    public var rating: Int
    public var colorLabel: ColorLabel?
    public var flag: PickFlag?
    public var keywords: [String]
    public var caption: String?
    public var creator: String?
    public var copyright: String?

    public init(
        rating: Int = 0,
        colorLabel: ColorLabel? = nil,
        flag: PickFlag? = nil,
        keywords: [String] = [],
        caption: String? = nil,
        creator: String? = nil,
        copyright: String? = nil
    ) {
        self.rating = rating
        self.colorLabel = colorLabel
        self.flag = flag
        self.keywords = keywords
        self.caption = caption
        self.creator = creator
        self.copyright = copyright
    }

    public static func validated(
        rating: Int,
        colorLabel: ColorLabel?,
        flag: PickFlag?,
        keywords: [String]
    ) throws -> AssetMetadata {
        guard (0...5).contains(rating) else {
            throw TeststripError.invalidState("rating must be between 0 and 5")
        }
        return AssetMetadata(rating: rating, colorLabel: colorLabel, flag: flag, keywords: keywords)
    }
}
