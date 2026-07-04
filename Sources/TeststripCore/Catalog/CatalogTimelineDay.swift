import Foundation

public struct CatalogTimelineDay: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    public var assetCount: Int

    public init(year: Int, month: Int, day: Int, assetCount: Int) {
        self.year = year
        self.month = month
        self.day = day
        self.assetCount = assetCount
    }

    public var id: String {
        "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
    }

    public func startDate(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    public func endDate(calendar: Calendar = .current) -> Date? {
        guard let startDate = startDate(calendar: calendar) else { return nil }
        return calendar.date(byAdding: .day, value: 1, to: startDate)
    }
}
