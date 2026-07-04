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

public enum BackgroundWorkQueuePlacement: Equatable, Sendable {
    case back
    case front
}

public struct BackgroundWorkQueue: Equatable, Sendable {
    public private(set) var maxRunningCount: Int
    public private(set) var kindRunningLimits: [WorkSessionKind: Int]
    public private(set) var items: [BackgroundWorkItem]
    public private(set) var isPaused: Bool

    public init(maxRunningCount: Int, kindRunningLimits: [WorkSessionKind: Int] = [:], items: [BackgroundWorkItem] = []) {
        self.maxRunningCount = max(1, maxRunningCount)
        self.kindRunningLimits = kindRunningLimits.mapValues { max(1, $0) }
        self.items = items
        self.isPaused = false
    }

    public var runningItems: [BackgroundWorkItem] {
        items.filter { $0.status == .running }
    }

    public var queuedItems: [BackgroundWorkItem] {
        items.filter { $0.status == .queued }
    }

    public mutating func enqueue(_ item: BackgroundWorkItem, placement: BackgroundWorkQueuePlacement = .back) {
        if placement == .front, let firstQueuedIndex = items.firstIndex(where: { $0.status == .queued }) {
            items.insert(item, at: firstQueuedIndex)
            return
        }
        items.append(item)
    }

    public func item(id: WorkSessionID) -> BackgroundWorkItem? {
        items.first { $0.id == id }
    }

    @discardableResult
    public mutating func promoteQueuedItem(id: WorkSessionID) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id && $0.status == .queued }) else {
            return false
        }
        let item = items.remove(at: index)
        if let firstQueuedIndex = items.firstIndex(where: { $0.status == .queued }) {
            items.insert(item, at: firstQueuedIndex)
        } else {
            items.append(item)
        }
        return true
    }

    public mutating func activateRunnableItems() {
        guard !isPaused else { return }

        for index in items.indices where items[index].status == .paused {
            items[index].status = .queued
        }

        while runningItems.count < maxRunningCount, let index = items.firstIndex(where: { $0.status == .queued && canRun($0) }) {
            items[index].status = .running
        }
    }

    public mutating func markCompleted(id: WorkSessionID, detail: String? = nil) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .completed
        if let detail {
            items[index].detail = detail
        }
        if let totalUnitCount = items[index].totalUnitCount {
            items[index].completedUnitCount = totalUnitCount
        }
        activateRunnableItems()
    }

    public mutating func pruneCompletedItems(kind: WorkSessionKind, keepingLast retainedCount: Int = 0) {
        var remainingRetainedItems = max(0, retainedCount)
        let prunedItems = items.reversed().filter { item in
            guard item.kind == kind && item.status == .completed else { return true }
            guard remainingRetainedItems > 0 else { return false }
            remainingRetainedItems -= 1
            return true
        }
        items = Array(prunedItems.reversed())
    }

    public mutating func updateProgress(id: WorkSessionID, completedUnitCount: Int, totalUnitCount: Int?, detail: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].completedUnitCount = completedUnitCount
        items[index].totalUnitCount = totalUnitCount
        items[index].detail = detail
    }

    public mutating func markFailed(id: WorkSessionID, detail: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].status = .failed
        items[index].detail = detail
        activateRunnableItems()
    }

    public mutating func pause() {
        isPaused = true
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

    public mutating func cancel(id: WorkSessionID) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              [.queued, .running, .paused].contains(items[index].status) else {
            return
        }
        items[index].status = .cancelled
        activateRunnableItems()
    }

    private func canRun(_ item: BackgroundWorkItem) -> Bool {
        guard let kindLimit = kindRunningLimits[item.kind] else { return true }
        return runningItems.filter { $0.kind == item.kind }.count < kindLimit
    }
}
