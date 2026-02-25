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

public struct SpikeHybridFastPathSummary: Sendable, Equatable {
    public let stageMetadataPresent: Bool
    public let confirmationLinkagePresent: Bool
    public let provisionalTransitionsEmitted: Int
    public let provisionalTransitionsConfirmed: Int?
    public let provisionalConfirmationRatePercent: Double?
    public let provisionalP50DetectionSeconds: Double?
    public let provisionalP95DetectionSeconds: Double?
    public let confirmationP95Seconds: Double?
    public let shortStopFalsePositives: Int?
    public let shortStopObservationCount: Int?

    public init(
        stageMetadataPresent: Bool,
        confirmationLinkagePresent: Bool,
        provisionalTransitionsEmitted: Int,
        provisionalTransitionsConfirmed: Int?,
        provisionalConfirmationRatePercent: Double?,
        provisionalP50DetectionSeconds: Double?,
        provisionalP95DetectionSeconds: Double?,
        confirmationP95Seconds: Double?,
        shortStopFalsePositives: Int?,
        shortStopObservationCount: Int?
    ) {
        self.stageMetadataPresent = stageMetadataPresent
        self.confirmationLinkagePresent = confirmationLinkagePresent
        self.provisionalTransitionsEmitted = provisionalTransitionsEmitted
        self.provisionalTransitionsConfirmed = provisionalTransitionsConfirmed
        self.provisionalConfirmationRatePercent = provisionalConfirmationRatePercent
        self.provisionalP50DetectionSeconds = provisionalP50DetectionSeconds
        self.provisionalP95DetectionSeconds = provisionalP95DetectionSeconds
        self.confirmationP95Seconds = confirmationP95Seconds
        self.shortStopFalsePositives = shortStopFalsePositives
        self.shortStopObservationCount = shortStopObservationCount
    }
}

public struct SpikeBackgroundWakeReliabilitySummary: Sendable, Equatable {
    public let backgroundOpportunities: Int
    public let backgroundCallbacks: Int
    public let suspendedOpportunities: Int
    public let suspendedCallbacks: Int
    public let relaunchOpportunities: Int
    public let relaunchCallbacks: Int

    public init(
        backgroundOpportunities: Int,
        backgroundCallbacks: Int,
        suspendedOpportunities: Int,
        suspendedCallbacks: Int,
        relaunchOpportunities: Int,
        relaunchCallbacks: Int
    ) {
        self.backgroundOpportunities = backgroundOpportunities
        self.backgroundCallbacks = backgroundCallbacks
        self.suspendedOpportunities = suspendedOpportunities
        self.suspendedCallbacks = suspendedCallbacks
        self.relaunchOpportunities = relaunchOpportunities
        self.relaunchCallbacks = relaunchCallbacks
    }

    public func opportunityCount(for appState: SpikeAppState) -> Int {
        switch appState {
        case .foreground:
            return 0
        case .background:
            return backgroundOpportunities
        case .suspended:
            return suspendedOpportunities
        case .relaunch:
            return relaunchOpportunities
        }
    }

    public func callbackCount(for appState: SpikeAppState) -> Int {
        switch appState {
        case .foreground:
            return 0
        case .background:
            return backgroundCallbacks
        case .suspended:
            return suspendedCallbacks
        case .relaunch:
            return relaunchCallbacks
        }
    }

    public func reliabilityPercent(for appState: SpikeAppState) -> Double? {
        let opportunities = opportunityCount(for: appState)
        guard opportunities > 0 else {
            return nil
        }
        return (Double(callbackCount(for: appState)) / Double(opportunities)) * 100
    }
}

public struct SpikeLogAnalysisSummary: Sendable, Equatable {
    public let totalEntries: Int
    public let transitionEntryCount: Int
    public let firstRecordedAt: Date?
    public let lastRecordedAt: Date?
    public let signalSummaries: [SpikeSignalLatencySummary]
    public let hybridFastPath: SpikeHybridFastPathSummary
    public let backgroundWakeReliability: SpikeBackgroundWakeReliabilitySummary

    public init(
        totalEntries: Int,
        transitionEntryCount: Int,
        firstRecordedAt: Date?,
        lastRecordedAt: Date?,
        signalSummaries: [SpikeSignalLatencySummary],
        hybridFastPath: SpikeHybridFastPathSummary,
        backgroundWakeReliability: SpikeBackgroundWakeReliabilitySummary
    ) {
        self.totalEntries = totalEntries
        self.transitionEntryCount = transitionEntryCount
        self.firstRecordedAt = firstRecordedAt
        self.lastRecordedAt = lastRecordedAt
        self.signalSummaries = signalSummaries
        self.hybridFastPath = hybridFastPath
        self.backgroundWakeReliability = backgroundWakeReliability
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
    private let shortStopThresholdSeconds: TimeInterval

    public init(
        parser: NDJSONSpikeLogParser = NDJSONSpikeLogParser(),
        shortStopThresholdSeconds: TimeInterval = 15 * 60
    ) {
        self.parser = parser
        self.shortStopThresholdSeconds = shortStopThresholdSeconds
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
        let hybridFastPath = analyzeHybridFastPath(
            transitionEntries: transitionEntries,
            lastRecordedAt: lastRecordedAt
        )
        let backgroundWakeReliability = analyzeBackgroundWakeReliability(
            entries: entries,
            transitionEntries: transitionEntries
        )

        return SpikeLogAnalysisSummary(
            totalEntries: entries.count,
            transitionEntryCount: transitionEntries.count,
            firstRecordedAt: firstRecordedAt,
            lastRecordedAt: lastRecordedAt,
            signalSummaries: signalSummaries,
            hybridFastPath: hybridFastPath,
            backgroundWakeReliability: backgroundWakeReliability
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

    private func analyzeBackgroundWakeReliability(
        entries: [SpikeLogEntry],
        transitionEntries: [SpikeLogEntry]
    ) -> SpikeBackgroundWakeReliabilitySummary {
        let opportunityEntries = entries.filter { entry in
            entry.recordType == .sessionSummary &&
                entry.sample.signalType == .callbackOpportunity
        }

        var backgroundOpportunities = 0
        var suspendedOpportunities = 0
        var relaunchOpportunities = 0
        for entry in opportunityEntries {
            guard let opportunityType = Self.resolveOpportunityType(entry: entry) else {
                continue
            }
            switch opportunityType {
            case .backgroundWindow:
                backgroundOpportunities += 1
            case .suspendedWindow:
                suspendedOpportunities += 1
            case .relaunchWindow:
                relaunchOpportunities += 1
            }
        }

        return SpikeBackgroundWakeReliabilitySummary(
            backgroundOpportunities: backgroundOpportunities,
            backgroundCallbacks: Self.countObservedCallbacks(
                transitionEntries: transitionEntries,
                appState: .background
            ),
            suspendedOpportunities: suspendedOpportunities,
            suspendedCallbacks: Self.countObservedCallbacks(
                transitionEntries: transitionEntries,
                appState: .suspended
            ),
            relaunchOpportunities: relaunchOpportunities,
            relaunchCallbacks: Self.countObservedCallbacks(
                transitionEntries: transitionEntries,
                appState: .relaunch
            )
        )
    }

    private func analyzeHybridFastPath(
        transitionEntries: [SpikeLogEntry],
        lastRecordedAt: Date?
    ) -> SpikeHybridFastPathSummary {
        let stageMetadataPresent = transitionEntries.contains { entry in
            entry.sample.transitionStage != nil ||
                Self.normalizedTransitionID(entry.sample.transitionID) != nil ||
                Self.normalizedTransitionID(entry.sample.linkedProvisionalID) != nil
        }
        let provisionalEntries = transitionEntries.filter {
            Self.resolveTransitionStage(entry: $0) == .provisional
        }
        let provisionalDetectionDelays = provisionalEntries
            .compactMap(Self.resolveDelaySeconds)
            .sorted()
        let provisionalTransitionsEmitted = provisionalEntries.count

        guard stageMetadataPresent else {
            return SpikeHybridFastPathSummary(
                stageMetadataPresent: false,
                confirmationLinkagePresent: false,
                provisionalTransitionsEmitted: provisionalTransitionsEmitted,
                provisionalTransitionsConfirmed: nil,
                provisionalConfirmationRatePercent: nil,
                provisionalP50DetectionSeconds: provisionalDetectionDelays.percentile(nearestRank: 0.50),
                provisionalP95DetectionSeconds: provisionalDetectionDelays.percentile(nearestRank: 0.95),
                confirmationP95Seconds: nil,
                shortStopFalsePositives: nil,
                shortStopObservationCount: nil
            )
        }

        var provisionalByID: [String: SpikeLogEntry] = [:]
        for entry in provisionalEntries {
            guard let transitionID = Self.normalizedTransitionID(entry.sample.transitionID) else {
                continue
            }
            let existing = provisionalByID[transitionID]
            let existingAt = existing.flatMap(Self.resolveCallbackTimestamp)
            let candidateAt = Self.resolveCallbackTimestamp(entry)
            if existing == nil || (candidateAt ?? .distantFuture) < (existingAt ?? .distantFuture) {
                provisionalByID[transitionID] = entry
            }
        }
        let knownProvisionalIDs = Set(provisionalByID.keys)

        let confirmedEntries = transitionEntries.filter {
            Self.resolveTransitionStage(entry: $0) == .confirmed
        }
        var earliestConfirmationAtByProvisionalID: [String: Date] = [:]
        for entry in confirmedEntries {
            guard let provisionalID = Self.resolveLinkedProvisionalID(
                forConfirmedEntry: entry,
                knownProvisionalIDs: knownProvisionalIDs
            ),
                let confirmedAt = Self.resolveCallbackTimestamp(entry)
            else {
                continue
            }
            if let existing = earliestConfirmationAtByProvisionalID[provisionalID], existing <= confirmedAt {
                continue
            }
            earliestConfirmationAtByProvisionalID[provisionalID] = confirmedAt
        }

        let confirmationLinkagePresent = !earliestConfirmationAtByProvisionalID.isEmpty
        guard confirmationLinkagePresent else {
            return SpikeHybridFastPathSummary(
                stageMetadataPresent: true,
                confirmationLinkagePresent: false,
                provisionalTransitionsEmitted: provisionalTransitionsEmitted,
                provisionalTransitionsConfirmed: 0,
                provisionalConfirmationRatePercent: provisionalTransitionsEmitted == 0 ? nil : 0,
                provisionalP50DetectionSeconds: provisionalDetectionDelays.percentile(nearestRank: 0.50),
                provisionalP95DetectionSeconds: provisionalDetectionDelays.percentile(nearestRank: 0.95),
                confirmationP95Seconds: nil,
                shortStopFalsePositives: nil,
                shortStopObservationCount: nil
            )
        }

        let confirmedProvisionalIDs = Set(earliestConfirmationAtByProvisionalID.keys)
        let provisionalTransitionsConfirmed = confirmedProvisionalIDs.count
        let confirmationRatePercent: Double?
        if provisionalTransitionsEmitted > 0 {
            confirmationRatePercent = (Double(provisionalTransitionsConfirmed) / Double(provisionalTransitionsEmitted)) * 100
        } else {
            confirmationRatePercent = nil
        }

        let confirmationDelays = confirmedProvisionalIDs.compactMap { provisionalID -> Double? in
            guard let provisionalEntry = provisionalByID[provisionalID],
                  let provisionalAt = Self.resolveCallbackTimestamp(provisionalEntry),
                  let confirmedAt = earliestConfirmationAtByProvisionalID[provisionalID]
            else {
                return nil
            }
            let delta = confirmedAt.timeIntervalSince(provisionalAt)
            guard delta.isFinite else {
                return nil
            }
            return max(0, delta)
        }.sorted()

        var shortStopObservationCount: Int?
        var shortStopFalsePositives: Int?
        if let windowEnd = lastRecordedAt {
            let observedProvisionalIDs = provisionalByID.keys.filter { provisionalID in
                guard let provisionalEntry = provisionalByID[provisionalID],
                      let provisionalAt = Self.resolveCallbackTimestamp(provisionalEntry)
                else {
                    return false
                }
                return windowEnd.timeIntervalSince(provisionalAt) >= shortStopThresholdSeconds
            }
            shortStopObservationCount = observedProvisionalIDs.count
            shortStopFalsePositives = observedProvisionalIDs.filter { provisionalID in
                !confirmedProvisionalIDs.contains(provisionalID)
            }.count
        }

        return SpikeHybridFastPathSummary(
            stageMetadataPresent: true,
            confirmationLinkagePresent: true,
            provisionalTransitionsEmitted: provisionalTransitionsEmitted,
            provisionalTransitionsConfirmed: provisionalTransitionsConfirmed,
            provisionalConfirmationRatePercent: confirmationRatePercent,
            provisionalP50DetectionSeconds: provisionalDetectionDelays.percentile(nearestRank: 0.50),
            provisionalP95DetectionSeconds: provisionalDetectionDelays.percentile(nearestRank: 0.95),
            confirmationP95Seconds: confirmationDelays.percentile(nearestRank: 0.95),
            shortStopFalsePositives: shortStopFalsePositives,
            shortStopObservationCount: shortStopObservationCount
        )
    }

    private static func resolveTransitionStage(entry: SpikeLogEntry) -> SpikeTransitionStage? {
        if let stage = entry.sample.transitionStage {
            return stage
        }
        switch entry.sample.signalType {
        case .significantLocationChange:
            return .provisional
        case .clvisitArrival, .clvisitDeparture:
            return .confirmed
        default:
            return nil
        }
    }

    private static func resolveOpportunityType(entry: SpikeLogEntry) -> SpikeCallbackOpportunityType? {
        if let explicitType = entry.sample.opportunityType {
            return explicitType
        }
        switch entry.device.appState {
        case .background:
            return .backgroundWindow
        case .suspended:
            return .suspendedWindow
        case .relaunch:
            return .relaunchWindow
        case .foreground:
            return nil
        }
    }

    private static func countObservedCallbacks(
        transitionEntries: [SpikeLogEntry],
        appState: SpikeAppState
    ) -> Int {
        var keys: Set<String> = []
        for entry in transitionEntries where entry.device.appState == appState {
            keys.insert(callbackDeduplicationKey(entry: entry))
        }
        return keys.count
    }

    private static func callbackDeduplicationKey(entry: SpikeLogEntry) -> String {
        if let transitionID = normalizedTransitionID(entry.sample.transitionID) {
            return "transition:\(transitionID)"
        }
        let callbackAt = resolveCallbackTimestamp(entry) ?? entry.recordedAt
        let milliseconds = Int64((callbackAt.timeIntervalSince1970 * 1000).rounded())
        switch entry.sample.signalType {
        case .clvisitArrival, .clvisitDeparture:
            return "visit:\(milliseconds)"
        default:
            return "\(entry.sample.signalType.rawValue):\(milliseconds)"
        }
    }

    private static func resolveCallbackTimestamp(_ entry: SpikeLogEntry) -> Date? {
        entry.sample.callbackReceivedAt ?? entry.recordedAt
    }

    private static func resolveLinkedProvisionalID(
        forConfirmedEntry entry: SpikeLogEntry,
        knownProvisionalIDs: Set<String>
    ) -> String? {
        if let linkedID = normalizedTransitionID(entry.sample.linkedProvisionalID) {
            return linkedID
        }
        if let transitionID = normalizedTransitionID(entry.sample.transitionID),
           knownProvisionalIDs.contains(transitionID) {
            return transitionID
        }
        return nil
    }

    private static func normalizedTransitionID(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
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
