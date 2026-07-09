# Anava API — Ruby on Rails (light/API-only)

A standalone Ruby clone of the Supabase edge function in `supabase/functions/anava/index.ts`.
It exposes the same endpoints and response shapes, backed by plain Postgres instead of Supabase.

This is a **light** Rails app: `config.api_only = true`, and only Action Pack (routing +
controllers), Active Record, and Railties are loaded — no Action View, no asset pipeline, no
Action Mailer/Cable/Storage. Data access is through Active Record (`app/models/recording.rb`); the
schema itself is still owned entirely by `db/init.sql` (see "Database schema" below).

## Run with Docker Compose

```bash
cd anava-ruby
docker compose up --build
```

- API: http://localhost:8085/health (published via `docker-compose.override.yml`, local dev only)
- Postgres: localhost:5433 (user/password/db: `anava`), schema auto-applied from `db/init.sql` on first start

## Deploying on Coolify

`docker-compose.yaml` does **not** publish the `api` port to the host — it only `expose`s 8085 on
the internal Docker network. This is deliberate: a static `ports: ["8085:8085"]` mapping fails to
bind whenever another resource on the same server already holds that host port (Coolify's own
Traefik proxy doesn't need it and won't clean it up for you). Instead, set a domain for the `api`
service in the Coolify UI (Configuration → Domains, pointing at container port 8085) and let
Coolify's built-in proxy route to it — this avoids host-port collisions entirely.

`docker-compose.override.yml` restores the `8085:8085` host mapping for plain
`docker compose up` runs (Compose auto-merges it locally); Coolify deploys with
`-f docker-compose.yaml` explicitly, so it never picks up the override.

## Run locally (without Docker)

```bash
bundle install
DATABASE_URL=postgres://anava:anava@localhost:5433/anava bundle exec puma -C config/puma.rb
# or: bin/rails server
```

## Endpoints

Same as the original API (see the root README for request/response details):

| Method | Path |
|--------|------|
| GET | `/health` |
| GET | `/api/v1/statistics?userId=` |
| POST | `/api/v1/recordings` |
| GET | `/api/v1/recordings` |
| GET | `/api/v1/recordings/:id` |
| GET | `/api/v1/recordings/user/:userId` |
| GET | `/api/v1/recordings/analytics/:userId` |
| GET | `/api/v1/models` |
| GET | `/api/v1/recordings/model/:model` |
| GET | `/api/v1/recordings/analytics-by-model/:model` |
| PUT | `/api/v1/recordings/:id` |
| DELETE | `/api/v1/recordings/:id` |

## Project layout

```
app/models/recording.rb            # Active Record model + query-filter scope helper
app/services/recording_analytics.rb # analytics/ranking/stats logic built on top of Recording
app/controllers/                    # one controller per resource (health, statistics, device_models, recordings)
config/database.yml                 # Active Record connection config, reads DATABASE_URL
config/initializers/cors.rb         # rack-cors, mirrors the old before-filter CORS headers
config/routes.rb                    # maps /api/v1/* paths to controllers
```

## Database schema

Schema, indexes, and triggers all live in `db/init.sql`, auto-applied by the official Postgres
image on first container start (see `docker-compose.yaml`). There are intentionally **no Active
Record migrations** — the `recordings` table is treated as already existing/schema-first, so
`db/init.sql` remains the single source of truth; changes to the schema should be made directly
there. (The old `get_user_rank()`/`get_user_count()` Postgres functions in `db/init.sql` are no
longer called by the app — leaderboard ranking is now computed in Ruby via `RecordingAnalytics.user_rank`,
grouping/averaging through Active Record instead of calling into the DB function. They're left in
place in case anything else still relies on them.)

## Configuration

| Env var | Default | Purpose |
|---------|---------|---------|
| `DATABASE_URL` | `postgres://anava:anava@localhost:5432/anava` | Postgres connection string |
| `PORT` | `8085` | HTTP listen port |
| `DB_POOL_SIZE` | `5` | Active Record connection pool size |
| `RAILS_ENV` | `development` | `development` or `production` (set to `production` in Docker) |

## Running the specs

```bash
bundle exec rspec
```

Tests run against SQLite (`db/test.sqlite3`, gitignored) rather than Postgres — no external
database server needed. `db/init.sql` isn't portable to SQLite (`SERIAL`, trigger functions), so
`spec/support/schema.rb` (re)creates a plain `recordings` table via Active Record's schema DSL
before the suite runs; development/production are untouched and still use Postgres via
`DATABASE_URL` (see `config/database.yml`).

`spec/models/`, `spec/services/`, and `spec/requests/` cover the `Recording` model's query
filtering, `RecordingAnalytics` (including the tie-breaking rank calculation), and the endpoints
end-to-end. Test data is built with FactoryBot (`spec/factories/recordings.rb`) and Faker.
