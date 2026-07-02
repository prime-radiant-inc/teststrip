import Foundation

public final class WorkerSupervisor {
    public private(set) var queue: BackgroundWorkQueue

    private let transport: WorkerTransport
    private var commandsByItemID: [WorkSessionID: WorkerCommand]
    private var dispatchedItemIDs: Set<WorkSessionID>

    public init(
        queue: BackgroundWorkQueue = BackgroundWorkQueue(maxRunningCount: 2),
        transport: WorkerTransport
    ) {
        self.queue = queue
        self.transport = transport
        self.commandsByItemID = [:]
        self.dispatchedItemIDs = []
    }

    public func enqueue(_ item: BackgroundWorkItem, command: WorkerCommand) throws {
        commandsByItemID[item.id] = command
        queue.enqueue(item)
        queue.activateRunnableItems()
        try dispatchRunnableItems()
    }

    public func markCompleted(id: WorkSessionID) throws {
        commandsByItemID[id] = nil
        dispatchedItemIDs.remove(id)
        queue.markCompleted(id: id)
        try dispatchRunnableItems()
    }

    public func pause() throws {
        if transport.isRunning {
            try send(.pause)
        }
        queue.pause()
    }

    public func resume() throws {
        if transport.isRunning {
            try send(.resume)
        }
        queue.resume()
        try dispatchRunnableItems()
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
            dispatchedItemIDs.insert(item.id)
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
}
