# Transition Ingestion Contract v1

Tracks: `beacon-go6.2.1`

## Goal

Define a stable client-to-server transition payload and idempotency contract for
Phase 1 ingestion work.

## Endpoint

- Method: `POST`
- Path: `/api/v1/transitions`
- Auth: device bearer token
- Content type: `application/json`

The request path must only validate, persist, enqueue, and return. It must not
call external providers.

## Request Body

```json
{
  "schema_version": 1,
  "sent_at": "2026-02-23T13:05:44Z",
  "transitions": [
    {
      "client_event_id": "01952e80-f5e0-7b11-a955-768edb74f145",
      "occurred_at": "2026-02-23T13:05:31Z",
      "signal_type": "visit_arrival",
      "latitude": 42.3601,
      "longitude": -71.0589,
      "horizontal_accuracy_m": 24.5,
      "vertical_accuracy_m": 19.1,
      "altitude_m": 7.2,
      "speed_mps": 0,
      "course_deg": 0,
      "device_time_zone": "America/New_York",
      "motion_activity": "walking",
      "is_mocked": false
    }
  ]
}
```

## Field Requirements

### Envelope

- `schema_version` (required): integer, must be `1`.
- `sent_at` (required): RFC3339 UTC timestamp for upload attempt time.
- `transitions` (required): non-empty array, max 200 items.

### Transition

- `client_event_id` (required): UUIDv7 string generated on device per transition.
- `occurred_at` (required): RFC3339 UTC timestamp for the observed transition.
- `signal_type` (required): one of
  - `visit_arrival`
  - `visit_departure`
  - `significant_location_change`
  - `manual_correction`
- `latitude` (required): decimal degrees, range `[-90, 90]`.
- `longitude` (required): decimal degrees, range `[-180, 180]`.
- `horizontal_accuracy_m` (required): number, `>= 0`.
- `vertical_accuracy_m` (optional): number, `>= 0`.
- `altitude_m` (optional): number.
- `speed_mps` (optional): number, `>= 0`.
- `course_deg` (optional): number, `[0, 360]`.
- `device_time_zone` (optional): IANA tz name.
- `motion_activity` (optional): one of
  - `stationary`
  - `walking`
  - `running`
  - `cycling`
  - `automotive`
  - `unknown`
- `is_mocked` (optional): boolean.

## Idempotency Contract

- Idempotency key is `(device_id, client_event_id)`.
- Storage must enforce unique constraint on `(device_id, client_event_id)`.
- If the exact transition was already accepted:
  - no duplicate transition row is created
  - no duplicate job row is enqueued
  - server returns `202 Accepted` with `duplicate=true`
- Duplicate detection is device-scoped. Same `client_event_id` from different
  devices is not treated as duplicate.

## Response Body

Always `202 Accepted` when auth and payload validation pass, including duplicates.

```json
{
  "request_id": "req_01JQ4W6YQAPYY4QGJV32T0P3BX",
  "accepted": 1,
  "duplicates": 0,
  "results": [
    {
      "client_event_id": "01952e80-f5e0-7b11-a955-768edb74f145",
      "transition_id": "tr_01JQ4W6YV0J79QTXAQ3EG7XQRK",
      "job_id": "job_01JQ4W6YV22YPGAMQM1AN8NQ3K",
      "duplicate": false
    }
  ]
}
```

`duplicate=true` must return the existing `transition_id` and existing `job_id`
for deterministic client behavior.

## Error Handling

- `400 Bad Request`: schema/validation failure.
- `401 Unauthorized`: missing/invalid/revoked token.
- `413 Payload Too Large`: transition count over limit.
- `429 Too Many Requests`: device-level rate limit exceeded.
- `5xx`: transient server failure; client retries with backoff.

## Client Retry Rules

- Client must retry any request that does not receive a `2xx` response.
- Client must never mutate `client_event_id` during retries.
- Client should send transitions in observed order, but server must tolerate
  out-of-order arrivals.

