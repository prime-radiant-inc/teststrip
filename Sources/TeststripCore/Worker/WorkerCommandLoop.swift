import Foundation

/// Runs worker commands received on stdin concurrently and serializes their
/// output. Each submitted command is dispatched onto a background queue that runs
/// commands in parallel, so a slow command (a long preview render, a rate-limited
/// geocode) never blocks a command in another lane. The supervisor guarantees at
/// most one in-flight command per lane, so the loop needs no per-lane bookkeeping.
///
/// `writeLine` is the single serialized sink every stdout line must pass through
/// (both the terminal event returned here and the `.progress` events the `execute`
/// closure emits inline), so concurrently finishing commands never interleave a
/// partial line.
public final class WorkerCommandLoop: @unchecked Sendable {
    private let execute: @Sendable (WorkerCommandRequest) -> String
    private let writeLine: @Sendable (String) -> Void
    private let queue: DispatchQueue
    private let inFlight = DispatchGroup()

    public init(
        execute: @escaping @Sendable (WorkerCommandRequest) -> String,
        writeLine: @escaping @Sendable (String) -> Void
    ) {
        self.execute = execute
        self.writeLine = writeLine
        self.queue = DispatchQueue(label: "com.teststrip.worker.command-loop", attributes: .concurrent)
    }

    /// Hands a decoded command to a background worker and returns immediately so
    /// the reader can go on receiving the next command.
    public func submit(_ request: WorkerCommandRequest) {
        inFlight.enter()
        queue.async { [execute, writeLine, inFlight] in
            defer { inFlight.leave() }
            writeLine(execute(request))
        }
    }

    /// Blocks until every submitted command has finished and its output has been
    /// written. The worker calls this after stdin closes so no output is lost to
    /// an early exit.
    public func drain() {
        inFlight.wait()
    }
}
