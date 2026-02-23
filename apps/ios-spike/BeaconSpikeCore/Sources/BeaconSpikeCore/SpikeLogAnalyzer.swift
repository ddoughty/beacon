import Foundation

public struct SpikeSignalLatencySummary: Sendable, Equatable {
    public let signalType: SpikeSignalType
    public let sampleCount: Int
    public let p50DelaySeconds: Double?
    public let p95DelaySeconds: Double?
    public let p99DelaySeconds: Double?
    public let maxDelaySeconds: Double?

    public init(
        signalType: SpikeSignalType,
        sampleCount: Int,
        p50DelaySeconds: Double?,
        p95DelaySeconds: Double?,
        p99DelaySeconds: Double?,
        maxDelaySeconds: Double?
    ) {
        self.signalType = signalType
        self.sampleCount = sampleCount
        self.p50DelaySeconds = p50DelaySeconds
        self.p95DelaySeconds = p95DelaySeconds
        self.p99DelaySeconds = p99DelaySeconds
        self.maxDelaySeconds = maxDelaySeconds
    }
}

public struct SpikeLogAnalysisSummary: Sendable, Equatable {
    public let totalEntries: Int
    public let transitionEntryCount: Int
    public let firstRecordedAt: Date?
    public let lastRecordedAt: Date?
    public let signalSummaries: [SpikeSignalLatencySummary]

    public init(
        totalEntries: Int,
        transitionEntryCount: Int,
        firstRecordedAt: Date?,
        lastRecordedAt: Date?,
        signalSummaries: [SpikeSignalLatencySummary]
    ) {
        self.totalEntries = totalEntries
        self.transitionEntryCount = transitionEntryCount
        self.firstRecordedAt = firstRecordedAt
        self.lastRecordedAt = lastRecordedAt
        self.signalSummaries = signalSummaries
    }

    public var hasVisitArrival: Bool {
        sampleCount(for: .clvisitArrival) > 0
    }

    public var hasVisitDeparture: Bool {
        sampleCount(for: .clvisitDeparture) > 0
    }

    public func sampleCount(for signalType: SpikeSignalType) -> Int {
        summary(for: signalType)?.sampleCount ?? 0
    }

    public func summary(for signalType: SpikeSignalType) -> SpikeSignalLatencySummary? {
        signalSummaries.first(where: { $0.signalType == signalType })
    }
}

public struct SpikeLogAnalyzer {
    private let parser: NDJSONSpikeLogParser

    public init(parser: NDJSONSpikeLogParser = NDJSONSpikeLogParser()) {
        self.parser = parser
    }

    public func analyze(fileURL: URL) throws -> SpikeLogAnalysisSummary {
        let entries = try parser.parse(fileURL: fileURL)
        return analyze(entries: entries)
    }

    public func analyze(entries: [SpikeLogEntry]) -> SpikeLogAnalysisSummary {
        let transitionEntries = entries.filter { $0.recordType == .transitionSample }
        let firstRecordedAt = entries.map(\.recordedAt).min()
        let lastRecordedAt = entries.map(\.recordedAt).max()

        let grouped = Dictionary(grouping: transitionEntries, by: { $0.sample.signalType })
        let signalSummaries = grouped.keys.sorted(by: { $0.rawValue < $1.rawValue }).map { signalType in
            let delays = grouped[signalType, default: []]
                .compactMap(Self.resolveDelaySeconds)
                .sorted()
            return SpikeSignalLatencySummary(
                signalType: signalType,
                sampleCount: grouped[signalType, default: []].count,
                p50DelaySeconds: delays.percentile(nearestRank: 0.50),
                p95DelaySeconds: delays.percentile(nearestRank: 0.95),
                p99DelaySeconds: delays.percentile(nearestRank: 0.99),
                maxDelaySeconds: delays.last
            )
        }

        return SpikeLogAnalysisSummary(
            totalEntries: entries.count,
            transitionEntryCount: transitionEntries.count,
            firstRecordedAt: firstRecordedAt,
            lastRecordedAt: lastRecordedAt,
            signalSummaries: signalSummaries
        )
    }

    private static func resolveDelaySeconds(entry: SpikeLogEntry) -> Double? {
        if let explicitDelay = entry.sample.delaySeconds, explicitDelay.isFinite {
            return max(0, explicitDelay)
        }
        guard let callbackAt = entry.sample.callbackReceivedAt,
              let eventAt = entry.sample.eventOccurredAt
        else {
            return nil
        }
        let derivedDelay = callbackAt.timeIntervalSince(eventAt)
        guard derivedDelay.isFinite else {
            return nil
        }
        return max(0, derivedDelay)
    }
}

private extension [Double] {
    func percentile(nearestRank percentile: Double) -> Double? {
        guard !isEmpty else {
            return nil
        }
        let clamped = Swift.min(Swift.max(percentile, 0), 1)
        let rank = Int(ceil(clamped * Double(count)))
        let index = Swift.max(0, Swift.min(count - 1, rank - 1))
        return self[index]
    }
}
