# Phase 0 Spike App and Instrumentation Checklist

Tracks: `beacon-go6.1.1`

## Spike Branch

- Branch name: `codex/AGENT-feature/phase0-signal-validation-spike`
- App target: lightweight iOS spike app (no production auth or backend required)
- Build profile: Debug for instrumentation and TestFlight/Internal when needed for
  real background behavior

## Data to Capture

For each observed transition sample:

- `captured_at` (UTC)
- `signal_type` (`CLVisit`, significant location, motion update)
- `event_occurred_at` if provided by API
- `delay_seconds` between occurrence and callback delivery
- app state at callback (`foreground`, `background`, `suspended`, `relaunch`)
- horizontal accuracy and coordinates
- battery level and low power mode state
- device model + iOS version
- transition stage (`provisional` or `confirmed`)
- confirmation source (`clvisit`, `geofence`, `none_timeout`)
- provisional-to-confirmed delay when both stages are observed

Persist local samples to newline-delimited JSON for export.

## Instrumentation Tasks

1. CLVisit latency distribution
- Log arrival/departure callbacks with both callback time and event time.
- Compute p50/p95/p99 delay and max delay per day.

2. Background wake reliability
- Record whether callbacks are delivered when app is backgrounded, suspended, and
  after force-termination/relaunch cases.
- Include counts: expected opportunities vs observed callbacks.

3. Wi-Fi SSID availability
- Attempt background SSID read under intended permissions.
- Log availability state only (`available`, `unavailable`, `permission_denied`).
- Do not log raw SSID values in exported reports.

4. Focus status utility
- Record Focus availability and state transitions at callback times.
- Tag whether focus signal plausibly changes action policy decisions.

5. Battery impact profiling
- Run Instruments sessions for at least:
  - commute day
  - mostly stationary day
  - mixed walk/drive errands day
- Capture energy impact summary and high-cost call stacks.

6. Hybrid fast-path validation
- Emit provisional transitions from motion + significant-change hints, then
  reconcile when CLVisit callbacks arrive.
- Measure time-to-first provisional detection and % later confirmed by CLVisit.
- Track false positives for short-stop visits (for example, trips under 15 min).

## Test Matrix

- Devices: at least one recent iPhone + one older iPhone if available
- iOS versions: current major + previous major where possible
- Environments:
  - urban dense area
  - suburban area
  - home/work routine

## Exit Criteria Mapping (Gate A Inputs)

- CLVisit latency baseline established (distribution + worst-case notes)
- Background wake reliability quantified with reproducible logs
- Hybrid fast-path quality quantified (provisional speed, confirmation rate, false positives)
- SSID signal either:
  - accepted for MVP inputs, or
  - explicitly removed from MVP with reason
- Focus signal either:
  - accepted as useful policy input, or
  - removed as low-value/noisy
- Battery impact deemed acceptable for daily use with documented tradeoffs

## Report Template

Produce `docs/v2/phase0-validation-report.md` with:

1. Summary decision (go/no-go by signal)
2. Method and sample size
3. Quantitative results (tables + latency percentiles)
4. Battery findings
5. Recommendation for final MVP signal contract
