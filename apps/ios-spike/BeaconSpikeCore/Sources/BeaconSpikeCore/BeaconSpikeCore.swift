import Foundation

public enum SpikeRecordType: String, Codable, Sendable {
    case transitionSample = "transition_sample"
    case batterySnapshot = "battery_snapshot"
    case focusSnapshot = "focus_snapshot"
    case ssidProbe = "ssid_probe"
    case sessionSummary = "session_summary"
}

public enum SpikeAppState: String, Codable, Sendable {
    case foreground
    case background
    case suspended
    case relaunch
}

public enum SpikeSignalType: String, Codable, Sendable {
    case clvisitArrival = "clvisit_arrival"
    case clvisitDeparture = "clvisit_departure"
    case significantLocationChange = "significant_location_change"
    case motionUpdate = "motion_update"
    case focusUpdate = "focus_update"
    case ssidProbe = "ssid_probe"
    case batteryProfile = "battery_profile"
}

public enum SpikeMotionActivity: String, Codable, Sendable {
    case stationary
    case walking
    case running
    case cycling
    case automotive
    case unknown
}

public enum SpikeFocusState: String, Codable, Sendable {
    case unknown
    case off
    case on
}

public enum SpikeSSIDStatus: String, Codable, Sendable {
    case available
    case unavailable
    case permissionDenied = "permission_denied"
}

public enum SpikeBatteryEnergyImpact: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct SpikeDeviceContext: Codable, Sendable, Equatable {
    public let deviceModel: String
    public let iosVersion: String
    public let appState: SpikeAppState
    public let lowPowerMode: Bool?
    public let batteryLevelPct: Double?

    enum CodingKeys: String, CodingKey {
        case deviceModel = "device_model"
        case iosVersion = "ios_version"
        case appState = "app_state"
        case lowPowerMode = "low_power_mode"
        case batteryLevelPct = "battery_level_pct"
    }

    public init(
        deviceModel: String,
        iosVersion: String,
        appState: SpikeAppState,
        lowPowerMode: Bool? = nil,
        batteryLevelPct: Double? = nil
    ) {
        self.deviceModel = deviceModel
        self.iosVersion = iosVersion
        self.appState = appState
        self.lowPowerMode = lowPowerMode
        self.batteryLevelPct = batteryLevelPct
    }
}

public struct SpikeSample: Codable, Sendable, Equatable {
    public let signalType: SpikeSignalType
    public let eventOccurredAt: Date?
    public let callbackReceivedAt: Date?
    public let delaySeconds: Double?
    public let latitude: Double?
    public let longitude: Double?
    public let horizontalAccuracyM: Double?
    public let motionActivity: SpikeMotionActivity?
    public let focusState: SpikeFocusState?
    public let focusLabel: String?
    public let ssidStatus: SpikeSSIDStatus?
    public let batteryEnergyImpact: SpikeBatteryEnergyImpact?
    public let notes: String?

    enum CodingKeys: String, CodingKey {
        case signalType = "signal_type"
        case eventOccurredAt = "event_occurred_at"
        case callbackReceivedAt = "callback_received_at"
        case delaySeconds = "delay_seconds"
        case latitude
        case longitude
        case horizontalAccuracyM = "horizontal_accuracy_m"
        case motionActivity = "motion_activity"
        case focusState = "focus_state"
        case focusLabel = "focus_label"
        case ssidStatus = "ssid_status"
        case batteryEnergyImpact = "battery_energy_impact"
        case notes
    }

    public init(
        signalType: SpikeSignalType,
        eventOccurredAt: Date? = nil,
        callbackReceivedAt: Date? = nil,
        delaySeconds: Double? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        horizontalAccuracyM: Double? = nil,
        motionActivity: SpikeMotionActivity? = nil,
        focusState: SpikeFocusState? = nil,
        focusLabel: String? = nil,
        ssidStatus: SpikeSSIDStatus? = nil,
        batteryEnergyImpact: SpikeBatteryEnergyImpact? = nil,
        notes: String? = nil
    ) {
        self.signalType = signalType
        self.eventOccurredAt = eventOccurredAt
        self.callbackReceivedAt = callbackReceivedAt
        self.delaySeconds = delaySeconds
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracyM = horizontalAccuracyM
        self.motionActivity = motionActivity
        self.focusState = focusState
        self.focusLabel = focusLabel
        self.ssidStatus = ssidStatus
        self.batteryEnergyImpact = batteryEnergyImpact
        self.notes = notes
    }
}

public struct SpikeLogEntry: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let recordType: SpikeRecordType
    public let recordedAt: Date
    public let sessionID: String?
    public let device: SpikeDeviceContext
    public let sample: SpikeSample

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordType = "record_type"
        case recordedAt = "recorded_at"
        case sessionID = "session_id"
        case device
        case sample
    }

    public init(
        schemaVersion: Int = 1,
        recordType: SpikeRecordType,
        recordedAt: Date,
        sessionID: String? = nil,
        device: SpikeDeviceContext,
        sample: SpikeSample
    ) {
        self.schemaVersion = schemaVersion
        self.recordType = recordType
        self.recordedAt = recordedAt
        self.sessionID = sessionID
        self.device = device
        self.sample = sample
    }
}
