# Anava API — Ruby on Rails (light/API-only)

A standalone Ruby clone of the Supabase edge function in `supabase/functions/anava/index.ts`.
It exposes the same endpoints and response shapes, backed by plain Postgres instead of Supabase.

This is a **light** Rails app: `config.api_only = true`, and only Action Pack (routing +
controllers), Active Record, and Railties are loaded — no Action View, no asset pipeline, no
Action Mailer/Cable/Storage. Data access is through Active Record (`app/models/recording.rb`); see
"Database schema" below for how that lines up with `db/init.sql`.

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

Full request/response detail (parameters, schemas, examples) is in the generated OpenAPI doc — see
"API documentation" below.

## Uploading a WAV file

`POST /api/v1/recordings` and `PUT /api/v1/recordings/:id` also accept `multipart/form-data`
instead of a JSON body: send the same fields as regular form fields, plus a `file` part holding the
recording's audio. The file must actually be a WAV (checked via its RIFF/WAVE magic bytes, not the
filename or the client-supplied Content-Type — see `app/services/audio_file_storage.rb`); anything
else is rejected with `400`. On success it's saved under `storage/recordings/<uuid>.wav` and that
path is stored as the recording's `file_path`. A `file`-only `PUT` (no other fields) is valid — it
just attaches/replaces the audio on an existing recording. Uploaded files aren't served back over
HTTP by this app; `file_path` is just a string reference.

## Project layout

```
app/models/recording.rb            # Active Record model + query-filter scope helper
app/services/recording_analytics.rb # analytics/ranking/stats logic built on top of Recording
app/services/audio_file_storage.rb  # validates + saves uploaded WAV files (see above)
app/controllers/                    # one controller per resource (health, statistics, device_models, recordings)
config/database.yml                 # Active Record connection config, reads DATABASE_URL
config/initializers/cors.rb         # rack-cors, mirrors the old before-filter CORS headers
config/initializers/rswag_*.rb      # mounts /api-docs (see "API documentation" below)
config/routes.rb                    # maps /api/v1/* paths to controllers
db/init.sql                         # what actually provisions dev/production Postgres (see below)
db/migrate/, db/schema.rb           # standard Active Record migrations (see "Database schema" below)
swagger/v1/swagger.yaml             # generated OpenAPI doc, checked in (see "API documentation")
```

## Database schema

There are now two parallel definitions of the `recordings` table, and they need to be kept in sync
by hand:

- **`db/init.sql`** — what actually provisions dev/production: the official Postgres image applies
  it automatically on first container start (see `docker-compose.yaml`). Still has the
  `update_updated_at_column()` trigger and the `get_user_rank()`/`get_user_count()` functions, which
  the app no longer calls (ranking is computed in Ruby via `RecordingAnalytics.user_rank` instead),
  left in place in case anything else relies on them.
- **`db/migrate/` + `db/schema.rb`** — the standard Active Record way to manage the schema going
  forward. `db/schema.rb` was generated by applying `db/migrate/20260709152751_create_recordings.rb`'s
  `create_table`/`add_index` calls directly against a scratch database and dumping the result — not
  by running `rails db:migrate` against a real one.

Nothing here runs migrations against your configured `DATABASE_URL` automatically — `docker-compose.yaml`
still bootstraps dev/production Postgres from `db/init.sql` exactly as before, and the Dockerfile
doesn't run `db:migrate`/`db:prepare` on boot. If you want the migration to actually be the source
of truth for a real database (rather than just specs), you'd run `bin/rails db:migrate` (or
`db:prepare` for a fresh one) yourself, and add whatever schema change you make there to
`db/init.sql` too so Docker's bootstrap stays in sync — this repo doesn't do either of those for you.

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
database server needed. `spec/rails_helper.rb`'s `ActiveRecord::Migration.maintain_test_schema!`
call loads `db/schema.rb` into it automatically (and keeps it in sync whenever the schema changes)
the standard Rails way; development/production are untouched and still use Postgres via
`DATABASE_URL` (see `config/database.yml`).

`spec/models/`, `spec/services/`, and `spec/requests/` cover the `Recording` model's query
filtering, `RecordingAnalytics` (including the tie-breaking rank calculation), and the endpoints
end-to-end. Test data is built with FactoryBot (`spec/factories/recordings.rb`) and Faker.
`spec/integration/` is a separate set of specs written in [rswag](https://github.com/rswag/rswag)'s
DSL specifically to generate the OpenAPI doc (see below) — same app, deliberately kept apart from
the plain specs above so neither set has to compromise on style for the other's purpose.

## API documentation

An interactive Swagger UI is mounted at **`/api-docs`** (e.g. http://localhost:8085/api-docs when
running via Docker Compose), backed by the OpenAPI doc at `swagger/v1/swagger.yaml`. Both
`rswag-ui` and `rswag-api` are plain Rack middleware (not Action View — this stays a light,
view-less app) that just serve static Swagger UI assets and that YAML file.

The YAML is generated from `spec/integration/*_spec.rb` and checked into git (so `/api-docs` works
in production without running specs there). Regenerate and commit it whenever those specs or the
API itself change:

```bash
bundle exec rake rswag:specs:swaggerize
```

This only rewrites `swagger/v1/swagger.yaml` from the specs' declared paths/parameters/schemas —
run the full `bundle exec rspec` first (or as part of the same CI step) to make sure those
declarations still match what the app actually returns.
