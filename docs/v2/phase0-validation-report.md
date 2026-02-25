# Phase 0 Validation Report (Draft)

Tracks: `beacon-go6.1.6`

## 1. Summary Decision

- Report date: 2026-02-25
- Test period: 2026-02-23 to 2026-02-25
- Devices covered: 1 iOS device (primary tester)
- Sample count: 19 transition samples (10 with staged transition metadata)

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

- NDJSON export: `/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals-1.ndjson`
- Analyzer command:
  - `apps/ios-spike/BeaconSpikeCore/.build/debug/BeaconSpikeAnalyze '/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals-1.ndjson' --require-clvisit`
  - staged-only fast-path slice: `jq -c 'select(.sample.transition_stage != null)' '/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals-1.ndjson' > /tmp/phase0-signals-1-staged.ndjson && apps/ios-spike/BeaconSpikeCore/.build/debug/BeaconSpikeAnalyze '/tmp/phase0-signals-1-staged.ndjson' --require-clvisit`

## 3. CLVisit and Transition Latency

| Signal | Samples | p50 delay (s) | p95 delay (s) | p99 delay (s) | max delay (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| clvisit_arrival | 6 | 932.6 | 63985.6 | 63985.6 | 63985.6 |
| clvisit_departure | 3 | 165.1 | 263.4 | 263.4 | 263.4 |
| significant_location_change | 10 | 25931.3 | 116362.4 | 116362.4 | 116362.4 |

Notes:

- CLVisit requirement check passed: both arrival and departure are present.
- Arrival latency remains highly variable (5.0 minutes median but with multi-hour tail outliers).
- Significant-change delays remain bimodal (near-real-time samples plus very large stale/outlier delays).

### 3.1 Hybrid Fast-Path Validation

| Metric | Value | Notes |
| --- | ---: | --- |
| provisional transitions emitted | 4 | staged subset only (`transition_stage=provisional`) |
| provisional transitions confirmed by CLVisit | 3 | unique staged provisional IDs linked by CLVisit confirmations |
| provisional confirmation rate (%) | 75.0 | staged subset only |
| provisional p50 time-to-first-detection (s) | 0.1 | staged subset only |
| provisional p95 time-to-first-detection (s) | 116362.4 | staged subset includes one extreme stale/outlier provisional sample |
| provisional p95 time-to-confirmation (s) | 4156.5 | staged subset only |
| short-stop false positives (<15 min) | 1 / 3 | staged subset, 15-minute observation threshold |

Decision:

- Hybrid strategy acceptable for MVP? `pending`
- Rationale: staged instrumentation is now producing measurable confirmation metrics (75% in this run), but outlier delays and limited sample size still require broader real-device validation before Gate A closure.

## 4. Background Wake Reliability

| App state | Opportunities | Callbacks received | Reliability % |
| --- | ---: | ---: | ---: |
| background | pending | 12 | pending |
| suspended | pending | 0 | pending |
| relaunch after termination | pending | 4 | pending |

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
- stationary day: partial (19 callback samples all report `battery_level_pct=100`, `low_power_mode=false`)
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
  - `/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals-1.ndjson`
  - `/Users/doughty/Library/Mobile Documents/com~apple~CloudDocs/Beacon Data/phase0-signals.ndjson` (prior snapshot)
- Aggregate notebook/script location:
  - `apps/ios-spike/BeaconSpikeCore` (`swift run BeaconSpikeAnalyze <path> [--require-clvisit]`)
- Open issues created from findings:
  - `beacon-go6.1.6` (ongoing on-device smoke and broader collection)
  - `beacon-1j6` (add background opportunity counters for reliability denominator)
  - `beacon-642` (investigate stale-delay outliers in staged provisional samples)
