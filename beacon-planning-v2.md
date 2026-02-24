# Beacon — Alternative Planning Document (Risk-First)

**Project:** Beacon — Personal Location-Aware Context Engine  
**Author:** Dennis  
**Date:** February 23, 2026  
**Status:** Proposed Replacement Plan

---

## 1. Why This Plan Exists

The original plan is feature-complete but execution-risk heavy. This alternative plan prioritizes:

1. Reliability before intelligence
2. Security/privacy before multi-user growth
3. Measurable platform validation before committing to assumptions
4. Incremental release gates with explicit exit criteria

This is a realistic solo-builder plan with contingency.

---

## 2. Scope and Success Criteria

## 2.1 MVP Scope (In)

- Passive transition capture on iOS (visits + significant location changes)
- Durable, idempotent server ingestion
- Deterministic event builder that produces a usable timeline
- Context surfacing through Wallet pass updates and optional notifications
- Basic Reminders sync for shopping list use case
- Optional Google Calendar sync only after timeline reliability is proven

## 2.2 Out of Scope for MVP (Out)

- Multi-user social features
- Live Activities beyond basic prototype
- Fully autonomous LLM actions without guardrails
- Advanced historical behavior prediction

## 2.3 MVP Success Criteria

- >=95% of transition uploads accepted and persisted within 5 seconds
- <1% duplicate transition records after idempotency controls
- >=85% place resolution judged correct by user correction feedback
- 0 known security incidents; tested token revocation and device removal
- Daily battery impact acceptable for primary tester (subjective + Instruments validation)

---

## 3. Architecture (Revised for Reliability)

## 3.1 Core Principle

The ingestion request path does **not** call external providers (Google/OpenAI/APNs). It only validates, stores, and queues work.

## 3.2 Data Flow

1. iOS sends transition with `client_event_id` (UUIDv7) and `sent_at`.
2. API validates auth, enforces idempotency, writes transition row, writes job row, returns `202 Accepted`.
3. Worker consumes jobs and performs:
   - place resolution
   - event state updates
   - policy evaluation
   - optional action dispatch (pass update/notification)
4. Action worker handles APNs/Wallet updates with retries and dead-letter logging.
5. Observability pipeline records ingestion latency, duplicate rate, queue depth, and downstream failures.

## 3.3 Queue Strategy

Start with PostgreSQL-backed job tables (`FOR UPDATE SKIP LOCKED`) to avoid early infrastructure sprawl. Revisit Redis/SQS only if queue latency exceeds SLO.

## 3.4 Idempotency Contract

- Client includes `client_event_id` per transition.
- DB unique constraint: `(device_id, client_event_id)`.
- Server returns existing record on duplicate submissions.
- Event builder uses deterministic merge rules for near-identical points.

---

## 4. Security and Privacy Baseline

## 4.1 Auth and Device Security

- Per-device bearer token (256-bit random), stored hashed (SHA-256 or Argon2id)
- Token rotation endpoint + emergency revocation
- Device-scoped permissions only (no cross-user reads)
- TLS everywhere; no HTTP fallback

## 4.2 Secrets Management

- APNs, Google, OpenAI, and signing keys stored only in Fly secrets
- No plaintext secrets in repo or logs
- Monthly key rotation checklist for non-Apple credentials

## 4.3 Data Minimization and Retention

- Raw transitions retained 90 days
- Aggregated events retained 12 months (configurable)
- User can delete all data + revoke all devices from app settings
- Add export endpoint (`JSON`) before adding non-owner users

## 4.4 Access and Audit

- Structured audit log for sensitive operations: login/register, token rotate/revoke, export, delete
- Correlation ID on every API request and worker job

---

## 5. LLM Integration Policy (Constrained)

LLM is advisory, not authoritative, at first.

1. Deterministic policy engine decides whether to invoke LLM
2. LLM output validated against strict JSON schema
3. Allowed actions initially:
   - `none`
   - `suggest_pass_content` (non-destructive)
4. Guardrails:
   - cooldown (e.g., no more than one suggestion per place per 30 minutes)
   - daily action budget per user
   - fallback to deterministic templates on parse/policy failure
5. Rollout:
   - shadow mode first (log only)
   - then canary execution for single user

---

## 6. iOS Assumption Validation Plan

Before heavy implementation, run focused spikes:

- CLVisit latency distribution in real-world usage
- Background wake reliability (terminated/suspended states)
- Wi-Fi SSID availability in background under target permissions
- Focus status availability and utility for decisions
- Battery cost of motion + location strategy via Instruments

Any signal failing reliability/value thresholds is removed from MVP inputs.

## 6.1 Hybrid Transition Detection Policy (Fast + Confirmed)

Use a two-stage transition model so short visits can still trigger timely context:

1. **Fast provisional detection** from motion + significant change (+ optional one-shot precise fix)
2. **Authoritative confirmation** from CLVisit arrival/departure when available

Signal roles:

- `CLVisit`: high-confidence arrival/departure, low power, delayed callbacks tolerated
- `significant_location_change`: coarse movement boundary between places
- `motion_activity`: quick travel start/stop hints
- optional geofence enter/exit: instant known-place transitions when configured

Policy rules:

1. Emit a provisional departure/travel transition when motion changes from
   stationary to walking/cycling/automotive and movement is corroborated by
   significant-change or a short precise-fix burst.
2. Emit a provisional arrival when motion returns to stationary near a new place
   and remains stable for a short dwell window.
3. Confirm and backfill transition timing when CLVisit arrival/departure arrives.
4. If no CLVisit confirmation arrives within a timeout window, keep the event as
   inferred (lower confidence) and avoid aggressive user-facing actions.

Battery guardrails:

- No continuous high-accuracy location tracking
- One-shot precise bursts only on motion edge transitions
- Auto-stop precise updates immediately after acceptable fix
- Tighten/disable burst behavior in Low Power Mode

Phase 0 must measure:

- time-to-first provisional detection
- provisional-to-confirmed delay
- % of provisional transitions later confirmed by CLVisit
- false-positive rate for short-stop trips (for example, quick grocery runs)
- incremental battery impact versus CLVisit-only baseline

---

## 7. Realistic Timeline (18 Weeks + 2-Week Buffer)

Start date: **February 23, 2026**  
Target beta-ready date: **June 28, 2026**  
Contingency buffer: **June 29, 2026 to July 12, 2026**

### Phase 0 — Validation Spikes (2 weeks, Feb 23 to Mar 8)

**Goal:** De-risk iOS platform assumptions and finalize MVP signal set.

Deliverables:
- Spike app collecting visit/motion/background behavior logs
- Short report: reliability + battery findings
- Finalized signal contract for server ingestion

Exit criteria:
- Clear go/no-go on SSID and Focus signals
- Confirmed baseline for CLVisit latency and wake behavior

### Phase 1 — Secure Ingestion Backbone (3 weeks, Mar 9 to Mar 29)

**Goal:** Build production-grade ingestion and storage foundation.

Deliverables:
- Device registration/auth with hashed tokens + rotation/revocation
- Transition ingestion endpoint with idempotency
- PostgreSQL schema + migrations + job table
- Structured logging + core metrics dashboards

Exit criteria:
- Duplicate retries do not create duplicate rows
- p95 ingest request latency under target in local/staging load test

### Phase 2 — Deterministic Timeline Engine (3 weeks, Mar 30 to Apr 19)

**Goal:** Turn transitions into coherent events without LLM dependency.

Deliverables:
- Event state machine implementation
- Place resolver with cache and confidence scoring
- User correction API and replay-safe recomputation path

Exit criteria:
- Timeline accuracy acceptable in daily use for primary tester
- Queue/backfill/replay works without data corruption

### Phase 3 — Wallet Pass and Action Dispatch (3 weeks, Apr 20 to May 10)

**Goal:** Deliver contextual value without LLM complexity.

Deliverables:
- Pass signing/generation and Apple web service endpoints
- APNs action dispatcher with retries + dead-letter records
- Deterministic rules: grocery arrival -> shopping list pass

Exit criteria:
- End-to-end pass refresh works reliably on device
- Failed pushes retried and observable

### Phase 4 — Reminders Sync + LLM Shadow Mode (3 weeks, May 11 to May 31)

**Goal:** Introduce LLM safely behind policy controls.

Deliverables:
- EventKit reminders sync path (app -> server)
- Policy engine and JSON-schema validation
- LLM integration in shadow mode (no execution)
- Comparison report: deterministic vs LLM suggestions

Exit criteria:
- Shadow mode quality judged useful enough for canary
- No increase in operational incidents from LLM pipeline

### Phase 5 — Calendar Sync + Privacy Controls (2 weeks, Jun 1 to Jun 14)

**Goal:** Add secondary integrations after core reliability.

Deliverables:
- Google Calendar OAuth + dedicated Beacon calendar
- Event create/update with dedupe keys
- Data export and delete-all endpoints

Exit criteria:
- No duplicate calendar events in regression tests
- Privacy lifecycle (export/delete) validated end-to-end

### Phase 6 — Hardening and Beta (2 weeks, Jun 15 to Jun 28)

**Goal:** Stabilize for daily use and limited friend pilot.

Deliverables:
- Runbooks (incident, key rotation, backup/restore)
- Load + chaos tests for worker retries and provider failures
- Beta checklist and release candidate

Exit criteria:
- SLOs met for 14 consecutive days
- No unresolved P0/P1 defects

---

## 8. Milestone Gates (No Gate, No Progression)

1. **Gate A (after Phase 0):** Signal set validated
2. **Gate B (after Phase 1):** Idempotent ingestion + security baseline complete
3. **Gate C (after Phase 3):** Core user value works without LLM
4. **Gate D (after Phase 4):** LLM quality and safety accepted for controlled rollout
5. **Gate E (after Phase 6):** Beta readiness sign-off

---

## 9. Revised Data Model Requirements

Mandatory additions to schema design:

- `transitions.client_event_id` (NOT NULL)
- UNIQUE `(device_id, client_event_id)`
- `jobs` table with status, attempts, next_run_at, locked_at, error_code
- `audit_log` table for sensitive operations
- `devices.auth_token_hash` (replace plaintext token storage)
- Retention timestamps and purge jobs

---

## 10. Observability and Testing Strategy (Day One)

## 10.1 Metrics

- Ingest request count, success/failure rate
- Duplicate request rate
- Queue depth and age
- Worker success/failure by job type
- External API latency/error rates
- Push delivery attempts and failures

## 10.2 Tests

- Contract tests for ingestion idempotency
- Replay tests for event builder determinism
- Integration tests for pass update protocol
- Failure-injection tests (provider timeout, APNs failure, DB reconnect)

## 10.3 Release Controls

- Feature flags for LLM execution, Calendar sync, and advanced signals
- Canary rollout for high-risk features
- Kill switch for all action dispatch

---

## 11. Resource and Dependency Plan

- Solo development assumption: 18 weeks + 2-week buffer is realistic
- External dependency setup deadlines:
  - Apple Developer + Pass cert by end of Phase 1
  - Google APIs by start of Phase 2
  - OpenAI key by start of Phase 4

If any dependency slips, do not block core timeline engine work.

---

## 12. Immediate Next Actions (This Week)

1. Build Phase 0 spike app branch and instrumentation checklist
2. Define transition payload schema including idempotency fields
3. Draft DB migration set for Phase 1 (`devices`, `transitions`, `jobs`, `audit_log`)
4. Set initial SLO targets and dashboard placeholders

---

This document replaces feature-first sequencing with a reliability-first plan intended to ship a stable personal product before expanding scope.
