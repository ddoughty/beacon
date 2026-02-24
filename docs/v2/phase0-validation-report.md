# Phase 0 Validation Report (Draft)

Tracks: `beacon-go6.1.6`

## 1. Summary Decision

- Report date: 2026-02-24
- Test period: 2026-02-23 to 2026-02-24
- Devices covered: 1 iOS device (primary tester)
- Sample count: 9 transition samples

Gate A recommendation (preliminary):

- SSID signal: `not instrumented yet` (0 SSID probes in current dataset)
- Focus signal: `not instrumented yet` (0 Focus snapshots in current dataset)
- CLVisit baseline quality: `acceptable (preliminary)` (arrival + departure observed)
- Background wake reliability: `partial evidence only` (callbacks seen in `background` and `relaunch`; denominator still missing)
- Battery impact: `pending dedicated profiling` (only callback snapshots so far)

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
| provisional transitions emitted | 6 | legacy fallback classifies `significant_location_change` entries as provisional |
| provisional transitions confirmed by CLVisit | n/a | current dataset has no `transition_id`/`linked_provisional_id` linkage fields |
| provisional confirmation rate (%) | n/a | requires linked provisional/confirmed IDs |
| provisional p50 time-to-first-detection (s) | 25931.3 | from fallback provisional classification |
| provisional p95 time-to-first-detection (s) | 27655.3 | from fallback provisional classification |
| provisional p95 time-to-confirmation (s) | n/a | confirmation linkage unavailable in this export |
| short-stop false positives (<15 min) | n/a | requires linked IDs plus >=15 minute observation windows |

Decision:

- Hybrid strategy acceptable for MVP? `pending`
- Rationale: staged instrumentation (`transition_stage`, `transition_id`, `confirmation_source`, `linked_provisional_id`) is now in code, but this export predates that change and cannot quantify confirmation/false-positive rates yet.

## 4. Background Wake Reliability

| App state | Opportunities | Callbacks received | Reliability % |
| --- | ---: | ---: | ---: |
| background | pending | 4 | pending |
| suspended | pending | 0 | pending |
| relaunch after termination | pending | 3 | pending |

Observed failure modes:

- Reliability denominator is missing (callbacks are logged, but "opportunities" are not yet counted).
- No explicit `suspended` callbacks observed in this dataset.
- Significant-change callbacks show long-tail latency bursts, creating delayed wake visibility.

## 5. SSID Availability Assessment

| Scope | Probes | available | unavailable | permission_denied |
| --- | ---: | ---: | ---: | ---: |
| aggregate (current dataset) | 0 | 0 | 0 | 0 |

Decision:

- Include SSID in MVP inputs? `pending`
- Rationale: no SSID probes have been emitted yet, so availability and permission behavior are unknown.

## 6. Focus Signal Utility

| Scope | Focus visible? | Decision impact? | Notes |
| --- | --- | --- | --- |
| aggregate (current dataset) | no samples | pending | no `focus_snapshot` or `focus_state` values captured |

Decision:

- Include focus in MVP policy inputs? `pending`
- Rationale: signal remains unmeasured in real-device runs.

## 7. Battery Findings

Instruments summaries:

- commute day: pending
- stationary day: partial (9 callback samples all report `battery_level_pct=100`, `low_power_mode=false`)
- mixed day: pending

High-cost paths and mitigations:

- Pending dedicated Instruments energy runs; callback snapshots alone are insufficient for energy-cost conclusions.

## 8. Recommendation for Final MVP Signal Contract

Signals to keep:

- `clvisit_arrival`
- `clvisit_departure`
- `significant_location_change` (provisional; validate delay semantics with larger sample)

Signals to defer/remove:

- Pending SSID and Focus analysis.

Contract updates required:

- Staged transition fields are implemented in spike logs (`transition_stage`, `transition_id`, `confirmation_source`, `linked_provisional_id`); collect a fresh export to populate confirmation and short-stop metrics.
- Add explicit background opportunity counters so reliability percentages can be computed (current logs capture callback counts only).

## 9. Appendix

- NDJSON export location(s):
  - `/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals.ndjson`
- Aggregate notebook/script location:
  - `apps/ios-spike/BeaconSpikeCore` (`swift run BeaconSpikeAnalyze <path> [--require-clvisit]`)
- Open issues created from findings:
  - `beacon-go6.1.6` (ongoing on-device smoke and broader collection)
  - `beacon-1j6` (add background opportunity counters for reliability denominator)
