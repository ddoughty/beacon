# BeaconSpikeCore

Phase 0 spike implementation scaffold for Beacon signal validation.

Current scope:

- typed models for spike log entries aligned with
  `docs/v2/phase0-spike-log.schema.json`
- NDJSON writer for app-side signal capture
- NDJSON parser for local analysis and report generation
- log analyzer for signal counts + latency percentiles
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
- request Focus authorization (when available) for focus snapshot logging
- append callbacks through `CoreLocationSignalCaptureAdapter` into NDJSON logs
- emit SSID probe and Focus snapshot records on lifecycle/callback events
- show log path, entry count, and recent callback activity in a debug UI
- provide controls to capture manual SSID/Focus snapshots and clear the log

Analyze an exported NDJSON log:

```bash
cd apps/ios-spike/BeaconSpikeCore
swift run BeaconSpikeAnalyze /path/to/phase0-signals.ndjson --require-clvisit
```

The analyzer prints:

- total/transition entry counts
- CLVisit arrival/departure presence
- per-signal latency table (`p50`, `p95`, `p99`, `max`)
- hybrid fast-path metrics (`provisional` detection/confirmation quality)
- background wake reliability table (opportunities vs observed callbacks for
  `background`, `suspended`, `relaunch`)

When `--require-clvisit` is supplied, the command exits non-zero if either
`clvisit_arrival` or `clvisit_departure` entries are missing.
