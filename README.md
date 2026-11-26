# Elets SalesCall AI

Sales calling and AI voice-agent platform for Elets Technomedia's sales team.

- **Human calling** — smart dialer with click-to-call through Exotel / Twilio / Plivo / Knowlarity, live call
  status, dispositions, follow-ups, recordings. Every call is tied to the salesperson who made it.
- **AI voice agents** — configurable agents (English & Hindi) that call leads, disclose they are AI, qualify
  interest, book meetings, hand off to humans, and write structured call intelligence.
- **AI campaigns** — scheduled bulk calling with retries, concurrency/rate limits, live progress and logs.
- **Lead management** — CRUD, CSV/Excel import, duplicate protection, bulk assignment, full history.
- **Analytics** — role-based dashboards, leaderboard, human vs AI comparison, CSV/Excel exports.
- **Security & compliance** — JWT sessions, RBAC (admin / manager / executive), encrypted PII, opt-out list,
  calling-hours enforcement, recording controls, audit log.

| Path | What |
|---|---|
| [`backend/`](backend) | FastAPI + PostgreSQL API, telephony adapters, AI voice engine, workers |
| [`mobile/`](mobile) | Flutter app (Riverpod, GoRouter, Material 3) |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | System design and folder structure |
| [`docs/API.md`](docs/API.md) | REST / WebSocket contract (live docs at `/docs`) |
| [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) | Setup, provider configuration, production deployment |
| [`docs/COMPLIANCE.md`](docs/COMPLIANCE.md) | What is enforced for TRAI / consent / recording / AI disclosure |

## Quick start

```bash
docker run -d --name elets-pg -e POSTGRES_USER=elets -e POSTGRES_PASSWORD=elets \
  -e POSTGRES_DB=elets_salescall -p 5432:5432 postgres:16-alpine
cd backend && pip install -r requirements.txt && cp .env.example .env
alembic upgrade head && python -m app.seed --demo-activity
uvicorn app.main:app --port 8000
# new terminal
cd mobile && flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

Sign in as `admin@elets.local` / `Elets@12345` (seed defaults — change them). Calling stays disabled, with a clear
"no telephony provider configured" message, until you add provider credentials to `backend/.env`; AI calling also
needs Anthropic, Deepgram and ElevenLabs keys. See [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

Run the backend tests with `cd backend && python -m pytest`.
