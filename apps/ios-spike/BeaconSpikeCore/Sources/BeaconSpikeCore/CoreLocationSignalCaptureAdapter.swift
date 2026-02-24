import Foundation

public protocol VisitSignalEvent {
    var arrivalDate: Date { get }
    var departureDate: Date { get }
    var latitude: Double { get }
    var longitude: Double { get }
    var horizontalAccuracy: Double { get }
}

public protocol LocationSignalEvent {
    var timestamp: Date { get }
    var latitude: Double { get }
    var longitude: Double { get }
    var horizontalAccuracy: Double { get }
}

public struct CoreLocationSignalCaptureAdapter: Sendable {
    public typealias AppendEntry = @Sendable (SpikeLogEntry) async throws -> Void
    public typealias NowProvider = @Sendable () -> Date

    private let sessionID: String?
    private let deviceModel: String
    private let iosVersion: String
    private let appendEntry: AppendEntry
    private let now: NowProvider

    public init(
        sessionID: String?,
        deviceModel: String,
        iosVersion: String,
        appendEntry: @escaping AppendEntry,
        now: @escaping NowProvider = Date.init
    ) {
        self.sessionID = sessionID
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
        self.appendEntry = appendEntry
        self.now = now
    }

    @discardableResult
    public func captureVisit(
        _ visit: some VisitSignalEvent,
        appState: SpikeAppState,
        lowPowerMode: Bool? = nil,
        batteryLevelPct: Double? = nil,
        transitionID: String? = nil,
        linkedProvisionalID: String? = nil,
        confirmationSource: SpikeTransitionConfirmationSource? = .clvisit,
        transitionStage: SpikeTransitionStage = .confirmed,
        callbackReceivedAt: Date? = nil
    ) async throws -> Int {
        let callbackAt = callbackReceivedAt ?? now()
        let context = makeDeviceContext(
            appState: appState,
            lowPowerMode: lowPowerMode,
            batteryLevelPct: batteryLevelPct
        )

        var count = 0
        if visit.arrivalDate != Date.distantPast {
            let entry = makeVisitEntry(
                signalType: .clvisitArrival,
                eventOccurredAt: visit.arrivalDate,
                callbackReceivedAt: callbackAt,
                transitionStage: transitionStage,
                transitionID: transitionID,
                confirmationSource: confirmationSource,
                linkedProvisionalID: linkedProvisionalID,
                context: context,
                visit: visit
            )
            try await appendEntry(entry)
            count += 1
        }

        if visit.departureDate != Date.distantFuture {
            let entry = makeVisitEntry(
                signalType: .clvisitDeparture,
                eventOccurredAt: visit.departureDate,
                callbackReceivedAt: callbackAt,
                transitionStage: transitionStage,
                transitionID: transitionID,
                confirmationSource: confirmationSource,
                linkedProvisionalID: linkedProvisionalID,
                context: context,
                visit: visit
            )
            try await appendEntry(entry)
            count += 1
        }

        return count
    }

    public func captureSignificantLocationChange(
        _ location: some LocationSignalEvent,
        appState: SpikeAppState,
        lowPowerMode: Bool? = nil,
        batteryLevelPct: Double? = nil,
        motionActivity: SpikeMotionActivity? = nil,
        transitionID: String? = nil,
        transitionStage: SpikeTransitionStage = .provisional,
        confirmationSource: SpikeTransitionConfirmationSource? = nil,
        linkedProvisionalID: String? = nil,
        callbackReceivedAt: Date? = nil
    ) async throws {
        let callbackAt = callbackReceivedAt ?? now()
        let context = makeDeviceContext(
            appState: appState,
            lowPowerMode: lowPowerMode,
            batteryLevelPct: batteryLevelPct
        )
        let delaySeconds = max(0, callbackAt.timeIntervalSince(location.timestamp))
        let entry = SpikeLogEntry(
            recordType: .transitionSample,
            recordedAt: callbackAt,
            sessionID: sessionID,
            device: context,
            sample: SpikeSample(
                signalType: .significantLocationChange,
                eventOccurredAt: location.timestamp,
                callbackReceivedAt: callbackAt,
                delaySeconds: delaySeconds,
                transitionStage: transitionStage,
                transitionID: transitionID,
                confirmationSource: confirmationSource,
                linkedProvisionalID: linkedProvisionalID,
                latitude: location.latitude,
                longitude: location.longitude,
                horizontalAccuracyM: location.horizontalAccuracy,
                motionActivity: motionActivity,
                notes: "core_location_significant_change"
            )
        )
        try await appendEntry(entry)
    }

    private func makeVisitEntry(
        signalType: SpikeSignalType,
        eventOccurredAt: Date,
        callbackReceivedAt: Date,
        transitionStage: SpikeTransitionStage,
        transitionID: String?,
        confirmationSource: SpikeTransitionConfirmationSource?,
        linkedProvisionalID: String?,
        context: SpikeDeviceContext,
        visit: some VisitSignalEvent
    ) -> SpikeLogEntry {
        let delaySeconds = max(0, callbackReceivedAt.timeIntervalSince(eventOccurredAt))
        return SpikeLogEntry(
            recordType: .transitionSample,
            recordedAt: callbackReceivedAt,
            sessionID: sessionID,
            device: context,
            sample: SpikeSample(
                signalType: signalType,
                eventOccurredAt: eventOccurredAt,
                callbackReceivedAt: callbackReceivedAt,
                delaySeconds: delaySeconds,
                transitionStage: transitionStage,
                transitionID: transitionID,
                confirmationSource: confirmationSource,
                linkedProvisionalID: linkedProvisionalID,
                latitude: visit.latitude,
                longitude: visit.longitude,
                horizontalAccuracyM: visit.horizontalAccuracy,
                notes: "core_location_visit"
            )
        )
    }

    private func makeDeviceContext(
        appState: SpikeAppState,
        lowPowerMode: Bool?,
        batteryLevelPct: Double?
    ) -> SpikeDeviceContext {
        SpikeDeviceContext(
            deviceModel: deviceModel,
            iosVersion: iosVersion,
            appState: appState,
            lowPowerMode: lowPowerMode,
            batteryLevelPct: batteryLevelPct
        )
    }
}

#if canImport(CoreLocation)
import CoreLocation

@available(macOS 10.15, iOS 8.0, watchOS 2.0, tvOS 9.0, *)
extension CLVisit: VisitSignalEvent {
    public var latitude: Double { coordinate.latitude }
    public var longitude: Double { coordinate.longitude }
}

extension CLLocation: LocationSignalEvent {
    public var latitude: Double { coordinate.latitude }
    public var longitude: Double { coordinate.longitude }
}
#endif
