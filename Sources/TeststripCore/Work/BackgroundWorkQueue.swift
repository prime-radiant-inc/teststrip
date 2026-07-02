import Foundation

public struct BackgroundWorkItem: Codable, Equatable, Sendable {
    public var id: WorkSessionID
    public var kind: WorkSessionKind
    public var title: String
    public var detail: String
    public var status: WorkSessionStatus
    public var completedUnitCount: Int
    public var totalUnitCount: Int?

    public init(
        id: WorkSessionID,
        kind: WorkSessionKind,
        title: String,
        detail: String,
        status: WorkSessionStatus = .queued,
        completedUnitCount: Int,
        totalUnitCount: Int?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.status = status
        self.completedUnitCount = completedUnitCount
        self.totalUnitCount = totalUnitCount
    }
}

public struct BackgroundWorkQueue: Equatable, Sendable {
    public private(set) var maxRunningCount: Int
    public private(set) var items: [BackgroundWorkItem]
    public private(set) var isPaused: Bool

    public init(maxRunningCount: Int, items: [BackgroundWorkItem] = []) {
        self.maxRunningCount = max(1, maxRunningCount)
        self.items = items
        self.isPaused = false
    }

    public var runningItems: [BackgroundWorkItem] {
        items.filter { $0.status == .running }
    }

    public var queuedItems: [BackgroundWorkItem] {
        items.filter { $0.status == .queued }
    }

    public mutating func enqueue(_ item: BackgroundWorkItem) {
        items.append(item)
    }

    public func item(id: WorkSessionID) -> BackgroundWorkItem? {
        items.first { $0.id == id }
    }

    public mutating func activateRunnableItems() {
        guard !isPaused else { return }

        for index in items.indices where items[index].status == .paused {
            items[index].status = .queued
        }

        while runningItems.count < maxRunningCount, let index = items.firstIndex(where: { $0.status == .queued }) {
            items[index].status = .running
        }
    }

    public mutating func markCompleted(id: WorkSessionID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .completed
        activateRunnableItems()
    }

    public mutating func pause() {
        isPaused = true
        for index in items.indices where items[index].status == .running {
            items[index].status = .paused
        }
    }

    public mutating func resume() {
        isPaused = false
        activateRunnableItems()
    }

    public mutating func cancelAll() {
        isPaused = false
        for index in items.indices where [.queued, .running, .paused].contains(items[index].status) {
            items[index].status = .cancelled
        }
    }
}
