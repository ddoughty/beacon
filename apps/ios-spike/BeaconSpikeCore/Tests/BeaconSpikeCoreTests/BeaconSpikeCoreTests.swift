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
    let entry = makeEntry(signal: .ssidProbe, appState: .suspended, delaySeconds: 3.0)
    let payload = try SpikeJSONCodec.makeEncoder().encode(entry)
    let object = try #require(JSONSerialization.jsonObject(with: payload) as? [String: Any])

    #expect(object["schema_version"] as? Int == 1)
    #expect(object["record_type"] as? String == "transition_sample")
    #expect(object["recorded_at"] != nil)
    #expect(object["session_id"] as? String == "session-001")
    #expect(object["device"] != nil)
    #expect(object["sample"] != nil)
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

private func makeEntry(
    signal: SpikeSignalType,
    appState: SpikeAppState,
    delaySeconds: Double
) -> SpikeLogEntry {
    let recordedAt = Date(timeIntervalSince1970: 1_709_052_000)
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
