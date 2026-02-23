# BeaconSpikeCore

Phase 0 spike implementation scaffold for Beacon signal validation.

Current scope:

- typed models for spike log entries aligned with
  `docs/v2/phase0-spike-log.schema.json`
- NDJSON writer for app-side signal capture
- NDJSON parser for local analysis and report generation
- CoreLocation adapter for `CLVisit` and significant location change events
- unit tests validating append/read flow and payload key format

Run tests:

```bash
cd apps/ios-spike/BeaconSpikeCore
swift test
```

Run the iOS spike app target:

```bash
open apps/ios-spike/BeaconSpikeApp/BeaconSpikeApp.xcodeproj
```

In Xcode, run the `BeaconSpikeApp` scheme on a device/simulator. The app will:

- request location authorization
- start `CLVisit` and significant location monitoring
- append callbacks through `CoreLocationSignalCaptureAdapter` into NDJSON logs
- show log path, entry count, and recent callback activity in a debug UI
