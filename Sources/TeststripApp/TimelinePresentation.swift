import Foundation
import TeststripCore

struct TimelinePresentation: Equatable {
    var months: [TimelineMonthPresentation]
    var scrubber: TimelineScrubberPresentation
    var summaryText: String
    var yearRibbon: TimelineYearRibbonPresentation

    init(assets: [Asset], totalAssetCount: Int, calendar: Calendar = .current) {
        self.init(
            timelineDays: Self.timelineDays(from: assets, calendar: calendar),
            loadedAssets: assets,
            totalAssetCount: totalAssetCount,
            calendar: calendar
        )
    }

    init(
        timelineDays: [CatalogTimelineDay],
        loadedAssets: [Asset],
        totalAssetCount: Int,
        calendar: Calendar = .current
    ) {
        let sortedAssets = Self.sortedAssets(loadedAssets)
        let months = Self.months(for: timelineDays, loadedAssets: sortedAssets, calendar: calendar)
        self.months = months
        self.scrubber = Self.scrubber(
            for: months,
            focusedMonthID: Self.focusedMonthID(
                timelineDays: timelineDays,
                loadedAssets: sortedAssets,
                calendar: calendar
            ),
            focusedDayID: Self.focusedDayID(
                timelineDays: timelineDays,
                loadedAssets: sortedAssets,
                calendar: calendar
            )
        )
        self.yearRibbon = Self.yearRibbon(
            for: timelineDays,
            loadedAssets: sortedAssets,
            totalAssetCount: totalAssetCount,
            calendar: calendar
        )
        let dayCount = timelineDays.count
        if dayCount == 0, loadedAssets.isEmpty {
            self.summaryText = "No dated photographs"
        } else if dayCount == 0 {
            self.summaryText = "\(totalAssetCount) \(totalAssetCount == 1 ? "photograph" : "photographs") without capture dates"
        } else if totalAssetCount > loadedAssets.count {
            self.summaryText = "Showing \(loadedAssets.count) loaded of \(totalAssetCount) photographs across \(dayCount) \(dayCount == 1 ? "day" : "days")"
        } else {
            self.summaryText = "\(totalAssetCount) \(totalAssetCount == 1 ? "photograph" : "photographs") across \(dayCount) \(dayCount == 1 ? "day" : "days")"
        }
    }

    private static func focusedMonthID(
        timelineDays: [CatalogTimelineDay],
        loadedAssets: [Asset],
        calendar: Calendar
    ) -> String? {
        if let capturedAt = loadedAssets.compactMap({ $0.technicalMetadata?.capturedAt }).first {
            return TimelineMonthKey(date: capturedAt, calendar: calendar).id
        }
        if let firstDay = timelineDays.first {
            return TimelineMonthKey(day: firstDay).id
        }
        return nil
    }

    private static func focusedDayID(
        timelineDays: [CatalogTimelineDay],
        loadedAssets: [Asset],
        calendar: Calendar
    ) -> String? {
        if let capturedAt = loadedAssets.compactMap({ $0.technicalMetadata?.capturedAt }).first {
            return TimelineDayKey(date: capturedAt, calendar: calendar).id
        }
        return timelineDays.first?.id
    }

    private static func scrubber(
        for months: [TimelineMonthPresentation],
        focusedMonthID: String?,
        focusedDayID: String?
    ) -> TimelineScrubberPresentation {
        let focusedMonth = months.first { $0.id == focusedMonthID }
            ?? months.first { $0.year != nil && $0.month != nil }
        let scrubberMonths = months.compactMap { month -> TimelineScrubberMonthPresentation? in
            guard let year = month.year,
                  let monthNumber = month.month else {
                return nil
            }
            return TimelineScrubberMonthPresentation(
                title: month.title,
                year: year,
                month: monthNumber,
                assetCount: month.assetCount,
                dayCount: month.dayCount,
                isFocused: month.id == focusedMonth?.id
            )
        }
        let days = focusedMonth?.days.compactMap { day -> TimelineScrubberDayPresentation? in
            guard let timelineDay = day.timelineDay else { return nil }
            return TimelineScrubberDayPresentation(
                title: day.title,
                assetCount: day.assetCount,
                timelineDay: timelineDay,
                isFocused: timelineDay.id == focusedDayID
            )
        } ?? []
        let focusedDayTitle = days.first(where: \.isFocused)?.title
        let focusText = [focusedMonth?.title, focusedDayTitle]
            .compactMap { $0 }
            .joined(separator: " / ")
        return TimelineScrubberPresentation(
            months: scrubberMonths,
            days: days,
            focusText: focusText.isEmpty ? nil : focusText
        )
    }

    private static func yearRibbon(
        for timelineDays: [CatalogTimelineDay],
        loadedAssets: [Asset],
        totalAssetCount: Int,
        calendar: Calendar
    ) -> TimelineYearRibbonPresentation {
        var countsByYear: [Int: Int] = [:]
        for day in timelineDays {
            countsByYear[day.year, default: 0] += day.assetCount
        }
        guard let firstYear = countsByYear.keys.min(),
              let lastYear = countsByYear.keys.max() else {
            return TimelineYearRibbonPresentation(years: [], rangeText: "No dates", summaryText: "No dated photographs", focusText: nil)
        }

        let focusedYear = loadedAssets.compactMap { asset -> Int? in
            guard let capturedAt = asset.technicalMetadata?.capturedAt else { return nil }
            return calendar.component(.year, from: capturedAt)
        }.max() ?? lastYear
        let maxYearCount = max(countsByYear.values.max() ?? 0, 1)
        let years = (firstYear...lastYear).map { year in
            let count = countsByYear[year, default: 0]
            return TimelineYearPresentation(
                year: year,
                assetCount: count,
                heightRatio: Double(count) / Double(maxYearCount),
                tickText: year.isMultiple(of: 5) ? "\(year)" : "",
                isFocused: year == focusedYear
            )
        }
        let yearCount = years.count
        let summaryText = "\(totalAssetCount.formatted()) \(totalAssetCount == 1 ? "photograph" : "photographs") - \(yearCount) \(yearCount == 1 ? "year" : "years")"
        let focusCount = countsByYear[focusedYear, default: 0]
        let focusText = "\(focusedYear) - \(focusCount.formatted())"
        return TimelineYearRibbonPresentation(
            years: years,
            rangeText: "\(firstYear) - \(lastYear)",
            summaryText: summaryText,
            focusText: focusText
        )
    }

    private static func sortedAssets(_ assets: [Asset]) -> [Asset] {
        assets.sorted { lhs, rhs in
            switch (lhs.technicalMetadata?.capturedAt, rhs.technicalMetadata?.capturedAt) {
            case (.some(let lhsDate), .some(let rhsDate)):
                return lhsDate > rhsDate
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs.originalURL.lastPathComponent.localizedStandardCompare(rhs.originalURL.lastPathComponent) == .orderedAscending
            }
        }
    }

    private static func timelineDays(from assets: [Asset], calendar: Calendar) -> [CatalogTimelineDay] {
        let sortedAssets = Self.sortedAssets(assets)
        var dayOrder: [TimelineDayKey] = []
        var countsByDay: [TimelineDayKey: Int] = [:]
        for asset in sortedAssets {
            guard asset.technicalMetadata?.capturedAt != nil else { continue }
            let key = TimelineDayKey(date: asset.technicalMetadata?.capturedAt, calendar: calendar)
            if countsByDay[key] == nil {
                dayOrder.append(key)
            }
            countsByDay[key, default: 0] += 1
        }
        return dayOrder.compactMap { key in
            guard let year = key.year,
                  let month = key.month,
                  let day = key.day,
                  let assetCount = countsByDay[key] else {
                return nil
            }
            return CatalogTimelineDay(year: year, month: month, day: day, assetCount: assetCount)
        }
    }

    private static func months(
        for timelineDays: [CatalogTimelineDay],
        loadedAssets: [Asset],
        calendar: Calendar
    ) -> [TimelineMonthPresentation] {
        let assetsByDay = Dictionary(grouping: loadedAssets.filter { $0.technicalMetadata?.capturedAt != nil }) { asset in
            TimelineDayKey(date: asset.technicalMetadata?.capturedAt, calendar: calendar)
        }
        var monthOrder: [TimelineMonthKey] = []
        var daysByMonth: [TimelineMonthKey: [TimelineDayPresentation]] = [:]

        for day in timelineDays {
            let monthKey = TimelineMonthKey(day: day)
            if daysByMonth[monthKey] == nil {
                monthOrder.append(monthKey)
            }
            let dayKey = TimelineDayKey(day: day)
            daysByMonth[monthKey, default: []].append(TimelineDayPresentation(
                key: dayKey,
                assetCount: day.assetCount,
                assets: assetsByDay[dayKey] ?? [],
                timelineDay: day
            ))
        }

        let undatedAssets = loadedAssets.filter { $0.technicalMetadata?.capturedAt == nil }
        if !undatedAssets.isEmpty {
            let undatedMonth = TimelineMonthKey(date: nil, calendar: calendar)
            if daysByMonth[undatedMonth] == nil {
                monthOrder.append(undatedMonth)
            }
            let undatedDay = TimelineDayKey(date: nil, calendar: calendar)
            daysByMonth[undatedMonth, default: []].append(TimelineDayPresentation(
                key: undatedDay,
                assetCount: undatedAssets.count,
                assets: undatedAssets,
                timelineDay: nil
            ))
        }

        return monthOrder.compactMap { monthKey in
            guard let days = daysByMonth[monthKey] else { return nil }
            return TimelineMonthPresentation(key: monthKey, days: days)
        }
    }
}

struct TimelineYearRibbonPresentation: Equatable {
    var years: [TimelineYearPresentation]
    var rangeText: String
    var summaryText: String
    var focusText: String?
}

struct TimelineScrubberPresentation: Equatable {
    var months: [TimelineScrubberMonthPresentation]
    var days: [TimelineScrubberDayPresentation]
    var focusText: String?
}

struct TimelineScrubberMonthPresentation: Identifiable, Equatable {
    var id: String
    var title: String
    var year: Int
    var month: Int
    var assetCount: Int
    var dayCount: Int
    var countText: String
    var isFocused: Bool

    init(title: String, year: Int, month: Int, assetCount: Int, dayCount: Int, isFocused: Bool) {
        self.id = "\(year)-\(String(format: "%02d", month))"
        self.title = title
        self.year = year
        self.month = month
        self.assetCount = assetCount
        self.dayCount = dayCount
        self.countText = "\(assetCount) \(assetCount == 1 ? "photo" : "photos") / \(dayCount) \(dayCount == 1 ? "day" : "days")"
        self.isFocused = isFocused
    }
}

struct TimelineScrubberDayPresentation: Identifiable, Equatable {
    var id: String
    var title: String
    var assetCount: Int
    var countText: String
    var timelineDay: CatalogTimelineDay
    var isFocused: Bool

    init(title: String, assetCount: Int, timelineDay: CatalogTimelineDay, isFocused: Bool) {
        self.id = timelineDay.id
        self.title = title
        self.assetCount = assetCount
        self.countText = "\(assetCount)"
        self.timelineDay = timelineDay
        self.isFocused = isFocused
    }
}

struct TimelineYearPresentation: Identifiable, Equatable {
    var id: String
    var year: Int
    var assetCount: Int
    var heightRatio: Double
    var tickText: String
    var isFocused: Bool

    init(year: Int, assetCount: Int, heightRatio: Double, tickText: String, isFocused: Bool) {
        self.id = "\(year)"
        self.year = year
        self.assetCount = assetCount
        self.heightRatio = heightRatio
        self.tickText = tickText
        self.isFocused = isFocused
    }
}

struct TimelineMonthPresentation: Identifiable, Equatable {
    var id: String
    var year: Int?
    var month: Int?
    var title: String
    var subtitle: String
    var assetCount: Int
    var dayCount: Int
    var days: [TimelineDayPresentation]

    init(key: TimelineMonthKey, days: [TimelineDayPresentation]) {
        self.id = key.id
        self.year = key.year
        self.month = key.month
        self.title = key.title
        self.days = days
        self.assetCount = days.reduce(0) { $0 + $1.assetCount }
        self.dayCount = days.count
        self.subtitle = "\(assetCount) \(assetCount == 1 ? "photograph" : "photographs") across \(dayCount) \(dayCount == 1 ? "day" : "days")"
    }
}

struct TimelineDayPresentation: Identifiable, Equatable {
    var id: String
    var title: String
    var assetCount: Int
    var countText: String
    var assets: [Asset]
    var timelineDay: CatalogTimelineDay?

    init(key: TimelineDayKey, assetCount: Int, assets: [Asset], timelineDay: CatalogTimelineDay?) {
        self.id = key.id
        self.title = key.title
        self.assetCount = assetCount
        self.assets = assets
        self.timelineDay = timelineDay
        self.countText = "\(assetCount) \(assetCount == 1 ? "frame" : "frames")"
    }
}

struct TimelineMonthKey: Hashable {
    var year: Int?
    var month: Int?

    init(day: CatalogTimelineDay) {
        self.year = day.year
        self.month = day.month
    }

    init(date: Date?, calendar: Calendar) {
        guard let date else {
            self.year = nil
            self.month = nil
            return
        }
        self.year = calendar.component(.year, from: date)
        self.month = calendar.component(.month, from: date)
    }

    var id: String {
        guard let year, let month else { return "undated" }
        return "\(year)-\(String(format: "%02d", month))"
    }

    var title: String {
        guard let year, let month else { return "No Capture Date" }
        return "\(Self.monthName(month)) \(year)"
    }

    fileprivate static func monthName(_ month: Int) -> String {
        guard (1...12).contains(month) else { return "Month \(month)" }
        return [
            "January",
            "February",
            "March",
            "April",
            "May",
            "June",
            "July",
            "August",
            "September",
            "October",
            "November",
            "December"
        ][month - 1]
    }
}

struct TimelineDayKey: Hashable {
    var year: Int?
    var month: Int?
    var day: Int?

    init(day: CatalogTimelineDay) {
        self.year = day.year
        self.month = day.month
        self.day = day.day
    }

    init(date: Date?, calendar: Calendar) {
        guard let date else {
            self.year = nil
            self.month = nil
            self.day = nil
            return
        }
        self.year = calendar.component(.year, from: date)
        self.month = calendar.component(.month, from: date)
        self.day = calendar.component(.day, from: date)
    }

    var id: String {
        guard let year, let month, let day else { return "undated" }
        return "\(year)-\(String(format: "%02d", month))-\(String(format: "%02d", day))"
    }

    var title: String {
        guard let month, let day else { return "Undated" }
        return "\(TimelineMonthKey.monthName(month)) \(day)"
    }
}
