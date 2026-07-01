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
    public var rating: Int {
        didSet {
            precondition(Self.isValidRating(rating), Self.invalidRatingMessage)
        }
    }
    public var colorLabel: ColorLabel?
    public var flag: PickFlag?
    public var keywords: [String]
    public var caption: String?
    public var creator: String?
    public var copyright: String?

    private static let validRatingRange = 0...5
    private static let invalidRatingMessage = "rating must be between 0 and 5"

    public init(
        rating: Int = 0,
        colorLabel: ColorLabel? = nil,
        flag: PickFlag? = nil,
        keywords: [String] = [],
        caption: String? = nil,
        creator: String? = nil,
        copyright: String? = nil
    ) {
        precondition(Self.isValidRating(rating), Self.invalidRatingMessage)

        self.rating = rating
        self.colorLabel = colorLabel
        self.flag = flag
        self.keywords = keywords
        self.caption = caption
        self.creator = creator
        self.copyright = copyright
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rating = try container.decode(Int.self, forKey: .rating)
        guard Self.isValidRating(rating) else {
            throw DecodingError.dataCorruptedError(
                forKey: .rating,
                in: container,
                debugDescription: Self.invalidRatingMessage
            )
        }

        self.rating = rating
        self.colorLabel = try container.decodeIfPresent(ColorLabel.self, forKey: .colorLabel)
        self.flag = try container.decodeIfPresent(PickFlag.self, forKey: .flag)
        self.keywords = try container.decode([String].self, forKey: .keywords)
        self.caption = try container.decodeIfPresent(String.self, forKey: .caption)
        self.creator = try container.decodeIfPresent(String.self, forKey: .creator)
        self.copyright = try container.decodeIfPresent(String.self, forKey: .copyright)
    }

    public static func validated(
        rating: Int,
        colorLabel: ColorLabel?,
        flag: PickFlag?,
        keywords: [String]
    ) throws -> AssetMetadata {
        guard Self.isValidRating(rating) else {
            throw TeststripError.invalidState(Self.invalidRatingMessage)
        }
        return AssetMetadata(rating: rating, colorLabel: colorLabel, flag: flag, keywords: keywords)
    }

    private static func isValidRating(_ rating: Int) -> Bool {
        validRatingRange.contains(rating)
    }
}
