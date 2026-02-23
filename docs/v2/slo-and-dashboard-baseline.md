# Initial SLOs and Dashboard Placeholders

Tracks: `beacon-go6.2.3`

## Reliability SLOs (Phase 1 Baseline)

Measurement window: rolling 7 days unless noted.

1. Ingestion acceptance latency
- SLI: `% of valid transitions persisted and queued within 5s`
- Target: `>= 95%`
- Error budget: `< 5%` over 7 days

2. Ingestion availability
- SLI: `% of authenticated ingest requests returning 2xx/4xx (non-5xx)`
- Target: `>= 99.5%`
- Error budget: `< 0.5%` 5xx responses over 7 days

3. Duplicate suppression quality
- SLI: `% of submitted retries that create extra transition rows`
- Target: `< 1%`
- Error budget: `>= 1%` duplicate-write rate is a breach

4. Queue freshness
- SLI: `p95 queue age for ready jobs`
- Target: `<= 30s`
- Error budget: more than 30 minutes/day above target is a breach

5. Worker execution success
- SLI: `% jobs finishing in succeeded without dead-letter`
- Target: `>= 99%`
- Error budget: `< 1%` failed+dead-letter jobs over 7 days

## Metric Placeholders

These names are placeholders and should be mapped to real instrumentation names
during implementation.

- `beacon_ingest_requests_total{status}`
- `beacon_ingest_transitions_total{result="accepted|duplicate|rejected"}`
- `beacon_ingest_persist_seconds_bucket`
- `beacon_ingest_to_queue_seconds_bucket`
- `beacon_jobs_ready_total{job_type}`
- `beacon_jobs_inflight_total{job_type}`
- `beacon_job_attempts_total{job_type,outcome}`
- `beacon_job_duration_seconds_bucket{job_type,outcome}`
- `beacon_job_dead_letter_total{job_type,error_code}`
- `beacon_external_call_seconds_bucket{provider,endpoint}`
- `beacon_external_call_total{provider,endpoint,outcome}`

## Dashboard Layout (v0)

## Row 1: Ingestion Health

- Panel: request volume by status (5m rate)
- Panel: ingest latency p50/p95/p99
- Panel: accepted vs duplicate vs rejected transitions
- Panel: 5xx rate burn-down against error budget

## Row 2: Queue and Worker Health

- Panel: ready queue depth by job type
- Panel: queue age p50/p95
- Panel: worker success/failure/dead-letter counts
- Panel: retries by error code (top N)

## Row 3: External Dependencies

- Panel: provider latency (APNs/Google/OpenAI) p95
- Panel: provider error rates by endpoint
- Panel: circuit-breaker / kill-switch state

## Row 4: Product Outcome Signals

- Panel: pass update attempts/success/failures
- Panel: notification dispatch attempts/success/failures
- Panel: duplicate transition write rate

## Alert Placeholders

1. `Critical`: ingest 5xx rate > 2% for 10 minutes.
2. `High`: ingest p95 persist latency > 5s for 15 minutes.
3. `High`: queue age p95 > 120s for 15 minutes.
4. `Medium`: dead-letter rate > 1% for 30 minutes.
5. `Medium`: duplicate-write rate >= 1% for 30 minutes.

## Instrumentation Notes

- Attach `request_id` and `device_id` tags to ingest logs and traces.
- Emit one metric event after DB commit so accepted counts are durable.
- Capture job state transitions as both logs and counters.
- Keep cardinality bounded: avoid raw `client_event_id` labels.

