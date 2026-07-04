import Foundation

public struct BenchmarkSummary: Codable, Equatable {
    public static let machineReadablePrefix = "benchmark-summary\t"

    public var benchmark: String
    public var count: Int
    public var metrics: [String: Int]
    public var measurements: [String: Double]

    public init(
        benchmark: String,
        count: Int,
        metrics: [String: Int] = [:],
        measurements: [String: Double] = [:]
    ) {
        self.benchmark = benchmark
        self.count = count
        self.metrics = metrics
        self.measurements = measurements
    }

    public func machineReadableLine() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(self)
        guard let payload = String(data: data, encoding: .utf8) else {
            throw TeststripBenchError.encoding("could not encode benchmark summary")
        }
        return Self.machineReadablePrefix + payload
    }
}

public enum TeststripBenchError: Error, LocalizedError, Equatable {
    case encoding(String)

    public var errorDescription: String? {
        switch self {
        case .encoding(let message):
            return message
        }
    }
}

public struct BenchmarkSummaryRecorder {
    private var benchmark: String
    private var count: Int
    private var metrics: [String: Int]
    private var measurements: [String: Double]

    public init(benchmark: String, count: Int) {
        self.benchmark = benchmark
        self.count = count
        self.metrics = [:]
        self.measurements = [:]
    }

    public var summary: BenchmarkSummary {
        BenchmarkSummary(
            benchmark: benchmark,
            count: count,
            metrics: metrics,
            measurements: measurements
        )
    }

    public mutating func recordMetric(_ name: String, _ value: Int) {
        metrics[name] = value
    }

    public mutating func recordMeasurement(_ name: String, _ elapsed: TimeInterval) {
        measurements[name] = elapsed
    }

    @discardableResult
    public mutating func measure<T>(_ name: String, work: () throws -> T) rethrows -> T {
        let start = Date()
        let value = try work()
        recordMeasurement(name, Date().timeIntervalSince(start))
        return value
    }
}
