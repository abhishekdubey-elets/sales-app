# Setup & Deployment

## 1. Local development

Requirements: Python 3.12, PostgreSQL 16 (or Docker), Flutter 3.x stable.

```bash
# database
docker run -d --name elets-pg -e POSTGRES_USER=elets -e POSTGRES_PASSWORD=elets \
  -e POSTGRES_DB=elets_salescall -p 5432:5432 postgres:16-alpine

# backend
cd backend
python -m venv .venv && . .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env                                  # edit as needed
alembic upgrade head
python -m app.seed --demo-activity                    # roles, users, 30 sample leads, 3 AI agents, sample history
uvicorn app.main:app --reload --port 8000
```

Open http://localhost:8000/docs for interactive API docs.

Seeded accounts (password = `SEED_DEFAULT_PASSWORD`, default `Elets@12345`; change it):

| Role | Email |
|---|---|
| Admin | `admin@elets.local` |
| Manager — Corporate Sales | `manager.sales@elets.local` |
| Manager — Events & Partnerships | `manager.events@elets.local` |
| Executives | `rohit@`, `priya@`, `karan@`, `ananya@elets.local` |

Sample leads use the invalid `+91 0…` number range so they can never ring a real phone. `--demo-activity` adds
seven days of call history tagged `provider = demo-seed` so dashboards are populated; omit it for a clean install.

Tests: `cd backend && python -m pytest` (SQLite in memory, fake telephony provider — no network).

### Without Docker (SQLite, single machine)

For a demo or a laptop without Docker/PostgreSQL, the backend can use a SQLite file. Use PostgreSQL for
anything shared or production.

```bash
cd backend
# in .env:  DATABASE_URL=sqlite+aiosqlite:///./data/elets.db
mkdir -p data
alembic upgrade head
python -m app.seed --demo-activity
uvicorn app.main:app --host 0.0.0.0 --port 8010
```

`--host 0.0.0.0` makes the API reachable from phones on the same network (`http://<this PC's IP>:8010`).
On Windows, allow the port through the firewall once (admin PowerShell):
`New-NetFirewallRule -DisplayName "Elets SalesCall API (8010)" -Direction Inbound -Protocol TCP -LocalPort 8010 -Action Allow -Profile Private`

### Flutter app

```bash
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000     # Android emulator → host machine
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

On a physical phone use your machine's LAN IP (and add it to `CORS_ORIGINS` for web). See `mobile/README.md`.

## 2. Configuration reference

Everything is configured through environment variables (`backend/.env.example` lists them all). Nothing secret is
ever shipped to the Flutter app — it only knows `API_BASE_URL`.

| Group | Variables |
|---|---|
| Core | `ENVIRONMENT`, `API_PUBLIC_BASE_URL` (public **https** URL; used in provider callbacks and signed links), `DATABASE_URL`, `CORS_ORIGINS`, `ORG_TIMEZONE`, `RUN_WORKERS` |
| Secrets | `JWT_SECRET`, `FIELD_ENCRYPTION_KEY`, `BLIND_INDEX_KEY`, `WEBHOOK_SIGNING_SECRET` — generate with `python -m app.cli gen-secrets`. **Never rotate `FIELD_ENCRYPTION_KEY` or `BLIND_INDEX_KEY` without a re-encryption migration.** |
| Telephony | `TELEPHONY_PROVIDER` (`exotel`/`twilio`/`plivo`/`knowlarity`), `TELEPHONY_CALLER_ID`, provider credentials |
| AI voice | `ANTHROPIC_API_KEY`, `LLM_MODEL`, `LLM_REALTIME_EFFORT`, `LLM_ANALYSIS_EFFORT`, `DEEPGRAM_API_KEY`, `DEEPGRAM_MODEL`, `ELEVENLABS_API_KEY`, `ELEVENLABS_MODEL`, `ELEVENLABS_DEFAULT_VOICE_ID` |
| Push | `FCM_PROJECT_ID`, `FCM_SERVICE_ACCOUNT_FILE` |

Startup refuses to run in `staging`/`production` with development secrets or a non-https public URL.

`GET /health` reports database, telephony and AI-voice readiness. `GET /api/v1/ai/voice-status` shows the same
inside the app (AI Agents → status card).

## 3. Telephony provider setup

Calls are **bridge (click-to-call)** calls: the provider rings the salesperson's registered *calling number*
first, then connects the lead with your virtual number as caller ID. Each salesperson sets their calling number in
Profile. Every call row carries the salesperson's ID; nothing is marked connected or completed unless the
provider's webhook says so.

Webhook URLs are generated per call and signed (`wt=` token), so for outbound calls there is nothing to paste.
Static URLs (inbound routing, Exotel flows, Knowlarity's panel webhook) are printed by:

```bash
python -m app.cli webhook-urls exotel     # or twilio / plivo / knowlarity
```

The public base URL must be reachable by the provider (use an https tunnel such as ngrok or Cloudflare Tunnel
during development and set `API_PUBLIC_BASE_URL` to it).

### Exotel (recommended for India)
1. Set `EXOTEL_API_KEY`, `EXOTEL_API_TOKEN`, `EXOTEL_ACCOUNT_SID`, `EXOTEL_SUBDOMAIN` (`api.in.exotel.com` for the
   Mumbai cluster) and `TELEPHONY_CALLER_ID` (your ExoPhone).
2. Human calls work immediately (Calls/connect API).
3. AI calls: create an Exotel flow → **Voicebot** applet with *Dynamic URL* = the `voicebot dynamic URL` printed
   above, followed by a **Connect** applet whose dynamic number URL = `connect applet (AI hand-off)`, then Hangup.
   Put the flow's app id in `EXOTEL_AI_APP_ID`. Ask Exotel to enable the Voicebot (bidirectional stream) applet.
4. Inbound: on the ExoPhone's incoming flow, add a Connect applet with dynamic URL = `inbound`.
5. Exotel has no "end call" API — the End button in the app explains this; the salesperson ends the call on the
   phone.

### Twilio
Set `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TELEPHONY_CALLER_ID`. AI calls use Media Streams and live transfer
works through the API. For inbound, set the number's *A call comes in* webhook to the `inbound` URL (POST).
Twilio request signatures are verified, so `API_PUBLIC_BASE_URL` must exactly match the URL Twilio calls.

### Plivo
Set `PLIVO_AUTH_ID`, `PLIVO_AUTH_TOKEN`, `TELEPHONY_CALLER_ID`. AI calls use bidirectional audio streams; live
transfer uses the call-transfer API. Inbound: point the Plivo application's Answer URL at the `inbound` URL.

### Knowlarity
Set `KNOWLARITY_API_KEY`, `KNOWLARITY_AUTH_TOKEN`, `KNOWLARITY_K_NUMBER`. Human click-to-call only (no AI media
streaming). Configure Knowlarity's call-event webhook to the provider-level `status` URL.

> The provider adapters follow each provider's public API documentation but could not be exercised against live
> accounts during development. Place test calls on a sandbox/trial account and compare a few raw callbacks
> (stored in the `telephony_events` table) with the adapter's field mapping before rollout.

## 4. AI voice agents

1. Set `ANTHROPIC_API_KEY` (Claude, default model `claude-opus-5-5`; live turns run at low effort for latency,
   post-call analysis at medium). Server-side refusal fallback is enabled on every request.
2. Set `DEEPGRAM_API_KEY` (speech-to-text, English + Hindi) and `ELEVENLABS_API_KEY` + a voice id
   (text-to-speech in telephony µ-law 8 kHz). Each AI agent can override the voice id.
3. In the app: AI Agents → create from a template → fill in the **knowledge base** with your real event calendar,
   packages and contacts (the agent is instructed to state only facts listed there) → use **Test reply** to
   rehearse in text → place a single test call to your own number → then create a campaign.

To change models: `LLM_MODEL=claude-sonnet-5-5` (or `claude-haiku-5-5`) trades capability for lower latency/cost.
Other LLM/STT/TTS vendors plug in by implementing `voice/llm/base.py`, `voice/stt/base.py`, `voice/tts/base.py`
and registering them in `voice/registry.py`.

## 5. Push notifications (FCM)

1. Create a Firebase project; add Android/iOS apps; download `google-services.json` /
   `GoogleService-Info.plist` into the Flutter platform folders (never commit them).
2. Create a service account with the *Firebase Cloud Messaging API* role; save its JSON on the server and set
   `FCM_PROJECT_ID` and `FCM_SERVICE_ACCOUNT_FILE`.
3. Build the app with `--dart-define=FCM_ENABLED=true`. The app registers its token with
   `POST /users/me/device-tokens`. Without FCM, notifications still arrive in-app over the WebSocket.

## 6. Production deployment

Single server (Docker Compose):

```bash
cp backend/.env.example backend/.env      # set ENVIRONMENT=production, secrets, providers, https URL
docker compose up -d --build
docker compose exec api python -m app.seed      # once; then change all seeded passwords or create real users
```

Put a TLS-terminating reverse proxy (Nginx, Caddy, a cloud load balancer) in front of the API. It must forward
WebSocket upgrades for `/api/v1/ws` and `/api/v1/media/*` and pass `X-Forwarded-*` headers.

Checklist:
- [ ] `ENVIRONMENT=production`, fresh secrets, `API_PUBLIC_BASE_URL` = public https URL
- [ ] Managed PostgreSQL with automated backups and encryption at rest; `alembic upgrade head` runs on start
- [ ] `CORS_ORIGINS` limited to your web origin(s) (mobile apps don't need CORS)
- [ ] Replace or re-password all seeded users; remove sample leads (`source` = Website/Event/… with `remarks`
      "Sample lead")
- [ ] Calling hours, disclosure texts and consent requirement reviewed with counsel (Settings screen)
- [ ] Provider callbacks verified on a test call; `telephony_events` show expected statuses
- [ ] Log shipping and uptime monitoring on `/health`

Scaling notes:
- The WebSocket hub (`realtime/hub.py`) is in-process. With more than one API replica, swap it for Redis pub/sub
  and keep **one** worker (`RUN_WORKERS=true` on a single replica, or run `python -m app.workers` separately — live
  events from a separate worker process also need the Redis hub to reach connected apps).
- AI calls hold a media WebSocket for their whole duration; size API workers for peak concurrent AI calls
  (each campaign's `max_concurrent_calls`).
- The login brute-force limiter is in-memory per process; use a shared store or a gateway rate limit when scaled.

## 7. Mobile release

- Android: set the application id/signing config in `mobile/android`, then
  `flutter build appbundle --dart-define=API_BASE_URL=https://api.example.com --dart-define=FCM_ENABLED=true`.
- iOS: set the bundle id/signing in Xcode, add push capability, then `flutter build ipa` with the same defines.
