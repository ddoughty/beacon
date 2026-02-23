# Beacon — Project Planning Document

**Project:** Beacon — Personal Location-Aware Context Engine
**Author:** Dennis
**Date:** February 2026
**Status:** Planning

---

## 1. Project Overview

Beacon is a personal life-logging and contextual awareness system consisting of a native iOS app and a Python server backend. The app passively captures location transitions and device context, uploads them to the server, and receives contextual actions in return — such as surfacing a shopping list when arriving at a grocery store, or displaying a loyalty card at a restaurant.

The system generates a structured event stream ("bike ride from home to Trader Joe's, 12 minutes"), feeds events into an LLM for contextual reasoning, and synchronizes the resulting timeline to Google Calendar for later reference.

### Target Users

Dennis and a small number of friends. No App Store submission required; distribution via TestFlight or direct Xcode installation in developer mode.

### Working Name

**Beacon**

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                      iOS App (Swift)                     │
│                                                         │
│  CLVisit + CLLocationManager + CMMotionActivityManager   │
│  INFocusStatusCenter + Wi-Fi SSID + Bluetooth Beacons    │
│            │                          ▲                  │
│            │ location + context       │ commands         │
│            ▼                          │ (APNs)           │
├─────────────────────────────────────────────────────────┤
│                    HTTPS REST API                        │
├─────────────────────────────────────────────────────────┤
│                  Server (Starlette/Python)               │
│                     on Fly.io                            │
│                                                         │
│  ┌──────────┐  ┌────────────┐  ┌──────────────────────┐ │
│  │ Location  │  │  Event     │  │  LLM Reasoning       │ │
│  │ Resolver  │  │  Builder   │  │  (OpenAI API)        │ │
│  └──────────┘  └────────────┘  └──────────────────────┘ │
│  ┌──────────┐  ┌────────────┐  ┌──────────────────────┐ │
│  │ Wallet   │  │  Google    │  │  APNs Push           │ │
│  │ Pass Mgr │  │  Calendar  │  │  Service             │ │
│  └──────────┘  └────────────┘  └──────────────────────┘ │
│                       │                                  │
│                  PostgreSQL                               │
│               (Fly.io Managed)                           │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

1. **iOS app** detects a location transition (arrival, departure, mode change) and uploads a context snapshot to the server
2. **Server** resolves the raw coordinates to a place via reverse geocoding (Google Places API)
3. **Event Builder** assembles or updates a high-level event from accumulated transitions ("arrived at Trader Joe's at 2:15 PM")
4. **LLM Reasoning** evaluates the event and determines if an action is warranted
5. **Action Executor** carries out the LLM's suggestion — update a wallet pass, send a push notification, etc.
6. **Calendar Sync** writes finalized events to Google Calendar

---

## 3. iOS App Design

### 3.1 Development Approach

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI (minimal UI needs; primary view is an event timeline)
- **Minimum Target:** iOS 17 (for ActivityKit push support and latest CoreLocation APIs)
- **Distribution:** TestFlight (up to 100 testers, no App Store review for internal testing) or direct Xcode install

### 3.2 Background Location Strategy

The app uses a **hybrid approach optimized for battery life**, focusing on transitions rather than continuous tracking:

**Primary: CLVisit Monitoring**
- Extremely battery-efficient
- Fires when user arrives at or departs from a location where they dwell
- Provides arrival time, departure time, and coordinates
- Latency: visits may be reported with a delay (minutes to hours), but typically within a few minutes for departures

**Secondary: Significant Location Change Monitoring**
- Cell-tower-level granularity (~500m)
- Fires on cell tower transitions — catches movement between visits
- Used to detect travel mode transitions

**Supplementary: Targeted Precise Location**
- Brief bursts of `kCLLocationAccuracyBest` when motion activity changes (e.g., user starts cycling)
- Used to get a precise fix at the start/end of a travel segment
- Auto-stops after fix is acquired to conserve battery

**Geofence Layer (Server-Managed)**
- Server pushes up to 20 geofences for frequently-visited or important locations
- Provides instant arrival/departure detection for known places
- Registered via `CLCircularRegion` monitoring

### 3.3 Context Capture

At each transition event, the app captures and uploads:

| Signal | Source | Background Access |
|--------|--------|-------------------|
| Location (lat/lng/accuracy) | CLLocationManager | Yes, with "Always" auth |
| Travel mode | CMMotionActivityManager | Yes |
| Current Wi-Fi SSID | NEHotspotNetwork | Yes, with location permission |
| Focus mode | INFocusStatusCenter | Yes (read-only) |
| Battery level | UIDevice | Yes |
| Timestamp | System | Yes |
| Bluetooth beacons (future) | CLBeaconRegion | Yes |

### 3.4 Server Communication

**Upstream (app → server):** HTTPS POST on each transition event. Events are queued locally in CoreData/SwiftData if the network is unavailable and flushed when connectivity resumes.

**Downstream (server → app):** APNs push notifications, in several categories:

- **Silent push** (`content-available`): triggers background app wake to update geofences, refresh config, etc.
- **Wallet pass update push**: signals the app to fetch updated pass data
- **Live Activity update push**: updates Dynamic Island / lock screen Live Activity content
- **Visible notification**: displays a user-facing notification with optional action buttons

**Authentication:** Simple bearer token per device, issued at registration. Given the tiny user base, a shared secret or device-specific token is sufficient — no need for OAuth.

### 3.5 Wallet Pass Integration

This is the primary mechanism for surfacing contextual information on the lock screen.

**How it works:**
1. Server generates a signed `.pkpass` file for the user
2. User adds the pass to Apple Wallet (one-time setup)
3. Server sends APNs push to the pass's push token when content should change
4. iOS calls back to the server to fetch the updated pass
5. Pass content updates on the lock screen (if relevant by time/location)

**Pass content structure:**
- **Header field:** Current context label (e.g., "Shopping")
- **Primary field:** Main content (e.g., shopping list items, loyalty card barcode)
- **Secondary fields:** Supporting info (store name, time)
- **Back fields:** Extended information, recent timeline

**Pass types to consider:**
- `generic` — most flexible, good for the default "contextual info" pass
- `storeCard` — if displaying loyalty cards with barcodes

**Pass relevance:**
- `relevantLocations` can be set dynamically to make the pass auto-surface at the right places
- `relevantDate` can trigger time-based surfacing

### 3.6 Live Activities (Supplementary)

Live Activities complement wallet passes for active/transient contexts:

- "Currently biking — 12 min, 2.3 mi"
- "At Trader Joe's — 20 min"

Live Activities are started/updated via ActivityKit push notifications from the server. They auto-expire after 8-12 hours. Best suited for in-progress activities rather than persistent ambient display.

### 3.7 In-App UI

The app's UI is minimal — it runs in the background almost always. When opened:

**Primary view: Event Timeline**
- Scrollable list of recent events, most recent first
- Each event shows: icon (based on type), place name, time range, travel mode
- Tapping an event shows details and allows correction of place name

**Secondary views:**
- Device registration / server connection status
- Tracking status indicator (active, paused, permissions)

### 3.8 Required iOS Permissions

| Permission | Purpose | Type |
|------------|---------|------|
| Location — Always | Background location monitoring | Required |
| Motion & Fitness | Travel mode detection | Required |
| Notifications | Server commands, alerts | Required |
| Local Network | Wi-Fi SSID detection | Required |
| Focus Status | Read current Focus mode | Optional |

### 3.9 Key iOS Frameworks

- `CoreLocation` — visits, significant change, geofences, standard location
- `CoreMotion` — motion activity (walking, cycling, driving, stationary)
- `PassKit` — wallet pass management
- `ActivityKit` — Live Activities and Dynamic Island
- `UserNotifications` — push notification handling
- `Network` / `NEHotspotNetwork` — Wi-Fi SSID
- `Intents` — Focus status reading
- `BackgroundTasks` — BGAppRefreshTask for periodic maintenance
- `SwiftData` or `CoreData` — local event queue and cache

---

## 4. Server Design

### 4.1 Technology Stack

- **Framework:** Starlette (Python 3.12+)
- **Database:** PostgreSQL (Fly.io managed)
- **ORM/Query:** asyncpg with raw SQL or SQLAlchemy async
- **Task Queue:** None initially — synchronous processing per request is fine at this scale; if needed later, add a simple background task with Starlette's `BackgroundTask`
- **Hosting:** Fly.io (single region, single instance to start)

### 4.2 API Endpoints

#### Device Management
```
POST   /api/devices/register     — Register a new device, returns auth token
GET    /api/devices/{id}/config  — Get current config (geofences, settings)
```

#### Location & Context Ingestion
```
POST   /api/events/transition    — Report a location transition with context
POST   /api/events/heartbeat     — Periodic alive signal with current state
```

#### Event Stream
```
GET    /api/events               — List events (paginated, filterable by date)
PATCH  /api/events/{id}          — Correct event details (e.g., place name)
```

#### Wallet Pass
```
GET    /v1/passes/{passTypeId}/{serialNumber}  — Apple Wallet pass update endpoint
POST   /v1/devices/{deviceId}/registrations/{passTypeId}/{serialNumber}  — Pass registration
DELETE /v1/devices/{deviceId}/registrations/{passTypeId}/{serialNumber}  — Pass unregistration
GET    /v1/devices/{deviceId}/registrations/{passTypeId}  — List updated passes
```

Note: The wallet pass endpoints follow Apple's required URL structure for pass updates.

### 4.3 Location Resolution Pipeline

When a transition arrives:

1. **Reverse geocode** the coordinates via Google Places API (`nearbysearch` or `findplacefromtext`)
2. **Candidate ranking:** If multiple places are nearby, rank by:
   - Distance from reported coordinates
   - Place type relevance (e.g., restaurant at lunchtime scores higher)
   - Historical frequency (user has been here before)
   - Time-of-day heuristics (grocery store at 6 PM > office supply store)
3. **Store top candidate** as the resolved place, flag confidence level
4. **If confidence is low**, mark for user review (surfaced in the app timeline)

**Caching:** Cache resolved places by geohash to avoid redundant API calls for return visits.

### 4.4 Event Builder

The event builder maintains a state machine per user:

```
IDLE → TRAVELING → DWELLING → IDLE
         │                      │
         └──────────────────────┘
```

**State transitions:**
- `IDLE → TRAVELING`: Motion activity changes from stationary to walking/cycling/driving
- `TRAVELING → DWELLING`: Visit arrival detected or stationary for >3 minutes at a new location
- `DWELLING → TRAVELING`: Visit departure detected or motion activity changes
- `DWELLING → IDLE`: Arrival at a known "home" location

**Event fields:**
```json
{
  "id": "uuid",
  "user_id": "uuid",
  "type": "visit|travel|activity",
  "started_at": "2026-02-22T14:15:00Z",
  "ended_at": "2026-02-22T14:52:00Z",
  "place": {
    "name": "Trader Joe's",
    "address": "1317 Beacon St, Brookline, MA",
    "category": "grocery_store",
    "lat": 42.3425,
    "lng": -71.1220,
    "confidence": 0.92,
    "place_id": "google_place_id"
  },
  "travel_mode": null,
  "context": {
    "focus_mode": "personal",
    "wifi_ssid": null,
    "battery": 72
  },
  "calendar_event_id": "google_calendar_event_id",
  "reviewed": false
}
```

### 4.5 LLM Reasoning Engine

When an event starts or updates, the server sends context to the OpenAI API (gpt-4o or equivalent) with a structured prompt:

**System prompt (condensed):**
```
You are a personal context assistant. Given the user's current situation,
suggest zero or one action from the allowed set. Respond with JSON only.

Allowed actions:
- update_pass: Update the wallet pass content. Provide fields.
- notify: Send a notification. Provide title and body.
- none: No action needed.

Consider: time of day, place category, day of week, user history.
Be conservative — only suggest actions that provide clear value.
```

**User prompt:**
```json
{
  "event": "arrived at Trader Joe's (grocery store)",
  "time": "Saturday 2:15 PM",
  "duration_so_far": "just arrived",
  "recent_history": ["left home at 2:00 PM, cycled 15 min"],
  "user_lists": ["Shopping: milk, eggs, bread, coffee"],
  "available_passes": ["loyalty:none for this store"]
}
```

**Expected response:**
```json
{
  "action": "update_pass",
  "reasoning": "User just arrived at grocery store, surface their shopping list",
  "pass_content": {
    "header": "Shopping List",
    "primary": "Trader Joe's",
    "secondary": ["milk", "eggs", "bread", "coffee"],
    "relevant_location": { "lat": 42.3425, "lng": -71.1220 }
  }
}
```

**Autonomy model:** Trust the vibes — the LLM's suggested action is executed without human approval. The action space is constrained (update a pass, send a notification, or do nothing), so the downside of a wrong action is minimal — a slightly irrelevant lock screen card.

### 4.6 Apple Reminders Integration

The server needs to fetch the user's shopping list from Apple Reminders to surface it in wallet passes. This is the trickiest integration because Apple Reminders has no public REST API.

**Options (in order of practicality):**

1. **iOS app reads Reminders and syncs to server:** The app uses `EventKit` to read Reminders lists and periodically uploads list contents to the server. This is the most reliable approach and keeps Apple auth on-device where it belongs.

2. **iCloud web API (unofficial):** There are reverse-engineered iCloud APIs, but they're fragile and require iCloud credentials. Not recommended.

3. **Shortcuts automation:** An iOS Shortcut that reads a Reminders list and POSTs it to the server, triggered periodically or on list change. Workable but brittle.

**Recommended approach:** Option 1. The iOS app syncs Reminders list contents to the server every time the app wakes for a location transition (and on a periodic BGAppRefreshTask). This keeps the data reasonably fresh without extra complexity.

### 4.7 Google Calendar Sync

**Approach:** Hybrid — create tentative events in near-real-time, finalize them when the event ends.

**Flow:**
1. When an event starts (user arrives at a place), create a Google Calendar event with:
   - Title: "At Trader Joe's" (or "Cycling" for travel)
   - Start time: arrival time
   - End time: current time (will be updated)
   - Description: Place details, travel mode, context
   - Status: tentative

2. When the event ends (user departs), update the calendar event:
   - Set actual end time
   - Update description with final details
   - Set status to confirmed

3. If hybrid proves complex, fall back to retrospective-only: create events only after departure.

**Auth:** OAuth 2.0 with Google Calendar API. Use a refresh token stored server-side. Initial auth flow via a one-time browser-based consent flow.

**Calendar:** Create a dedicated "Beacon" calendar so events don't clutter the user's primary calendar.

### 4.8 Wallet Pass Signing & Distribution

**Pass creation flow:**
1. Server generates pass.json with current content
2. Server signs the pass using the Pass Type ID certificate
3. Signed .pkpass is served to the device or sent via the update flow

**Pass update flow (Apple's protocol):**
1. Server sends an empty APNs push to the pass's device token
2. iOS calls `GET /v1/devices/{deviceId}/registrations/{passTypeId}` to check for updates
3. iOS calls `GET /v1/passes/{passTypeId}/{serialNumber}` to download the updated pass
4. Pass refreshes on the device

**Server-side signing:** Use the `passbook` or `wallet-py` Python library, or sign manually with OpenSSL using the Pass Type ID certificate and key.

### 4.9 APNs Push Service

The server needs to send several types of push notifications:

| Type | Purpose | APNs Topic |
|------|---------|------------|
| Wallet pass update | Trigger pass refresh | Pass Type ID |
| Silent push | Wake app for background work | App Bundle ID |
| Live Activity update | Update Dynamic Island | App Bundle ID + `.push-type.liveactivity` |
| Visible notification | User-facing alerts | App Bundle ID |

**Library:** `aioapns` (async Python APNs client) or `PyAPNs2`.

**Auth:** Token-based APNs auth (`.p8` key) is simpler than certificate-based and works for all push types.

---

## 5. Data Model (PostgreSQL)

### Core Tables

```sql
-- Users and their devices
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    name TEXT,  -- "Dennis's iPhone"
    auth_token TEXT UNIQUE NOT NULL,
    apns_token TEXT,  -- for push notifications
    pass_push_token TEXT,  -- for wallet pass updates
    created_at TIMESTAMPTZ DEFAULT now(),
    last_seen_at TIMESTAMPTZ
);

-- Raw transition reports from devices
CREATE TABLE transitions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id UUID REFERENCES devices(id),
    timestamp TIMESTAMPTZ NOT NULL,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    transition_type TEXT NOT NULL,  -- 'arrival', 'departure', 'mode_change', 'heartbeat'
    travel_mode TEXT,  -- 'stationary', 'walking', 'cycling', 'automotive'
    focus_mode TEXT,
    wifi_ssid TEXT,
    battery_level REAL,
    raw_payload JSONB  -- full context snapshot
);

-- Resolved places (cached reverse geocoding)
CREATE TABLE places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    google_place_id TEXT UNIQUE,
    name TEXT NOT NULL,
    address TEXT,
    category TEXT,  -- google place type
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    geohash TEXT NOT NULL,  -- for spatial lookups
    metadata JSONB,  -- hours, phone, etc.
    created_at TIMESTAMPTZ DEFAULT now()
);

-- High-level events (the timeline)
CREATE TABLE events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    event_type TEXT NOT NULL,  -- 'visit', 'travel', 'activity'
    started_at TIMESTAMPTZ NOT NULL,
    ended_at TIMESTAMPTZ,  -- null while in progress
    place_id UUID REFERENCES places(id),
    place_name_override TEXT,  -- user correction
    travel_mode TEXT,
    confidence REAL,
    context JSONB,
    google_calendar_event_id TEXT,
    reviewed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- User's synced lists (from Apple Reminders)
CREATE TABLE user_lists (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    list_name TEXT NOT NULL,
    items JSONB NOT NULL,  -- [{title, completed, ...}]
    synced_at TIMESTAMPTZ DEFAULT now()
);

-- Known/favorite places per user (for geofencing and preference)
CREATE TABLE user_places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id),
    place_id UUID REFERENCES places(id),
    label TEXT,  -- 'home', 'work', 'gym', custom
    visit_count INTEGER DEFAULT 0,
    last_visited_at TIMESTAMPTZ,
    geofence_enabled BOOLEAN DEFAULT false,
    geofence_radius REAL DEFAULT 100.0  -- meters
);

-- LLM action log
CREATE TABLE llm_actions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID REFERENCES events(id),
    prompt JSONB,
    response JSONB,
    action_type TEXT,  -- 'update_pass', 'notify', 'none'
    executed BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_transitions_device_time ON transitions(device_id, timestamp DESC);
CREATE INDEX idx_events_user_time ON events(user_id, started_at DESC);
CREATE INDEX idx_places_geohash ON places(geohash);
CREATE INDEX idx_user_places_user ON user_places(user_id);
```

---

## 6. External Dependencies & Certificates

### 6.1 Apple Developer Program

| Item | Purpose | Cost |
|------|---------|------|
| Apple Developer Program enrollment | Required for everything below | $99/year |
| APNs Authentication Key (.p8) | Push notifications (all types) | Included |
| Pass Type ID Certificate | Signing wallet passes | Included |
| App ID with capabilities | Push, background modes, wallet | Included |
| Provisioning Profile | Install on devices | Included |

**Required App ID Capabilities:**
- Push Notifications
- Background Modes (location, fetch, remote-notification, processing)
- Wallet (PassKit)
- Access WiFi Information

### 6.2 Google APIs

| API | Purpose | Cost |
|-----|---------|------|
| Google Places API (New) | Reverse geocoding, place details | $0 for first $200/month credit; ~$17/1000 requests after |
| Google Calendar API | Event sync | Free |

**Setup:** Google Cloud project → enable APIs → create OAuth 2.0 credentials (Calendar) and API key (Places).

### 6.3 OpenAI API

| Item | Purpose | Cost |
|------|---------|------|
| OpenAI API key | LLM reasoning for contextual actions | ~$0.005-0.01 per event (gpt-4o-mini) |

At personal usage levels (maybe 20-50 events/day), this would cost well under $1/month.

### 6.4 Fly.io

| Resource | Purpose | Estimated Cost |
|----------|---------|---------------|
| App machine (shared-cpu-1x, 256MB) | Starlette server | ~$2-5/month |
| Managed Postgres (single node) | Database | ~$0/month (free tier) or ~$15/month (1GB) |

### 6.5 Summary of Estimated Monthly Costs

| Item | Cost |
|------|------|
| Apple Developer Program | ~$8.25/month ($99/year) |
| Google APIs | ~$0 (within free tier for personal use) |
| OpenAI API | ~$1/month |
| Fly.io hosting | ~$5-20/month |
| **Total** | **~$15-30/month** |

---

## 7. Repository Structure

Monorepo layout:

```
beacon/
├── README.md
├── .gitignore
│
├── ios/                          # Xcode project
│   ├── Beacon.xcodeproj/
│   ├── Beacon/
│   │   ├── App/
│   │   │   ├── BeaconApp.swift           # App entry point
│   │   │   └── AppDelegate.swift         # Push notification handling
│   │   ├── Models/
│   │   │   ├── TransitionEvent.swift     # Context snapshot model
│   │   │   ├── TimelineEvent.swift       # Server event model
│   │   │   └── DeviceConfig.swift        # Server-pushed config
│   │   ├── Services/
│   │   │   ├── LocationService.swift     # CLVisit + significant change + geofences
│   │   │   ├── MotionService.swift       # CMMotionActivityManager
│   │   │   ├── ContextService.swift      # Aggregates all context signals
│   │   │   ├── APIService.swift          # Server communication
│   │   │   ├── PushService.swift         # APNs token management
│   │   │   ├── WalletService.swift       # PassKit integration
│   │   │   ├── LiveActivityService.swift # ActivityKit management
│   │   │   └── RemindersService.swift    # EventKit Reminders sync
│   │   ├── Views/
│   │   │   ├── TimelineView.swift        # Main event timeline
│   │   │   ├── EventDetailView.swift     # Event detail + correction
│   │   │   └── StatusView.swift          # Connection & tracking status
│   │   ├── Persistence/
│   │   │   └── LocalStore.swift          # SwiftData queue for offline events
│   │   └── Extensions/
│   │       └── ...
│   ├── BeaconWidget/                     # Live Activity widget extension
│   │   ├── BeaconLiveActivity.swift
│   │   └── BeaconWidgetBundle.swift
│   └── Shared/
│       └── BeaconActivityAttributes.swift  # Shared Live Activity definition
│
├── server/                       # Python backend
│   ├── pyproject.toml
│   ├── Dockerfile
│   ├── alembic/                  # Database migrations
│   │   ├── alembic.ini
│   │   └── versions/
│   ├── app/
│   │   ├── main.py               # Starlette app entry point
│   │   ├── config.py             # Settings, env vars
│   │   ├── database.py           # asyncpg connection pool
│   │   ├── auth.py               # Bearer token validation
│   │   ├── routes/
│   │   │   ├── devices.py        # Device registration
│   │   │   ├── transitions.py    # Location/context ingestion
│   │   │   ├── events.py         # Event stream CRUD
│   │   │   └── wallet.py         # Apple Wallet pass endpoints
│   │   ├── services/
│   │   │   ├── location_resolver.py   # Google Places reverse geocoding
│   │   │   ├── event_builder.py       # State machine, event assembly
│   │   │   ├── llm_engine.py          # OpenAI integration
│   │   │   ├── action_executor.py     # Dispatch LLM actions
│   │   │   ├── push_service.py        # APNs client
│   │   │   ├── pass_service.py        # Wallet pass generation & signing
│   │   │   └── calendar_sync.py       # Google Calendar integration
│   │   └── models/
│   │       └── schemas.py             # Pydantic models
│   ├── certs/                    # .gitignored — APNs keys, pass certs
│   │   └── .gitkeep
│   └── passes/
│       └── templates/            # Pass template assets (icon, logo, etc.)
│
├── docs/
│   ├── PLANNING.md               # This document
│   ├── SETUP.md                  # Development environment setup
│   └── API.md                    # API documentation
│
├── scripts/
│   ├── create_pass_cert.sh       # Helper to generate pass signing cert
│   └── seed_places.py            # Seed known places (home, work, etc.)
│
└── fly.toml                      # Fly.io deployment config
```

---

## 8. Phased Implementation Plan

### Phase 1: Foundation (Weeks 1-3)

**Goal:** iOS app tracks location and sends transitions to the server; server stores them and resolves places.

**iOS:**
- [ ] Create Xcode project with SwiftUI
- [ ] Implement `LocationService` with CLVisit + significant location change
- [ ] Implement `MotionService` for travel mode
- [ ] Implement `ContextService` to aggregate signals
- [ ] Build `APIService` with offline queue
- [ ] Request permissions on first launch
- [ ] Minimal timeline UI showing raw transitions

**Server:**
- [ ] Starlette app scaffold with asyncpg
- [ ] Device registration endpoint
- [ ] Transition ingestion endpoint
- [ ] Google Places reverse geocoding integration
- [ ] PostgreSQL schema + Alembic migrations
- [ ] Deploy to Fly.io

**Infra:**
- [ ] Enroll in Apple Developer Program
- [ ] Create Google Cloud project, enable Places API
- [ ] Set up Fly.io app + managed Postgres
- [ ] Generate APNs authentication key (.p8)

### Phase 2: Event Stream (Weeks 4-5)

**Goal:** Server builds coherent events from transitions; timeline shows resolved events.

**Server:**
- [ ] Implement event builder state machine
- [ ] Place caching by geohash
- [ ] Confidence scoring for place resolution
- [ ] Event CRUD API endpoints

**iOS:**
- [ ] Fetch and display server events in timeline
- [ ] Event detail view with place correction UI

### Phase 3: Wallet Pass & Push (Weeks 6-8)

**Goal:** Server sends contextual updates to the lock screen via wallet passes.

**Server:**
- [ ] Generate and sign wallet passes
- [ ] Implement Apple Wallet web service endpoints
- [ ] APNs push notification service
- [ ] Pass content update pipeline

**iOS:**
- [ ] Wallet pass download and add flow
- [ ] APNs token registration and forwarding to server
- [ ] Push notification handling (silent + visible)
- [ ] Pass update response handling

**Infra:**
- [ ] Create Pass Type ID and certificate in Apple Developer portal
- [ ] Configure pass signing on server

### Phase 4: LLM Integration (Weeks 9-10)

**Goal:** Server uses LLM reasoning to decide when and how to update the wallet pass.

**Server:**
- [ ] OpenAI API integration
- [ ] Prompt template for contextual reasoning
- [ ] Action executor (maps LLM response → pass update or notification)
- [ ] Action logging for debugging and iteration

**iOS:**
- [ ] Reminders sync via EventKit → server upload
- [ ] Display LLM-suggested actions in event detail view

### Phase 5: Calendar Sync & Polish (Weeks 11-12)

**Goal:** Events sync to Google Calendar; system is reliable for daily use.

**Server:**
- [ ] Google Calendar OAuth flow
- [ ] Calendar event creation (hybrid: tentative → confirmed)
- [ ] Dedicated "Beacon" calendar creation
- [ ] Event deduplication and update logic

**iOS:**
- [ ] Live Activity for in-progress events (optional/stretch)
- [ ] Geofence management from server config
- [ ] Battery optimization tuning

**General:**
- [ ] End-to-end testing with real-world usage
- [ ] Error handling and retry logic hardening
- [ ] Monitoring and logging

### Stretch Goals (Post-MVP)

- [ ] Multi-user geofence sharing ("Dennis is at the grocery store")
- [ ] Historical pattern analysis ("you usually go to the gym on Tuesdays")
- [ ] Automatic loyalty card barcode storage and surfacing
- [ ] Siri Shortcuts integration for advanced automations
- [ ] Web dashboard for timeline review and place management

---

## 9. Known Risks & Constraints

### iOS Platform Constraints

1. **CLVisit latency:** Visit arrivals are sometimes delayed by several minutes. Geofences for known places mitigate this for important locations.

2. **Background execution limits:** iOS aggressively suspends background apps. The combination of location background mode + push notifications provides reliable wake-ups, but there may be edge cases where the app is terminated and must be relaunched by the system.

3. **Shortcut execution:** Running arbitrary Shortcuts from the server without user confirmation is not reliably possible. The app can open shortcut URLs, but this requires user interaction. This limitation is accepted — the wallet pass and notification mechanisms cover the priority use cases.

4. **20 geofence limit:** iOS allows a maximum of 20 monitored regions per app. The server should prioritize the most useful locations.

5. **Apple Reminders access:** EventKit requires on-device access; there's no server-side API. The app must sync list contents proactively.

### API Cost Risks

6. **Google Places API costs:** At ~$17/1000 requests, aggressive geocoding could add up. Mitigate with geohash caching and only geocoding genuinely new locations.

### Reliability Risks

7. **LLM hallucination:** The LLM might suggest irrelevant actions. Since the action space is constrained and consequences are low (a wrong lock screen card), this is acceptable. Log all actions for review.

8. **Place disambiguation:** A location at a strip mall could match many businesses. The confidence scoring and user correction flow handle this, but early usage will require some manual correction to train the system's preferences.

### Security Considerations

9. **Location data sensitivity:** The server stores detailed location history. Ensure HTTPS everywhere, use strong auth tokens, and consider data retention policies. For a personal system, the risk is manageable, but be mindful if adding friends.

10. **Credential management:** APNs keys, Google API keys, and OpenAI keys must be stored securely on the server (Fly.io secrets) and never committed to the repo.

---

## 10. Development Environment Requirements

### iOS Development
- Mac with Xcode 15+
- Physical iPhone (location services require real device for testing)
- Apple Developer Program membership (active)

### Server Development
- Python 3.12+
- PostgreSQL (local for dev, or connect to Fly.io dev instance)
- Docker (for containerized deployment)

### Key Tools
- `flyctl` CLI for Fly.io deployment
- `openssl` for pass certificate management
- Xcode Instruments for battery profiling
- Postman or similar for API testing

---

*This document should be treated as a living plan. Update it as implementation reveals new constraints or opportunities.*
