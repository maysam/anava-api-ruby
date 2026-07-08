# Anava API — Ruby/Sinatra Clone

A standalone Ruby clone of the Supabase edge function in `supabase/functions/anava/index.ts`.
It exposes the same endpoints and response shapes, backed by plain Postgres instead of Supabase.

## Run with Docker Compose

```bash
cd anava-ruby
docker compose up --build
```

- API: http://localhost:8000/anava/health
- Postgres: localhost:5433 (user/password/db: `anava`), schema auto-applied from `db/init.sql` on first start

## Run locally (without Docker)

```bash
bundle install
DATABASE_URL=postgres://anava:anava@localhost:5433/anava bundle exec rackup -p 8000
```

## Endpoints

Same as the original API (see the root README for request/response details):

| Method | Path |
|--------|------|
| GET | `/anava/health` |
| GET | `/anava/statistics?userId=` |
| POST | `/anava/recordings` |
| GET | `/anava/recordings` |
| GET | `/anava/recordings/:id` |
| GET | `/anava/recordings/user/:userId` |
| GET | `/anava/recordings/analytics/:userId` |
| GET | `/anava/models` |
| GET | `/anava/recordings/model/:model` |
| GET | `/anava/recordings/analytics-by-model/:model` |
| PUT | `/anava/recordings/:id` |
| DELETE | `/anava/recordings/:id` |

## Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `DATABASE_URL` | `postgres://anava:anava@localhost:5432/anava` | Postgres connection string |
| `PORT` | `8000` | HTTP listen port |
| `DB_POOL_SIZE` | `5` | Connection pool size |
