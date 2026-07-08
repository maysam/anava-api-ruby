# Anava API — Ruby/Sinatra Clone

A standalone Ruby clone of the Supabase edge function in `supabase/functions/anava/index.ts`.
It exposes the same endpoints and response shapes, backed by plain Postgres instead of Supabase.

## Run with Docker Compose

```bash
cd anava-ruby
docker compose up --build
```

- API: http://localhost:8000/anava/health (published via `docker-compose.override.yml`, local dev only)
- Postgres: localhost:5433 (user/password/db: `anava`), schema auto-applied from `db/init.sql` on first start

## Deploying on Coolify

`docker-compose.yaml` does **not** publish the `api` port to the host — it only `expose`s 8000 on
the internal Docker network. This is deliberate: a static `ports: ["8000:8000"]` mapping fails to
bind whenever another resource on the same server already holds that host port (Coolify's own
Traefik proxy doesn't need it and won't clean it up for you). Instead, set a domain for the `api`
service in the Coolify UI (Configuration → Domains, pointing at container port 8000) and let
Coolify's built-in proxy route to it — this avoids host-port collisions entirely.

`docker-compose.override.yml` restores the `8000:8000` host mapping for plain
`docker compose up` runs (Compose auto-merges it locally); Coolify deploys with
`-f docker-compose.yaml` explicitly, so it never picks up the override.

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
