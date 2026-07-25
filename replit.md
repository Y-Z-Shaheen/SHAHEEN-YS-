# SHAHEEN-YS

Production-ready AI infrastructure platform built on AstrBot. Provides a Flask/WSGI web application with modular services: API gateway, identity, compute, observability, and a multi-provider AI key manager.

---

## Stack

- **Language**: Python 3.12
- **Web framework**: Flask (WSGI)
- **Production server**: Gunicorn (gthread workers)
- **Database**: PostgreSQL (production) / SQLite (development fallback)
- **ORM**: SQLAlchemy 2.x
- **Deployment target**: Railway

---

## Running locally

```bash
# Install dependencies
pip install -r requirements.txt

# Start development server (SQLite fallback, no DATABASE_URL needed)
python app/dashboard/app.py
```

Or via Gunicorn (production mode locally):

```bash
bash scripts/start-production.sh
```

---

## Production run command (Railway)

```
bash scripts/start-production.sh
```

Which executes:

```
gunicorn --config gunicorn.conf.py wsgi:application
```

Binds to `0.0.0.0:$PORT` (Railway sets `PORT` automatically).

---

## Health checks

| Endpoint | Purpose | Auth required |
|----------|---------|---------------|
| `GET /health/live` | Liveness — process alive | No |
| `GET /health/ready` | Readiness — DB connected | No |
| `GET /health` | Full health + DB status | No |
| `GET /metrics` | Request metrics snapshot | No |

**Railway healthcheck path**: `/health/ready`

---

## Database

| Environment | Backend | How to set |
|-------------|---------|------------|
| Production | PostgreSQL | Set `DATABASE_URL` env var |
| Development | SQLite | Leave `DATABASE_URL` unset; uses `SHAHEEN_YS_DATABASE_PATH` |

Schema is initialised automatically on startup (`CREATE TABLE IF NOT EXISTS`). No manual migration needed for new deployments.

PostgreSQL URL formats all supported:
- `postgres://...` → automatically normalised to `postgresql://`
- `postgresql://...`
- `postgresql+psycopg://...`

---

## Running tests

```bash
# SHAHEEN-YS tests only (fast, no external deps)
python -m pytest tests/test_config.py tests/test_database.py tests/test_providers.py tests/test_health.py tests/test_compute_service.py -v
```

---

## Environment variables

### Core
| Variable | Required in prod | Default | Notes |
|----------|-----------------|---------|-------|
| `SHAHEEN_YS_ENV` | Yes | `development` | `production` or `development` |
| `SHAHEEN_YS_HOST` | No | `0.0.0.0` | Bind host |
| `PORT` | No (Railway auto) | `8080` | Bind port |

### Database
| Variable | Required in prod | Default | Notes |
|----------|-----------------|---------|-------|
| `DATABASE_URL` | **Yes** | — | PostgreSQL connection URL (secret) |
| `SHAHEEN_YS_DATABASE_PATH` | No | `./data/db/shaheen_ys.db` | SQLite path (dev only) |

### Security (secrets)
| Variable | Required in prod | Default |
|----------|-----------------|---------|
| `SHAHEEN_YS_SECRET_KEY` | **Yes** | — |
| `SHAHEEN_YS_ADMIN_USERNAME` | No | `admin` |
| `SHAHEEN_YS_ADMIN_PASSWORD` | **Yes** | — |

### Localisation
| Variable | Default |
|----------|---------|
| `SHAHEEN_YS_LOCALE` | `ar_JO` |
| `SHAHEEN_YS_LANGUAGE` | `ar` |
| `SHAHEEN_YS_TIMEZONE` | `Asia/Amman` |

### Runtime
| Variable | Default | Notes |
|----------|---------|-------|
| `SHAHEEN_MAX_CONCURRENT_TASKS` | `10` | Integer 1–1000 |
| `SHAHEEN_LOG_LEVEL` | `INFO` | DEBUG/INFO/WARNING/ERROR/CRITICAL |
| `SHAHEEN_START_FROM_LATEST` | `true` | Boolean |
| `SHAHEEN_THEME` | `system` | light/dark/system |
| `NODE_OPTIONS` | — | Passed to Node/WebUI |
| `NITRO_PRESET` | — | Passed to Nitro/WebUI |

### AI Provider Keys
Each provider supports unlimited numbered keys discovered automatically:

```
PROVIDER_API_KEY        ← base key (index 0)
PROVIDER_API_KEY1       ← index 1
PROVIDER_API_KEY2       ← index 2
```

| Variable | Provider |
|----------|---------|
| `OPENROUTER_API_KEY[N]` | OpenRouter |
| `OPENAI_API_KEY[N]` | OpenAI |
| `ANTHROPIC_API_KEY[N]` | Anthropic |
| `GROQ_API_KEY[N]` | Groq |
| `GEMINI_API_KEY[N]` | Google Gemini |
| `MISTRAL_API_KEY[N]` | Mistral |
| `DEEPSEEK_API_KEY[N]` | DeepSeek |
| `XAI_API_KEY[N]` | xAI |
| `TAVILY_API_KEY[N]` | Tavily |
| `EXA_API_KEY[N]` | Exa |
| `FIRECRAWL_API_KEY[N]` | Firecrawl |
| `ELEVENLABS_API_KEY[N]` | ElevenLabs |
| `GOOGLE_SEARCH_API_KEY[N]` | Google Search |
| `GOOGLE_SEARCH_ENGINE_ID[N]` | Google Search Engine |
| `TELEGRAM_BOT_TOKEN[N]` | Telegram |

Keys rotate round-robin per worker. Failed keys get cooldowns:
- `401/403` → 1 hour (unauthorized)
- `429` → 60 seconds (rate limited)
- `5xx` → 30 seconds (server error)
- Timeout → 15 seconds

---

## User preferences

- Arabic-first locale: `ar_JO`, language `ar`, timezone `Asia/Amman`
- Production database: PostgreSQL via `DATABASE_URL` on Railway
- Development database: SQLite fallback (no setup needed)
- Do not commit `.env` or any file containing real secret values
- Do not `git push` or deploy without explicit instruction
