import BeaconSpikeCore
import CoreLocation
import Foundation
import UIKit

struct SpikeCaptureEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

private struct VisitSnapshot: VisitSignalEvent, Sendable {
    let arrivalDate: Date
    let departureDate: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
}

private struct LocationSnapshot: LocationSignalEvent, Sendable {
    let timestamp: Date
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
}

private struct ProvisionalTransition: Sendable {
    let id: String
    let callbackReceivedAt: Date
    let latitude: Double
    let longitude: Double
}

@MainActor
final class SpikeCaptureViewModel: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: String
    @Published private(set) var monitoringStatus = "stopped"
    @Published private(set) var logEntryCount = 0
    @Published private(set) var logFilePath: String
    @Published private(set) var events: [SpikeCaptureEvent] = []
    @Published var lastError: String?

    private let locationManager: CLLocationManager
    private let logger: NDJSONSpikeLogger
    private let adapter: CoreLocationSignalCaptureAdapter
    private var provisionalTransitionBuffer: [ProvisionalTransition] = []

    override init() {
        let manager = CLLocationManager()
        self.locationManager = manager

        let logsURL = SpikeCaptureViewModel.makeLogFileURL()
        self.logFilePath = logsURL.path
        self.logger = NDJSONSpikeLogger(fileURL: logsURL)
        self.authorizationStatus = SpikeCaptureViewModel.describe(manager.authorizationStatus)

        let device = UIDevice.current
        device.isBatteryMonitoringEnabled = true

        self.adapter = CoreLocationSignalCaptureAdapter(
            sessionID: UUID().uuidString.lowercased(),
            deviceModel: device.model,
            iosVersion: device.systemVersion,
            appendEntry: { [logger] entry in
                try await logger.append(entry)
            }
        )

        super.init()

        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.pausesLocationUpdatesAutomatically = true

        record("Ready. Log file: \(logsURL.lastPathComponent)")
    }

    func requestAuthorizationAndStart() {
        lastError = nil
        let status = locationManager.authorizationStatus
        if status == .notDetermined {
            record("Requesting Always location authorization")
            locationManager.requestAlwaysAuthorization()
            return
        }
        startMonitoringIfAuthorized(for: status)
    }

    func stopMonitoring() {
        locationManager.stopMonitoringVisits()
        locationManager.stopMonitoringSignificantLocationChanges()
        monitoringStatus = "stopped"
        record("Stopped monitoring")
    }

    func refreshLogEntryCount() async {
        do {
            let entries = try await logger.readAll()
            logEntryCount = entries.count
        } catch {
            lastError = "Log read failed: \(error.localizedDescription)"
            record(lastError ?? "Log read failed")
        }
    }

    func prepareExportFileURL() -> URL? {
        let fileURL = URL(fileURLWithPath: logFilePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let message = "No NDJSON file exists yet. Capture at least one callback before exporting."
            lastError = message
            record(message)
            return nil
        }
        return fileURL
    }

    private func startMonitoringIfAuthorized(for status: CLAuthorizationStatus) {
        authorizationStatus = Self.describe(status)
        guard status == .authorizedAlways || status == .authorizedWhenInUse else {
            monitoringStatus = "not authorized"
            if status == .denied || status == .restricted {
                lastError = "Location access denied/restricted. Update Settings to continue."
                record(lastError ?? "Location permission unavailable")
            }
            return
        }

        locationManager.startMonitoringVisits()
        locationManager.startMonitoringSignificantLocationChanges()
        monitoringStatus = "active"
        record("Started CLVisit + significant location monitoring")
    }

    private func captureVisit(_ snapshot: VisitSnapshot) {
        let appState = currentAppState()
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let batteryLevel = batteryLevelPercent()
        let callbackAt = Date()
        let linkedProvisionalID = consumeProvisionalMatch(for: snapshot, callbackAt: callbackAt)
        let transitionID = linkedProvisionalID ?? Self.makeTransitionID(prefix: "confirm")

        Task {
            do {
                let entriesWritten = try await adapter.captureVisit(
                    snapshot,
                    appState: appState,
                    lowPowerMode: lowPowerMode,
                    batteryLevelPct: batteryLevel,
                    transitionID: transitionID,
                    linkedProvisionalID: linkedProvisionalID,
                    confirmationSource: .clvisit,
                    transitionStage: .confirmed,
                    callbackReceivedAt: callbackAt
                )
                await MainActor.run {
                    if let linkedProvisionalID {
                        record("Captured CLVisit callback (\(entriesWritten) entries, linked: \(linkedProvisionalID))")
                    } else {
                        record("Captured CLVisit callback (\(entriesWritten) entries, no provisional link)")
                    }
                }
                await refreshLogEntryCount()
            } catch {
                await MainActor.run {
                    lastError = "Visit capture failed: \(error.localizedDescription)"
                    record(lastError ?? "Visit capture failed")
                }
            }
        }
    }

    private func captureSignificantLocation(_ snapshot: LocationSnapshot) {
        let appState = currentAppState()
        let lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        let batteryLevel = batteryLevelPercent()
        let callbackAt = Date()
        let transitionID = Self.makeTransitionID(prefix: "prov")

        Task {
            do {
                try await adapter.captureSignificantLocationChange(
                    snapshot,
                    appState: appState,
                    lowPowerMode: lowPowerMode,
                    batteryLevelPct: batteryLevel,
                    transitionID: transitionID,
                    transitionStage: .provisional,
                    callbackReceivedAt: callbackAt
                )
                await MainActor.run {
                    registerProvisionalTransition(
                        id: transitionID,
                        latitude: snapshot.latitude,
                        longitude: snapshot.longitude,
                        callbackAt: callbackAt
                    )
                    record("Captured significant location callback (provisional: \(transitionID))")
                }
                await refreshLogEntryCount()
            } catch {
                await MainActor.run {
                    lastError = "Significant-change capture failed: \(error.localizedDescription)"
                    record(lastError ?? "Significant-change capture failed")
                }
            }
        }
    }

    private func currentAppState() -> SpikeAppState {
        switch UIApplication.shared.applicationState {
        case .active:
            return .foreground
        case .background:
            return .background
        case .inactive:
            return .relaunch
        @unknown default:
            return .foreground
        }
    }

    private func batteryLevelPercent() -> Double? {
        let batteryLevel = UIDevice.current.batteryLevel
        guard batteryLevel >= 0 else {
            return nil
        }
        return (Double(batteryLevel) * 100).rounded()
    }

    private func record(_ message: String) {
        events.insert(SpikeCaptureEvent(timestamp: Date(), message: message), at: 0)
        if events.count > 40 {
            events.removeLast(events.count - 40)
        }
    }

    private func registerProvisionalTransition(
        id: String,
        latitude: Double,
        longitude: Double,
        callbackAt: Date
    ) {
        pruneProvisionalTransitions(referenceTime: callbackAt)
        provisionalTransitionBuffer.append(
            ProvisionalTransition(
                id: id,
                callbackReceivedAt: callbackAt,
                latitude: latitude,
                longitude: longitude
            )
        )
    }

    private func consumeProvisionalMatch(for visit: VisitSnapshot, callbackAt: Date) -> String? {
        pruneProvisionalTransitions(referenceTime: callbackAt)
        let visitLocation = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
        var bestIndex: Int?
        var bestDistance: CLLocationDistance = .greatestFiniteMagnitude
        var bestAge: TimeInterval = .greatestFiniteMagnitude

        for (index, provisional) in provisionalTransitionBuffer.enumerated() {
            let age = callbackAt.timeIntervalSince(provisional.callbackReceivedAt)
            guard age >= 0, age <= Self.provisionalLinkWindowSeconds else {
                continue
            }

            let provisionalLocation = CLLocation(latitude: provisional.latitude, longitude: provisional.longitude)
            let distance = visitLocation.distance(from: provisionalLocation)
            guard distance <= Self.provisionalLinkMaxDistanceMeters else {
                continue
            }

            if distance < bestDistance || (distance == bestDistance && age < bestAge) {
                bestIndex = index
                bestDistance = distance
                bestAge = age
            }
        }

        guard let bestIndex else {
            return nil
        }

        let matched = provisionalTransitionBuffer.remove(at: bestIndex)
        return matched.id
    }

    private func pruneProvisionalTransitions(referenceTime: Date) {
        provisionalTransitionBuffer.removeAll { provisional in
            referenceTime.timeIntervalSince(provisional.callbackReceivedAt) > Self.provisionalLinkWindowSeconds
        }
    }

    private static func makeTransitionID(prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.lowercased())"
    }

    private static let provisionalLinkWindowSeconds: TimeInterval = 24 * 60 * 60
    private static let provisionalLinkMaxDistanceMeters: CLLocationDistance = 500

    private static func makeLogFileURL() -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("BeaconSpike", isDirectory: true)
            .appendingPathComponent("phase0-signals.ndjson", isDirectory: false)
    }

    private static func describe(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "not determined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorizedAlways:
            return "authorized always"
        case .authorizedWhenInUse:
            return "authorized when in use"
        @unknown default:
            return "unknown"
        }
    }
}

extension SpikeCaptureViewModel: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.authorizationStatus = Self.describe(status)
            self.startMonitoringIfAuthorized(for: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        let snapshot = VisitSnapshot(
            arrivalDate: visit.arrivalDate,
            departureDate: visit.departureDate,
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude,
            horizontalAccuracy: visit.horizontalAccuracy
        )
        Task { @MainActor [weak self] in
            self?.captureVisit(snapshot)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }
        let snapshot = LocationSnapshot(
            timestamp: location.timestamp,
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy
        )
        Task { @MainActor [weak self] in
            self?.captureSignificantLocation(snapshot)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = "CoreLocation error: \(error.localizedDescription)"
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            self.lastError = message
            self.record(message)
        }
    }
}
