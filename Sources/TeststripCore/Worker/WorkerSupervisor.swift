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
            try send(command)
            dispatchedItemIDs.append(item.id)
        }
    }

    private func ensureRunning() throws {
        if !transport.isRunning {
            try transport.launch()
        }
    }

    private func send(_ command: WorkerCommand) throws {
        try transport.writeLine(try WorkerProtocolEncoder.encode(command))
    }

    private func handleOutputLine(_ line: String) {
        guard line.hasPrefix("completed "), !dispatchedItemIDs.isEmpty else {
            return
        }
        let itemID = dispatchedItemIDs.removeFirst()
        commandsByItemID[itemID] = nil
        queue.markCompleted(id: itemID)
        try? dispatchRunnableItems()
        notifyQueueChanged()
    }

    private func notifyQueueChanged() {
        onQueueChanged?(queue)
    }
}
