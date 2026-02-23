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
