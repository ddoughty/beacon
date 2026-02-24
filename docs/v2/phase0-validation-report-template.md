# Phase 0 Validation Report Template

Tracks: `beacon-go6.1.2`

Output file target: `docs/v2/phase0-validation-report.md`

## 1. Summary Decision

- Report date:
- Test period:
- Devices covered:
- Sample count:

Gate A recommendation:

- SSID signal: `go` or `no-go` (reason)
- Focus signal: `go` or `no-go` (reason)
- CLVisit baseline quality: `acceptable` or `not acceptable`
- Background wake reliability: `acceptable` or `not acceptable`
- Battery impact: `acceptable` or `not acceptable`

## 2. Method

- Spike app build/version:
- Logging schema version:
- Environments tested (urban/suburban/home-work):
- Session breakdown:
  - commute day:
  - stationary day:
  - mixed errands day:

## 3. CLVisit and Transition Latency

| Signal | Samples | p50 delay (s) | p95 delay (s) | p99 delay (s) | max delay (s) |
| --- | ---: | ---: | ---: | ---: | ---: |
| clvisit_arrival |  |  |  |  |  |
| clvisit_departure |  |  |  |  |  |
| significant_location_change |  |  |  |  |  |

Notes:

### 3.1 Hybrid Fast-Path Validation

| Metric | Value | Notes |
| --- | ---: | --- |
| provisional transitions emitted |  |  |
| provisional transitions confirmed by CLVisit |  |  |
| provisional confirmation rate (%) |  |  |
| provisional p50 time-to-first-detection (s) |  |  |
| provisional p95 time-to-first-detection (s) |  |  |
| provisional p95 time-to-confirmation (s) |  |  |
| short-stop false positives (<15 min) |  |  |

Decision:

- Hybrid strategy acceptable for MVP? `yes/no`
- Rationale:

## 4. Background Wake Reliability

| App state | Opportunities | Callbacks received | Reliability % |
| --- | ---: | ---: | ---: |
| background |  |  |  |
| suspended |  |  |  |
| relaunch after termination |  |  |  |

Observed failure modes:

## 5. SSID Availability Assessment

| Environment | Probes | available | unavailable | permission_denied |
| --- | ---: | ---: | ---: | ---: |
| home |  |  |  |  |
| work |  |  |  |  |
| transit |  |  |  |  |

Decision:

- Include SSID in MVP inputs? `yes/no`
- Rationale:

## 6. Focus Signal Utility

| Scenario | Focus visible? | Decision impact? | Notes |
| --- | --- | --- | --- |
| arrival at grocery |  |  |  |
| arrival at work |  |  |  |
| arrival at home |  |  |  |

Decision:

- Include focus in MVP policy inputs? `yes/no`
- Rationale:

## 7. Battery Findings

Instruments summaries:

- commute day:
- stationary day:
- mixed day:

High-cost paths and mitigations:

## 8. Recommendation for Final MVP Signal Contract

Signals to keep:

- 

Signals to defer/remove:

- 

Contract updates required:

- 

## 9. Appendix

- NDJSON export location(s):
- Aggregate notebook/script location: `apps/ios-spike/BeaconSpikeCore` (`swift run BeaconSpikeAnalyze <path> [--require-clvisit]`)
- Open issues created from findings:
