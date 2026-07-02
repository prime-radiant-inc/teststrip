import Foundation

public final class WorkerSupervisor: @unchecked Sendable {
    public private(set) var queue: BackgroundWorkQueue
    public var onQueueChanged: ((BackgroundWorkQueue) -> Void)?

    private let transport: WorkerTransport
    private var commandsByItemID: [WorkSessionID: WorkerCommand]
    private var dispatchedItemIDs: [WorkSessionID]

    public init(
        queue: BackgroundWorkQueue = BackgroundWorkQueue(maxRunningCount: 2),
        transport: WorkerTransport
    ) {
        self.queue = queue
        self.transport = transport
        self.commandsByItemID = [:]
        self.dispatchedItemIDs = []
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
        notifyQueueChanged()
        if let sendError {
            throw sendError
        }
    }

    private func dispatchRunnableItems() throws {
        for item in queue.runningItems where !dispatchedItemIDs.contains(item.id) {
            guard let command = commandsByItemID[item.id] else {
                throw TeststripError.invalidState("missing worker command for \(item.id.rawValue)")
            }
            try ensureRunning()
            try send(command, itemID: item.id)
            dispatchedItemIDs.append(item.id)
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
        case .completed(let itemID, _):
            guard let itemID else { return }
            completeDispatchedItem(id: itemID)
        case .failed(let itemID, let message):
            guard let itemID else { return }
            failDispatchedItem(id: itemID, detail: message)
        }
    }

    private func completeDispatchedItem(id itemID: WorkSessionID) {
        guard dispatchedItemIDs.contains(itemID) else { return }
        dispatchedItemIDs.removeAll { $0 == itemID }
        commandsByItemID[itemID] = nil
        queue.markCompleted(id: itemID)
        try? dispatchRunnableItems()
        notifyQueueChanged()
    }

    private func failDispatchedItem(id itemID: WorkSessionID, detail: String) {
        guard dispatchedItemIDs.contains(itemID) else { return }
        dispatchedItemIDs.removeAll { $0 == itemID }
        commandsByItemID[itemID] = nil
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
        queue.markFailed(id: itemID, detail: line)
        try? dispatchRunnableItems()
        notifyQueueChanged()
    }

    private func notifyQueueChanged() {
        onQueueChanged?(queue)
    }
}
