import Foundation

public protocol WorkerTimeoutCancellation: Sendable {
    func cancel()
}

public protocol WorkerTimeoutScheduling: Sendable {
    func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any WorkerTimeoutCancellation
}

public struct DispatchWorkerTimeoutScheduler: WorkerTimeoutScheduling {
    public init() {}

    public func schedule(after interval: TimeInterval, _ action: @escaping @Sendable () -> Void) -> any WorkerTimeoutCancellation {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval)
        timer.setEventHandler(handler: action)
        timer.resume()
        return DispatchWorkerTimeoutCancellation(timer: timer)
    }
}

private final class DispatchWorkerTimeoutCancellation: WorkerTimeoutCancellation, @unchecked Sendable {
    private let timer: DispatchSourceTimer

    init(timer: DispatchSourceTimer) {
        self.timer = timer
    }

    func cancel() {
        timer.cancel()
    }
}

public final class WorkerSupervisor: @unchecked Sendable {
    public private(set) var queue: BackgroundWorkQueue
    public var onQueueChanged: ((BackgroundWorkQueue) -> Void)?
    public var onCommandCompleted: ((WorkerEvent) -> Void)?

    private let transport: WorkerTransport
    private let commandTimeout: TimeInterval?
    private let timeoutScheduler: any WorkerTimeoutScheduling
    private let maxDispatchedCommandCount: Int
    private var commandsByItemID: [WorkSessionID: WorkerCommand]
    private var dispatchedItemIDs: [WorkSessionID]
    private var timeoutsByItemID: [WorkSessionID: any WorkerTimeoutCancellation]

    public init(
        queue: BackgroundWorkQueue = BackgroundWorkQueue(maxRunningCount: 2),
        transport: WorkerTransport,
        commandTimeout: TimeInterval? = 120,
        timeoutScheduler: any WorkerTimeoutScheduling = DispatchWorkerTimeoutScheduler(),
        maxDispatchedCommandCount: Int = 1
    ) {
        precondition(maxDispatchedCommandCount > 0, "maxDispatchedCommandCount must be positive")
        self.queue = queue
        self.transport = transport
        self.commandTimeout = commandTimeout
        self.timeoutScheduler = timeoutScheduler
        self.maxDispatchedCommandCount = maxDispatchedCommandCount
        self.commandsByItemID = [:]
        self.dispatchedItemIDs = []
        self.timeoutsByItemID = [:]
        self.transport.outputHandler = { [weak self] line in
            DispatchQueue.main.async { [weak self] in
                self?.handleOutputLine(line)
            }
        }
        self.transport.errorHandler = { [weak self] line in
            DispatchQueue.main.async { [weak self] in
                self?.handleErrorLine(line)
            }
        }
    }

    public func enqueue(_ item: BackgroundWorkItem, command: WorkerCommand) throws {
        commandsByItemID[item.id] = command
        queue.enqueue(item)
        queue.activateRunnableItems()
        try dispatchRunnableItems()
        notifyQueueChanged()
    }

    public func markCompleted(id: WorkSessionID) throws {
        commandsByItemID[id] = nil
        dispatchedItemIDs.removeAll { $0 == id }
        cancelTimeout(for: id)
        queue.markCompleted(id: id)
        try dispatchRunnableItems()
        notifyQueueChanged()
    }

    public func pause() throws {
        if transport.isRunning {
            try send(.pause)
        }
        queue.pause()
        notifyQueueChanged()
    }

    public func resume() throws {
        if transport.isRunning {
            try send(.resume)
        }
        queue.resume()
        scheduleTimeoutsForDispatchedRunningItems()
        try dispatchRunnableItems()
        notifyQueueChanged()
    }

    public func cancelAll() throws {
        var sendError: Error?
        if transport.isRunning {
            do {
                try send(.cancelAll)
            } catch {
                sendError = error
            }
            transport.terminate()
        }
        queue.cancelAll()
        commandsByItemID.removeAll()
        dispatchedItemIDs.removeAll()
        cancelAllTimeouts()
        notifyQueueChanged()
        if let sendError {
            throw sendError
        }
    }

    private func dispatchRunnableItems() throws {
        for item in queue.runningItems where !dispatchedItemIDs.contains(item.id) {
            guard dispatchedItemIDs.count < maxDispatchedCommandCount else {
                return
            }
            guard let command = commandsByItemID[item.id] else {
                throw TeststripError.invalidState("missing worker command for \(item.id.rawValue)")
            }
            try ensureRunning()
            try send(command, itemID: item.id)
            dispatchedItemIDs.append(item.id)
            scheduleTimeout(for: item.id)
        }
    }

    private func ensureRunning() throws {
        if !transport.isRunning {
            try transport.launch()
        }
    }

    private func send(_ command: WorkerCommand, itemID: WorkSessionID? = nil) throws {
        try transport.writeLine(try WorkerProtocolEncoder.encode(command, itemID: itemID))
    }

    private func handleOutputLine(_ line: String) {
        guard let event = try? WorkerProtocolEncoder.decodeEvent(line) else {
            return
        }

        switch event {
        case .accepted:
            return
        case .progress(let itemID, let completedUnitCount, let totalUnitCount, let detail):
            guard let itemID else { return }
            updateDispatchedItemProgress(
                id: itemID,
                completedUnitCount: completedUnitCount,
                totalUnitCount: totalUnitCount,
                detail: detail
            )
        case .completed(let itemID, let message):
            guard let itemID else { return }
            completeDispatchedItem(id: itemID, detail: message, event: event)
        case .completedImport(let itemID, let message, _):
            guard let itemID else { return }
            completeDispatchedItem(id: itemID, detail: message, event: event)
        case .failed(let itemID, let message):
            guard let itemID else { return }
            failDispatchedItem(id: itemID, detail: message)
        }
    }

    private func updateDispatchedItemProgress(id itemID: WorkSessionID, completedUnitCount: Int, totalUnitCount: Int?, detail: String) {
        guard dispatchedItemIDs.contains(itemID) else { return }
        queue.updateProgress(
            id: itemID,
            completedUnitCount: completedUnitCount,
            totalUnitCount: totalUnitCount,
            detail: detail
        )
        scheduleTimeout(for: itemID)
        notifyQueueChanged()
    }

    private func completeDispatchedItem(id itemID: WorkSessionID, detail: String, event: WorkerEvent) {
        guard dispatchedItemIDs.contains(itemID) else { return }
        dispatchedItemIDs.removeAll { $0 == itemID }
        commandsByItemID[itemID] = nil
        cancelTimeout(for: itemID)
        queue.markCompleted(id: itemID, detail: detail)
        try? dispatchRunnableItems()
        notifyQueueChanged()
        onCommandCompleted?(event)
    }

    private func failDispatchedItem(id itemID: WorkSessionID, detail: String) {
        guard dispatchedItemIDs.contains(itemID) else { return }
        dispatchedItemIDs.removeAll { $0 == itemID }
        commandsByItemID[itemID] = nil
        cancelTimeout(for: itemID)
        queue.markFailed(id: itemID, detail: detail)
        try? dispatchRunnableItems()
        notifyQueueChanged()
    }

    private func handleErrorLine(_ line: String) {
        guard !dispatchedItemIDs.isEmpty else {
            return
        }
        let itemID = dispatchedItemIDs.removeFirst()
        commandsByItemID[itemID] = nil
        cancelTimeout(for: itemID)
        queue.markFailed(id: itemID, detail: line)
        try? dispatchRunnableItems()
        notifyQueueChanged()
    }

    private func scheduleTimeout(for itemID: WorkSessionID) {
        guard let commandTimeout else { return }
        cancelTimeout(for: itemID)
        timeoutsByItemID[itemID] = timeoutScheduler.schedule(after: commandTimeout) { [weak self] in
            self?.handleCommandTimeout(itemID: itemID, timeout: commandTimeout)
        }
    }

    private func scheduleTimeoutIfNeeded(for itemID: WorkSessionID) {
        guard timeoutsByItemID[itemID] == nil else { return }
        scheduleTimeout(for: itemID)
    }

    private func scheduleTimeoutsForDispatchedRunningItems() {
        for itemID in dispatchedItemIDs where queue.item(id: itemID)?.status == .running {
            scheduleTimeoutIfNeeded(for: itemID)
        }
    }

    private func cancelTimeout(for itemID: WorkSessionID) {
        timeoutsByItemID[itemID]?.cancel()
        timeoutsByItemID[itemID] = nil
    }

    private func cancelAllTimeouts() {
        for timeout in timeoutsByItemID.values {
            timeout.cancel()
        }
        timeoutsByItemID.removeAll()
    }

    private func handleCommandTimeout(itemID: WorkSessionID, timeout: TimeInterval) {
        guard dispatchedItemIDs.contains(itemID) else { return }
        let timedOutItemIDs = dispatchedItemIDs
        dispatchedItemIDs.removeAll()
        cancelAllTimeouts()
        transport.terminate()
        for timedOutItemID in timedOutItemIDs {
            commandsByItemID[timedOutItemID] = nil
            let detail = timedOutItemID == itemID
                ? "Worker command timed out after \(Self.timeoutText(timeout))"
                : "Worker stopped because another command timed out"
            queue.markFailed(id: timedOutItemID, detail: detail)
        }
        try? dispatchRunnableItems()
        notifyQueueChanged()
    }

    private static func timeoutText(_ timeout: TimeInterval) -> String {
        if timeout.rounded() == timeout {
            return "\(Int(timeout)) seconds"
        }
        return "\(timeout) seconds"
    }

    private func notifyQueueChanged() {
        onQueueChanged?(queue)
    }
}
