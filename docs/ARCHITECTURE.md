# Elets SalesCall AI — Architecture

## 1. System overview

```
┌──────────────────────────┐        HTTPS (REST, JWT)        ┌──────────────────────────────────────────┐
│  Flutter app (mobile/)   │ ──────────────────────────────▶ │  FastAPI backend (backend/)              │
│  Riverpod · GoRouter     │ ◀────── WebSocket (events) ──── │                                          │
│  Material 3              │                                 │  api/v1        REST + WS endpoints       │
└──────────────────────────┘                                 │  services/     business logic            │
            ▲                                                │  telephony/    provider adapters         │
            │ FCM push                                       │  voice/        AI voice agent engine     │
            │                                                │  workers/      campaign runner, jobs     │
┌───────────┴──────────┐                                     │  realtime/     WS hub                    │
│ Firebase Cloud Msg   │ ◀────────── HTTP v1 ─────────────── │                                          │
└──────────────────────┘                                     └───────┬──────────────┬───────────────────┘
                                                                     │              │
                                         SQLAlchemy (asyncpg)        │              │  REST + webhooks + media WS
                                                                     ▼              ▼
                                                        ┌────────────────┐   ┌──────────────────────────────┐
                                                        │ PostgreSQL 16  │   │ Telephony provider           │
                                                        │ (Alembic)      │   │ Exotel / Twilio / Plivo /    │
                                                        └────────────────┘   │ Knowlarity                   │
                                                                             └──────────────┬───────────────┘
                                                                                            │ PSTN
                                                                                            ▼
                                                                                     Lead's phone

AI voice pipeline (per live AI call, inside the backend):

  provider media WS ──audio──▶ STT (Deepgram, streaming) ──final utterance──▶ Conversation engine
        ▲                                                                       │  LLM (Claude, streaming)
        └────────────audio◀── TTS (ElevenLabs) ◀──────────sentence chunks───────┘  tools: handoff / end / opt-out
```

Two independent calling systems share one lead database:

| Concern            | Human calling                          | AI calling                                       |
|--------------------|----------------------------------------|--------------------------------------------------|
| Table              | `human_calls`                          | `ai_calls`                                       |
| Origin             | `salesperson_id` (NOT NULL)            | `ai_agent_id` (NOT NULL) + `campaign_id`         |
| UI                 | Dialer tab, Call history               | AI Agents tab (dashboard, agents, campaigns, calls) |
| Stats              | `/analytics/*` human metrics           | `/ai/dashboard`, `/analytics/agents`, campaigns  |
| Unified reporting  | `v_unified_calls` SQL view (UNION ALL with an explicit `origin` column) |

Recordings, transcripts and notes live in their own tables and reference **exactly one** of
`human_call_id` / `ai_call_id` (enforced by a CHECK constraint), so no record is ambiguous.

## 2. Folder structure

```
VOICE/
├── README.md                     Quick start
├── docker-compose.yml            Postgres + backend (+ worker)
├── docs/
│   ├── ARCHITECTURE.md           This file
│   ├── API.md                    REST/WS contract
│   ├── DEPLOYMENT.md             Setup, environments, production deployment
│   └── COMPLIANCE.md             TRAI / consent / recording / AI disclosure notes
├── backend/
│   ├── requirements.txt
│   ├── .env.example              Every integration is configured here
│   ├── alembic.ini
│   ├── alembic/versions/         Database migrations
│   ├── app/
│   │   ├── main.py               App factory, routers, lifespan (starts workers)
│   │   ├── core/                 config, database, security (JWT, bcrypt), crypto (Fernet + blind index),
│   │   │                         permissions (RBAC), deps, time ranges, errors
│   │   ├── models/               SQLAlchemy models (one module per domain)
│   │   ├── schemas/              Pydantic request/response models
│   │   ├── api/v1/               auth, users, teams, leads, calls, recordings, followups,
│   │   │                         ai_agents, ai_calls, campaigns, analytics, notifications,
│   │   │                         settings, audit, webhooks, media (voice WS), ws (events)
│   │   ├── services/             leads, calls, ai_calls, campaigns, analytics, imports, exports,
│   │   │                         notifications, compliance, audit, call_locks, push (FCM)
│   │   ├── telephony/            base interface, registry, exotel, twilio, plivo, knowlarity
│   │   ├── voice/                stt/, tts/, llm/ provider interfaces + implementations,
│   │   │                         audio codecs, media adapters, conversation engine, intelligence
│   │   ├── realtime/             WebSocket hub (in-process pub/sub)
│   │   ├── workers/              campaign runner, follow-up reminders, daily summaries
│   │   └── seed.py               Roles, teams, users, sample leads, AI agent templates
│   └── tests/                    pytest suite (SQLite, fake telephony provider)
└── mobile/                       Flutter app
    ├── pubspec.yaml
    └── lib/
        ├── main.dart / app.dart
        ├── core/                 config (dart-defines), network (Dio, WS), storage, theme,
        │                         router (GoRouter + role guards), utils, shared widgets
        └── features/
            ├── auth/             login, session, current user
            ├── dashboard/        role-based dashboards, leaderboard, charts
            ├── leads/            list, filters, detail + timeline, form, import, bulk assign
            ├── dialer/           keypad, search, recents, favourites, live call screen, disposition
            ├── calls/            call history
            ├── ai_agents/        AI dashboard, agent list/editor, AI calls, transcript + intelligence
            ├── campaigns/        list, creation wizard, detail, controls, logs
            ├── analytics/        reports, date filters, exports
            ├── team/             users and teams (admin/manager)
            ├── notifications/
            └── profile/
```

Each Flutter feature follows `data/` (repository + models) → `providers/` (Riverpod) → `presentation/` (screens, widgets).

## 3. Backend design decisions

* **FastAPI + SQLAlchemy 2 async + asyncpg.** Alembic owns the schema; the app never calls `create_all` in production.
* **Portable types.** UUID primary keys (`sa.Uuid`), string enums with CHECK constraints, JSON columns.
  The test suite runs the same models on SQLite.
* **Auth.** Short-lived JWT access tokens + rotating refresh tokens stored hashed in `user_sessions`
  (per device, revocable). Passwords hashed with bcrypt.
* **RBAC.** `roles` table holds the role name and permission list; `core/permissions.py` defines the
  permission catalogue and default grants. Data scoping is applied in services:
  executive → own records, manager → own team, admin → everything.
* **Encryption at rest.** Lead phone numbers, emails and recording URLs are Fernet-encrypted
  (`FIELD_ENCRYPTION_KEY`). Duplicate detection and phone lookup use HMAC-SHA256 blind indexes
  (`phone_hash`, `email_hash`). Executives can be shown masked numbers (calls are placed server-side,
  so they never need the raw number).
* **No fake telephony.** A call row is created first with status `initiated`; it gets a
  `provider_call_id` only after the provider's API accepts the request. Any later status comes from
  provider webhooks. If no provider is configured the API returns `503` and the row is marked `failed`
  with the reason. The only fake provider lives in `tests/`.
* **One active call per lead.** `lead_call_locks` (primary key `lead_id`) is acquired by both
  human and AI calls before dialing and released on a terminal status (stale locks expire), so a lead can
  never be dialed twice at once across both systems.
* **Webhooks.** Every callback URL carries an HMAC token bound to the call ID (`wt=`), verified on
  receipt; Twilio and Plivo signatures are verified as well. Raw payloads are stored in `telephony_events`.
* **Realtime.** `/api/v1/ws` pushes `call.status`, `ai_call.status`, `campaign.progress` and
  `notification` events. The hub is in-process; swap `realtime/hub.py` for Redis pub/sub when running
  more than one API instance.
* **Workers.** The campaign runner, follow-up reminder and daily summary jobs run as asyncio tasks
  started by the app (`RUN_WORKERS=true`) or as a separate process (`python -m app.workers`).

## 4. Calling flows

### Human call (bridge / click-to-call)
1. App `POST /calls {lead_id}`. Backend checks permission, opt-out/DND, calling hours, lead lock.
2. Backend asks the provider to ring the salesperson's registered `calling_number`, then bridge to the lead
   (caller ID = company virtual number). The provider's response supplies `provider_call_id`.
3. Provider webhooks → `ringing` / `connected` / terminal status → row updated → WS `call.status` to the app.
4. On a terminal status, the app opens the disposition sheet: outcome, notes, follow-up, lead status.
5. Recording (if enabled and disclosed) is fetched later through `/recordings/{id}/url` (short-lived signed URL).

Bridge mode works with every listed provider and needs no native SDK. In-app VoIP calling (where mute and
speaker are controlled inside the app) is an extension point (`CallMode.voip`) for a provider's
Voice SDK; in bridge mode those controls are on the phone's own call screen.

### Inbound call
Provider hits `/webhooks/telephony/{provider}/inbound` → backend matches the caller by `phone_hash`,
routes to the assigned salesperson's number, creates an `inbound` `human_calls` row, notifies the app.
Unanswered inbound calls count as **missed**.

### AI call
1. Campaign runner (or an admin test call) picks a due `ai_campaign_leads` row inside the schedule window,
   checks consent/opt-out/calling hours/credits, acquires the lead lock and creates an `ai_calls` row.
2. Provider places the call; on answer it opens a bidirectional media WebSocket to
   `/api/v1/media/{provider}/{ai_call_id}`.
3. Conversation engine: plays the fixed AI disclosure (+ recording notice), then loops
   STT → Claude (streaming, tools `transfer_to_human`, `end_call`, `record_opt_out`) → TTS, with barge-in.
4. On hang-up: transcript saved, Claude produces structured call intelligence (summary, requirements,
   interest level, budget, decision maker, next action, follow-up, qualification score), lead status and
   campaign lead outcome updated, follow-ups and notifications created, handoffs routed to the assigned
   salesperson.

## 5. AI provider independence

`voice/llm/base.py`, `voice/stt/base.py`, `voice/tts/base.py` define the interfaces; `voice/registry.py`
picks implementations from env (`LLM_PROVIDER`, `STT_PROVIDER`, `TTS_PROVIDER`). Shipped implementations:

* LLM — Anthropic Claude (`claude-opus-5-5` by default for both live conversation and analysis;
  live turns run at low effort to keep latency down). Server-side refusal fallback is enabled.
* STT — Deepgram streaming (English + Hindi).
* TTS — ElevenLabs multilingual (English + Hindi), telephony output formats.

Languages are configured per agent (`en-IN`, `hi-IN`); adding a language means adding it to
`voice/languages.py` with its STT/TTS codes.
