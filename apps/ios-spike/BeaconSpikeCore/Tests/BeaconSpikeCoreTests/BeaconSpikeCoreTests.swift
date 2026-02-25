import Testing
import Foundation
@testable import BeaconSpikeCore

@Test func loggerAppendsAndReadsNDJSON() async throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("BeaconSpikeCoreTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let outputURL = tempDirectory.appendingPathComponent("phase0.ndjson")
    let logger = NDJSONSpikeLogger(fileURL: outputURL)

    let first = makeEntry(
        signal: .clvisitArrival,
        appState: .background,
        delaySeconds: 17.4
    )
    let second = makeEntry(
        signal: .focusUpdate,
        appState: .foreground,
        delaySeconds: 0.2
    )

    try await logger.append(first)
    try await logger.append(second)

    let entries = try await logger.readAll()
    #expect(entries.count == 2)
    #expect(entries[0].sample.signalType == .clvisitArrival)
    #expect(entries[1].sample.signalType == .focusUpdate)
    #expect(entries[0].schemaVersion == 1)
}

@Test func payloadUsesExpectedSnakeCaseKeys() throws {
    let entry = makeEntry(
        signal: .ssidProbe,
        appState: .suspended,
        delaySeconds: 3.0,
        transitionStage: .provisional,
        transitionID: "prov-001",
        confirmationSource: .noneTimeout,
        linkedProvisionalID: "prov-000"
    )
    let payload = try SpikeJSONCodec.makeEncoder().encode(entry)
    let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let sample = try #require(object["sample"] as? [String: Any])

    #expect(object["schema_version"] as? Int == 1)
    #expect(object["record_type"] as? String == "transition_sample")
    #expect(object["recorded_at"] != nil)
    #expect(object["session_id"] as? String == "session-001")
    #expect(object["device"] != nil)
    #expect(object["sample"] != nil)
    #expect(sample["transition_stage"] as? String == "provisional")
    #expect(sample["transition_id"] as? String == "prov-001")
    #expect(sample["confirmation_source"] as? String == "none_timeout")
    #expect(sample["linked_provisional_id"] as? String == "prov-000")
}

@Test func payloadEncodesOpportunityTypeWithSnakeCaseKey() throws {
    let recordedAt = Date(timeIntervalSince1970: 1_709_052_010)
    let entry = SpikeLogEntry(
        recordType: .sessionSummary,
        recordedAt: recordedAt,
        sessionID: "session-opp-payload",
        device: SpikeDeviceContext(
            deviceModel: "iPhone16,1",
            iosVersion: "18.2",
            appState: .relaunch,
            lowPowerMode: false,
            batteryLevelPct: 74
        ),
        sample: SpikeSample(
            signalType: .callbackOpportunity,
            callbackReceivedAt: recordedAt,
            opportunityType: .relaunchWindow,
            notes: "window_opened:test"
        )
    )

    let payload = try SpikeJSONCodec.makeEncoder().encode(entry)
    let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])
    let sample = try #require(object["sample"] as? [String: Any])
    #expect(sample["opportunity_type"] as? String == "relaunch_window")
}

@Test func visitCaptureWritesArrivalAndDepartureEntries() async throws {
    let sink = RecordingSink()
    let adapter = CoreLocationSignalCaptureAdapter(
        sessionID: "session-visit",
        deviceModel: "iPhone16,1",
        iosVersion: "18.2",
        appendEntry: { entry in
            await sink.append(entry)
        }
    )

    let callback = Date(timeIntervalSince1970: 1_709_060_000)
    let visit = TestVisit(
        arrivalDate: callback.addingTimeInterval(-240),
        departureDate: callback.addingTimeInterval(-10),
        latitude: 42.3601,
        longitude: -71.0589,
        horizontalAccuracy: 30.0
    )

    let written = try await adapter.captureVisit(
        visit,
        appState: .background,
        lowPowerMode: false,
        batteryLevelPct: 90,
        callbackReceivedAt: callback
    )

    let entries = await sink.snapshot()
    #expect(written == 2)
    #expect(entries.count == 2)
    #expect(entries[0].sample.signalType == .clvisitArrival)
    #expect(entries[1].sample.signalType == .clvisitDeparture)
    #expect(entries[0].sample.delaySeconds == 240)
    #expect(entries[1].sample.delaySeconds == 10)
    #expect(entries[0].sample.transitionStage == .confirmed)
    #expect(entries[1].sample.transitionStage == .confirmed)
    #expect(entries[0].sample.confirmationSource == .clvisit)
    #expect(entries[1].sample.confirmationSource == .clvisit)
}

@Test func significantLocationCaptureWritesSingleEntry() async throws {
    let sink = RecordingSink()
    let adapter = CoreLocationSignalCaptureAdapter(
        sessionID: "session-slc",
        deviceModel: "iPhone16,2",
        iosVersion: "18.2",
        appendEntry: { entry in
            await sink.append(entry)
        }
    )

    let callback = Date(timeIntervalSince1970: 1_709_065_000)
    let event = TestLocation(
        timestamp: callback.addingTimeInterval(-6),
        latitude: 42.3318,
        longitude: -71.1211,
        horizontalAccuracy: 18.0
    )

    try await adapter.captureSignificantLocationChange(
        event,
        appState: .foreground,
        lowPowerMode: true,
        batteryLevelPct: 66,
        motionActivity: .walking,
        callbackReceivedAt: callback
    )

    let entries = await sink.snapshot()
    #expect(entries.count == 1)
    #expect(entries[0].sample.signalType == .significantLocationChange)
    #expect(entries[0].sample.delaySeconds == 6)
    #expect(entries[0].sample.motionActivity == .walking)
    #expect(entries[0].device.appState == .foreground)
    #expect(entries[0].sample.transitionStage == .provisional)
    #expect(entries[0].sample.confirmationSource == nil)
}

@Test func callbackOpportunityCaptureWritesSessionSummaryEntry() async throws {
    let sink = RecordingSink()
    let adapter = CoreLocationSignalCaptureAdapter(
        sessionID: "session-opportunity",
        deviceModel: "iPhone16,2",
        iosVersion: "18.2",
        appendEntry: { entry in
            await sink.append(entry)
        }
    )

    let capturedAt = Date(timeIntervalSince1970: 1_709_067_500)
    try await adapter.captureCallbackOpportunity(
        .backgroundWindow,
        appState: .background,
        lowPowerMode: false,
        batteryLevelPct: 72,
        recordedAt: capturedAt,
        notes: "window_opened:test"
    )

    let entries = await sink.snapshot()
    #expect(entries.count == 1)
    #expect(entries[0].recordType == .sessionSummary)
    #expect(entries[0].sample.signalType == .callbackOpportunity)
    #expect(entries[0].sample.opportunityType == .backgroundWindow)
    #expect(entries[0].sample.callbackReceivedAt == capturedAt)
}

@Test func captureMethodsPropagateTransitionMetadata() async throws {
    let sink = RecordingSink()
    let adapter = CoreLocationSignalCaptureAdapter(
        sessionID: "session-metadata",
        deviceModel: "iPhone16,2",
        iosVersion: "18.2",
        appendEntry: { entry in
            await sink.append(entry)
        }
    )
    let provisionalCallback = Date(timeIntervalSince1970: 1_709_070_000)
    let visitCallback = provisionalCallback.addingTimeInterval(300)

    try await adapter.captureSignificantLocationChange(
        TestLocation(
            timestamp: provisionalCallback.addingTimeInterval(-15),
            latitude: 42.3318,
            longitude: -71.1211,
            horizontalAccuracy: 18.0
        ),
        appState: .background,
        transitionID: "prov-42",
        transitionStage: .provisional,
        callbackReceivedAt: provisionalCallback
    )

    _ = try await adapter.captureVisit(
        TestVisit(
            arrivalDate: visitCallback.addingTimeInterval(-30),
            departureDate: Date.distantFuture,
            latitude: 42.3318,
            longitude: -71.1211,
            horizontalAccuracy: 18.0
        ),
        appState: .background,
        transitionID: "confirm-42",
        linkedProvisionalID: "prov-42",
        confirmationSource: .clvisit,
        transitionStage: .confirmed,
        callbackReceivedAt: visitCallback
    )

    let entries = await sink.snapshot()
    #expect(entries.count == 2)
    #expect(entries[0].sample.transitionID == "prov-42")
    #expect(entries[0].sample.transitionStage == .provisional)
    #expect(entries[1].sample.transitionID == "confirm-42")
    #expect(entries[1].sample.transitionStage == .confirmed)
    #expect(entries[1].sample.linkedProvisionalID == "prov-42")
    #expect(entries[1].sample.confirmationSource == .clvisit)
}

@Test func analyzerSummarizesSignalCountsAndPercentiles() throws {
    let analyzer = SpikeLogAnalyzer()

    let entries = [
        makeEntry(signal: .clvisitArrival, appState: .background, delaySeconds: 10),
        makeEntry(signal: .clvisitArrival, appState: .background, delaySeconds: 20),
        makeEntry(signal: .clvisitArrival, appState: .background, delaySeconds: 30),
        makeEntry(signal: .clvisitArrival, appState: .background, delaySeconds: 40),
        makeEntry(signal: .clvisitDeparture, appState: .background, delaySeconds: 7),
        makeEntry(signal: .significantLocationChange, appState: .foreground, delaySeconds: 2),
        makeEntry(signal: .significantLocationChange, appState: .foreground, delaySeconds: 4),
        makeEntry(signal: .significantLocationChange, appState: .foreground, delaySeconds: 6),
        makeEntry(signal: .significantLocationChange, appState: .foreground, delaySeconds: 8),
        makeEntry(signal: .significantLocationChange, appState: .foreground, delaySeconds: 10),
    ]

    let summary = analyzer.analyze(entries: entries)
    #expect(summary.totalEntries == 10)
    #expect(summary.transitionEntryCount == 10)
    #expect(summary.hasVisitArrival)
    #expect(summary.hasVisitDeparture)
    #expect(!summary.hybridFastPath.stageMetadataPresent)
    #expect(!summary.hybridFastPath.confirmationLinkagePresent)
    #expect(summary.hybridFastPath.provisionalTransitionsEmitted == 5)
    #expect(summary.hybridFastPath.provisionalTransitionsConfirmed == nil)
    #expect(summary.hybridFastPath.provisionalP50DetectionSeconds == 6)
    #expect(summary.hybridFastPath.provisionalP95DetectionSeconds == 10)

    let arrival = try #require(summary.summary(for: .clvisitArrival))
    #expect(arrival.sampleCount == 4)
    #expect(arrival.p50DelaySeconds == 20)
    #expect(arrival.p95DelaySeconds == 40)
    #expect(arrival.p99DelaySeconds == 40)
    #expect(arrival.maxDelaySeconds == 40)

    let significant = try #require(summary.summary(for: .significantLocationChange))
    #expect(significant.sampleCount == 5)
    #expect(significant.p50DelaySeconds == 6)
    #expect(significant.p95DelaySeconds == 10)
    #expect(significant.p99DelaySeconds == 10)
    #expect(significant.maxDelaySeconds == 10)
}

@Test func analyzerDerivesDelayWhenDelaySecondsMissing() throws {
    let analyzer = SpikeLogAnalyzer()
    let callback = Date(timeIntervalSince1970: 1_709_052_222)

    let derivedDelayEntry = SpikeLogEntry(
        recordType: .transitionSample,
        recordedAt: callback,
        sessionID: "session-derived",
        device: SpikeDeviceContext(
            deviceModel: "iPhone16,1",
            iosVersion: "18.2",
            appState: .background,
            lowPowerMode: false,
            batteryLevelPct: 80
        ),
        sample: SpikeSample(
            signalType: .significantLocationChange,
            eventOccurredAt: callback.addingTimeInterval(-12),
            callbackReceivedAt: callback,
            delaySeconds: nil,
            latitude: 42.36,
            longitude: -71.05,
            horizontalAccuracyM: 20,
            notes: "derived delay test"
        )
    )

    let summary = analyzer.analyze(entries: [derivedDelayEntry])
    let significant = try #require(summary.summary(for: .significantLocationChange))
    #expect(significant.sampleCount == 1)
    #expect(significant.p50DelaySeconds == 12)
    #expect(significant.maxDelaySeconds == 12)
}

@Test func analyzerIgnoresNonTransitionRecordsForSignalLatencyTable() {
    let analyzer = SpikeLogAnalyzer()
    let transition = makeEntry(signal: .clvisitArrival, appState: .background, delaySeconds: 4)
    let nonTransition = SpikeLogEntry(
        recordType: .sessionSummary,
        recordedAt: Date(timeIntervalSince1970: 1_709_052_500),
        sessionID: "session-summary",
        device: transition.device,
        sample: transition.sample
    )

    let summary = analyzer.analyze(entries: [transition, nonTransition])
    #expect(summary.totalEntries == 2)
    #expect(summary.transitionEntryCount == 1)
    #expect(summary.signalSummaries.count == 1)
}

@Test func analyzerComputesHybridFastPathMetricsWithLinkedTransitions() {
    let analyzer = SpikeLogAnalyzer()
    let device = SpikeDeviceContext(
        deviceModel: "iPhone16,1",
        iosVersion: "18.2",
        appState: .background,
        lowPowerMode: false,
        batteryLevelPct: 80
    )
    let base = Date(timeIntervalSince1970: 1_709_080_000)

    let provisionalA = SpikeLogEntry(
        recordType: .transitionSample,
        recordedAt: base,
        sessionID: "session-hybrid",
        device: device,
        sample: SpikeSample(
            signalType: .significantLocationChange,
            eventOccurredAt: base.addingTimeInterval(-10),
            callbackReceivedAt: base,
            delaySeconds: 10,
            transitionStage: .provisional,
            transitionID: "prov-a",
            latitude: 42.36,
            longitude: -71.05,
            horizontalAccuracyM: 20,
            notes: "provisional-a"
        )
    )
    let provisionalB = SpikeLogEntry(
        recordType: .transitionSample,
        recordedAt: base.addingTimeInterval(60),
        sessionID: "session-hybrid",
        device: device,
        sample: SpikeSample(
            signalType: .significantLocationChange,
            eventOccurredAt: base.addingTimeInterval(40),
            callbackReceivedAt: base.addingTimeInterval(60),
            delaySeconds: 20,
            transitionStage: .provisional,
            transitionID: "prov-b",
            latitude: 42.36,
            longitude: -71.05,
            horizontalAccuracyM: 20,
            notes: "provisional-b"
        )
    )
    let provisionalC = SpikeLogEntry(
        recordType: .transitionSample,
        recordedAt: base.addingTimeInterval(120),
        sessionID: "session-hybrid",
        device: device,
        sample: SpikeSample(
            signalType: .significantLocationChange,
            eventOccurredAt: base.addingTimeInterval(90),
            callbackReceivedAt: base.addingTimeInterval(120),
            delaySeconds: 30,
            transitionStage: .provisional,
            transitionID: "prov-c",
            latitude: 42.36,
            longitude: -71.05,
            horizontalAccuracyM: 20,
            notes: "provisional-c"
        )
    )
    let confirmedA = SpikeLogEntry(
        recordType: .transitionSample,
        recordedAt: base.addingTimeInterval(300),
        sessionID: "session-hybrid",
        device: device,
        sample: SpikeSample(
            signalType: .clvisitArrival,
            eventOccurredAt: base.addingTimeInterval(250),
            callbackReceivedAt: base.addingTimeInterval(300),
            delaySeconds: 50,
            transitionStage: .confirmed,
            transitionID: "confirm-a",
            confirmationSource: .clvisit,
            linkedProvisionalID: "prov-a",
            latitude: 42.36,
            longitude: -71.05,
            horizontalAccuracyM: 20,
            notes: "confirmed-a"
        )
    )
    let confirmedB = SpikeLogEntry(
        recordType: .transitionSample,
        recordedAt: base.addingTimeInterval(1200),
        sessionID: "session-hybrid",
        device: device,
        sample: SpikeSample(
            signalType: .clvisitDeparture,
            eventOccurredAt: base.addingTimeInterval(1140),
            callbackReceivedAt: base.addingTimeInterval(1200),
            delaySeconds: 60,
            transitionStage: .confirmed,
            transitionID: "confirm-b",
            confirmationSource: .clvisit,
            linkedProvisionalID: "prov-b",
            latitude: 42.36,
            longitude: -71.05,
            horizontalAccuracyM: 20,
            notes: "confirmed-b"
        )
    )

    let summary = analyzer.analyze(entries: [provisionalA, provisionalB, provisionalC, confirmedA, confirmedB])
    let hybrid = summary.hybridFastPath
    #expect(hybrid.stageMetadataPresent)
    #expect(hybrid.confirmationLinkagePresent)
    #expect(hybrid.provisionalTransitionsEmitted == 3)
    #expect(hybrid.provisionalTransitionsConfirmed == 2)
    #expect(hybrid.provisionalConfirmationRatePercent == (2.0 / 3.0) * 100.0)
    #expect(hybrid.provisionalP50DetectionSeconds == 20)
    #expect(hybrid.provisionalP95DetectionSeconds == 30)
    #expect(hybrid.confirmationP95Seconds == 1140)
    #expect(hybrid.shortStopObservationCount == 3)
    #expect(hybrid.shortStopFalsePositives == 1)
}

@Test func analyzerComputesBackgroundWakeReliabilityFromOpportunities() {
    let analyzer = SpikeLogAnalyzer()
    let base = Date(timeIntervalSince1970: 1_709_090_000)

    let entries = [
        makeOpportunityEntry(type: .backgroundWindow, appState: .background, recordedAt: base),
        makeOpportunityEntry(type: .backgroundWindow, appState: .background, recordedAt: base.addingTimeInterval(60)),
        makeOpportunityEntry(type: .suspendedWindow, appState: .suspended, recordedAt: base.addingTimeInterval(120)),
        makeOpportunityEntry(type: .relaunchWindow, appState: .relaunch, recordedAt: base.addingTimeInterval(180)),
        makeEntry(
            signal: .clvisitArrival,
            appState: .background,
            delaySeconds: 15,
            recordedAt: base.addingTimeInterval(10)
        ),
        makeEntry(
            signal: .clvisitDeparture,
            appState: .background,
            delaySeconds: 12,
            recordedAt: base.addingTimeInterval(10)
        ),
        makeEntry(
            signal: .significantLocationChange,
            appState: .background,
            delaySeconds: 8,
            recordedAt: base.addingTimeInterval(40)
        ),
        makeEntry(
            signal: .significantLocationChange,
            appState: .suspended,
            delaySeconds: 11,
            recordedAt: base.addingTimeInterval(130)
        ),
        makeEntry(
            signal: .clvisitArrival,
            appState: .relaunch,
            delaySeconds: 20,
            recordedAt: base.addingTimeInterval(200),
            transitionID: "confirm-r"
        ),
        makeEntry(
            signal: .clvisitDeparture,
            appState: .relaunch,
            delaySeconds: 19,
            recordedAt: base.addingTimeInterval(200),
            transitionID: "confirm-r"
        ),
    ]

    let summary = analyzer.analyze(entries: entries)
    let reliability = summary.backgroundWakeReliability
    #expect(reliability.backgroundOpportunities == 2)
    #expect(reliability.backgroundCallbacks == 2)
    #expect(reliability.reliabilityPercent(for: .background) == 100)
    #expect(reliability.suspendedOpportunities == 1)
    #expect(reliability.suspendedCallbacks == 1)
    #expect(reliability.reliabilityPercent(for: .suspended) == 100)
    #expect(reliability.relaunchOpportunities == 1)
    #expect(reliability.relaunchCallbacks == 1)
    #expect(reliability.reliabilityPercent(for: .relaunch) == 100)
}

private func makeEntry(
    signal: SpikeSignalType,
    appState: SpikeAppState,
    delaySeconds: Double,
    recordedAt: Date = Date(timeIntervalSince1970: 1_709_052_000),
    transitionStage: SpikeTransitionStage? = nil,
    transitionID: String? = nil,
    confirmationSource: SpikeTransitionConfirmationSource? = nil,
    linkedProvisionalID: String? = nil
) -> SpikeLogEntry {
    let occurredAt = recordedAt.addingTimeInterval(-delaySeconds)
    return SpikeLogEntry(
        recordType: .transitionSample,
        recordedAt: recordedAt,
        sessionID: "session-001",
        device: SpikeDeviceContext(
            deviceModel: "iPhone16,1",
            iosVersion: "18.2",
            appState: appState,
            lowPowerMode: false,
            batteryLevelPct: 84.5
        ),
        sample: SpikeSample(
            signalType: signal,
            eventOccurredAt: occurredAt,
            callbackReceivedAt: recordedAt,
            delaySeconds: delaySeconds,
            transitionStage: transitionStage,
            transitionID: transitionID,
            confirmationSource: confirmationSource,
            linkedProvisionalID: linkedProvisionalID,
            latitude: 42.3601,
            longitude: -71.0589,
            horizontalAccuracyM: 25.0,
            motionActivity: .walking,
            focusState: .off,
            focusLabel: nil,
            ssidStatus: .available,
            batteryEnergyImpact: .low,
            notes: "test fixture"
        )
    )
}

private func makeOpportunityEntry(
    type: SpikeCallbackOpportunityType,
    appState: SpikeAppState,
    recordedAt: Date
) -> SpikeLogEntry {
    SpikeLogEntry(
        recordType: .sessionSummary,
        recordedAt: recordedAt,
        sessionID: "session-opportunity",
        device: SpikeDeviceContext(
            deviceModel: "iPhone16,1",
            iosVersion: "18.2",
            appState: appState,
            lowPowerMode: false,
            batteryLevelPct: 82
        ),
        sample: SpikeSample(
            signalType: .callbackOpportunity,
            callbackReceivedAt: recordedAt,
            opportunityType: type,
            notes: "window_opened:test"
        )
    )
}

private struct TestVisit: VisitSignalEvent {
    let arrivalDate: Date
    let departureDate: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
}

private struct TestLocation: LocationSignalEvent {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
}

private actor RecordingSink {
    private var entries: [SpikeLogEntry] = []

    func append(_ entry: SpikeLogEntry) {
        entries.append(entry)
    }

    func snapshot() -> [SpikeLogEntry] {
        entries
    }
}
