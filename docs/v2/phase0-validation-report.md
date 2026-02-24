# Phase 0 Validation Report (Draft)

Tracks: `beacon-go6.1.2`

## 1. Summary Decision

- Report date: 2026-02-24
- Test period: 2026-02-23 to 2026-02-24
- Devices covered: 1 iOS device (primary tester)
- Sample count: 9 transition samples

Gate A recommendation (preliminary):

- SSID signal: `pending` (not yet evaluated in this draft)
- Focus signal: `pending` (not yet evaluated in this draft)
- CLVisit baseline quality: `acceptable (preliminary)` (arrival + departure observed)
- Background wake reliability: `pending`
- Battery impact: `pending`

## 2. Method

- Spike app build/version: BeaconSpikeApp Phase 0 spike build (local device run)
- Logging schema version: 1
- Environments tested (urban/suburban/home-work): initial home + routine movement sample
- Session breakdown:
  - commute day: pending
  - stationary day: partial
  - mixed errands day: pending

Data source:

- NDJSON export: `/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals.ndjson`
- Analyzer command:
  - `apps/ios-spike/BeaconSpikeCore/.build/debug/BeaconSpikeAnalyze '/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals.ndjson' --require-clvisit`

## 3. CLVisit and Transition Latency

| Signal | Samples | p50 delay (s) | p95 delay (s) | p99 delay (s) | max delay (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| clvisit_arrival | 2 | 270.2 | 1199.5 | 1199.5 | 1199.5 |
| clvisit_departure | 1 | 88.7 | 88.7 | 88.7 | 88.7 |
| significant_location_change | 6 | 25931.3 | 27655.3 | 27655.3 | 27655.3 |

Notes:

- CLVisit requirement check passed: both arrival and departure are present.
- Arrival latency is variable (4.5 to 20.0 minutes in current sample).
- Significant-change delays appear very large in this run and need broader-sample validation.

### 3.1 Hybrid Fast-Path Validation

| Metric | Value | Notes |
| --- | ---: | --- |
| provisional transitions emitted | n/a | current spike log schema does not yet emit `provisional` stage |
| provisional transitions confirmed by CLVisit | n/a | stage linkage not yet captured |
| provisional confirmation rate (%) | n/a | requires staged transition IDs/links |
| provisional p50 time-to-first-detection (s) | n/a | not instrumented in current run |
| provisional p95 time-to-first-detection (s) | n/a | not instrumented in current run |
| provisional p95 time-to-confirmation (s) | n/a | not instrumented in current run |
| short-stop false positives (<15 min) | pending | requires additional short-stop field runs |

Decision:

- Hybrid strategy acceptable for MVP? `pending`
- Rationale: current dataset confirms CLVisit evidence but does not yet include explicit provisional-stage instrumentation.

## 4. Background Wake Reliability

| App state | Opportunities | Callbacks received | Reliability % |
| --- | ---: | ---: | ---: |
| background | pending | pending | pending |
| suspended | pending | pending | pending |
| relaunch after termination | pending | pending | pending |

Observed failure modes:

- Pending broader run data.

## 5. SSID Availability Assessment

| Environment | Probes | available | unavailable | permission_denied |
| --- | ---: | ---: | ---: | ---: |
| home | pending | pending | pending | pending |
| work | pending | pending | pending | pending |
| transit | pending | pending | pending | pending |

Decision:

- Include SSID in MVP inputs? `pending`
- Rationale: pending.

## 6. Focus Signal Utility

| Scenario | Focus visible? | Decision impact? | Notes |
| --- | --- | --- | --- |
| arrival at grocery | pending | pending | pending |
| arrival at work | pending | pending | pending |
| arrival at home | pending | pending | pending |

Decision:

- Include focus in MVP policy inputs? `pending`
- Rationale: pending.

## 7. Battery Findings

Instruments summaries:

- commute day: pending
- stationary day: pending
- mixed day: pending

High-cost paths and mitigations:

- Pending dedicated Instruments runs.

## 8. Recommendation for Final MVP Signal Contract

Signals to keep:

- `clvisit_arrival`
- `clvisit_departure`
- `significant_location_change` (provisional; validate delay semantics with larger sample)

Signals to defer/remove:

- Pending SSID and Focus analysis.

Contract updates required:

- Add explicit staged transition fields for `provisional` versus `confirmed` fast-path evaluation.

## 9. Appendix

- NDJSON export location(s):
  - `/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals.ndjson`
- Aggregate notebook/script location:
  - `apps/ios-spike/BeaconSpikeCore` (`swift run BeaconSpikeAnalyze <path> [--require-clvisit]`)
- Open issues created from findings:
  - `beacon-go6.1.6` (ongoing on-device smoke and broader collection)
