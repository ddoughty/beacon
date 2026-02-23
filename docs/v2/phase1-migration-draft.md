# Phase 1 Migration Draft (Yoyo)

Tracks: `beacon-go6.2.2`

## Scope

Draft baseline database migrations for secure, idempotent ingestion:

- `devices` with hashed bearer token storage and revocation metadata
- `transitions` with device-scoped idempotency key
- `jobs` queue table for async workers
- `audit_log` table for sensitive operation history
- retention support columns and purge job seed

## Proposed Migration Order

1. `0001_create_devices.py`
2. `0002_create_transitions.py`
3. `0003_create_jobs.py`
4. `0004_create_audit_log.py`
5. `0005_add_retention_helpers.py`

Each file should include `-- forward` and `-- reverse` sections in yoyo style.

## 0001_create_devices.py

```sql
CREATE TABLE devices (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    platform TEXT NOT NULL CHECK (platform IN ('ios')),
    name TEXT,
    auth_token_hash BYTEA NOT NULL,
    auth_token_hash_alg TEXT NOT NULL DEFAULT 'sha256',
    token_created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    token_rotated_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ,
    last_seen_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, id)
);

CREATE INDEX idx_devices_user_id ON devices (user_id);
CREATE INDEX idx_devices_revoked_at ON devices (revoked_at);
```

## 0002_create_transitions.py

```sql
CREATE TABLE transitions (
    id BIGSERIAL PRIMARY KEY,
    device_id BIGINT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
    client_event_id UUID NOT NULL,
    occurred_at TIMESTAMPTZ NOT NULL,
    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    sent_at TIMESTAMPTZ NOT NULL,
    signal_type TEXT NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    horizontal_accuracy_m DOUBLE PRECISION NOT NULL,
    vertical_accuracy_m DOUBLE PRECISION,
    altitude_m DOUBLE PRECISION,
    speed_mps DOUBLE PRECISION,
    course_deg DOUBLE PRECISION,
    motion_activity TEXT,
    is_mocked BOOLEAN NOT NULL DEFAULT FALSE,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    retention_delete_after TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (device_id, client_event_id)
);

CREATE INDEX idx_transitions_device_occurred_at
    ON transitions (device_id, occurred_at DESC);
CREATE INDEX idx_transitions_retention_delete_after
    ON transitions (retention_delete_after);
```

## 0003_create_jobs.py

```sql
CREATE TABLE jobs (
    id BIGSERIAL PRIMARY KEY,
    job_type TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('queued', 'running', 'succeeded', 'failed', 'dead_letter')),
    transition_id BIGINT REFERENCES transitions(id) ON DELETE CASCADE,
    payload JSONB NOT NULL DEFAULT '{}'::jsonb,
    attempts INTEGER NOT NULL DEFAULT 0,
    max_attempts INTEGER NOT NULL DEFAULT 10,
    next_run_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    locked_at TIMESTAMPTZ,
    locked_by TEXT,
    last_error_at TIMESTAMPTZ,
    error_code TEXT,
    error_detail TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_jobs_ready
    ON jobs (next_run_at, id)
    WHERE status IN ('queued', 'failed');
CREATE INDEX idx_jobs_locked_at ON jobs (locked_at);
CREATE INDEX idx_jobs_status ON jobs (status);
```

Worker dequeue query target:

```sql
SELECT id
FROM jobs
WHERE status IN ('queued', 'failed')
  AND next_run_at <= now()
ORDER BY next_run_at, id
FOR UPDATE SKIP LOCKED
LIMIT $1;
```

## 0004_create_audit_log.py

```sql
CREATE TABLE audit_log (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT,
    device_id BIGINT REFERENCES devices(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    request_id TEXT NOT NULL,
    actor_type TEXT NOT NULL,
    actor_id TEXT,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_log_created_at ON audit_log (created_at DESC);
CREATE INDEX idx_audit_log_user_created_at ON audit_log (user_id, created_at DESC);
CREATE INDEX idx_audit_log_action_created_at ON audit_log (action, created_at DESC);
```

Expected sensitive action values:

- `device.register`
- `token.rotate`
- `token.revoke`
- `data.export`
- `data.delete_all`

## 0005_add_retention_helpers.py

```sql
CREATE TABLE retention_policies (
    id BIGSERIAL PRIMARY KEY,
    subject TEXT NOT NULL UNIQUE,
    retention_days INTEGER NOT NULL CHECK (retention_days > 0),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

INSERT INTO retention_policies (subject, retention_days)
VALUES
  ('transitions.raw', 90),
  ('events.aggregated', 365);
```

## Notes for Implementation

- Store only hashed device tokens; never persist plaintext bearer tokens.
- `client_event_id` uniqueness in `transitions` enforces ingestion idempotency.
- `jobs` table fields satisfy V2 requirements: `status`, `attempts`,
  `next_run_at`, `locked_at`, `error_code`.
- Add periodic purge workers using `retention_delete_after` and
  `retention_policies`.

