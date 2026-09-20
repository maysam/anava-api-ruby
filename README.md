# Anava API — Ruby on Rails

A standalone Ruby clone of the Supabase edge function in `supabase/functions/anava/index.ts`.
It exposes the same JSON endpoints and response shapes, backed by plain Postgres instead of
Supabase. It is also the only thing Anava serves on the web — three audiences, one app:

| Path | Who it's for | What it is |
|------|--------------|------------|
| `/` | everyone | the public marketing website — static files under `public/` |
| `/admin` | the operator | the recordings dashboard (optional HTTP Basic auth) |
| `/panel` | one person | that device's own history, entered through a magic link from the app |
| `/api/v1/*` | the mobile apps | the JSON API |

Still a **light** Rails app: `config.api_only = true`, and only Action Pack (routing + controllers),
Active Record, and Action View are loaded — no asset pipeline, no Action Mailer/Cable/Storage. The
JSON controllers inherit from `ActionController::API`; the two HTML controllers
(`Admin::DashboardController`, `PanelController`) inherit from `ActionController::Base` and render
ERB. Data access is through Active Record (`app/models/recording.rb`); see "Database schema" below
for how that lines up with `db/init.sql`.

## Run with Docker Compose

```bash
cd anava-ruby
docker compose up --build
```

- Website, dashboard, panel + API: http://localhost:8085 (published via
  `docker-compose.override.yml`, local dev only)
- Postgres: localhost:5433 (user/password/db: `anava`), schema auto-applied from `db/init.sql` on first start

The website, the dashboard and their assets are plain files checked into this repo (`app/views/`,
`public/`), so there's no frontend build step — `docker compose up --build` just builds the Rails
image.

## The public website (`/`)

`/` is the marketing site: `public/index.html` plus `faq.html`, `privacy-policy.html`,
`terms-of-service.html`, `impressum.html`, `detector-playground.html`, `css/`, `js/`, `images/`,
`app-ads.txt` and `.well-known/assetlinks.json`. They are plain static files served by
`ActionDispatch::Static` before routing runs, which is why **there is deliberately no `root` route
in `config/routes.rb`** — adding one would shadow `public/index.html`.

These files came from the separate `website/` repo (GitHub Pages). That repo still exists and is
still the upstream for edits; `backend/public/` is the copy this app serves. `spec/requests/public_website_spec.rb`
guards the arrangement, so a stray root route or a renamed file fails the build rather than
silently replacing the homepage.

`assetlinks.json` and `app-ads.txt` must keep resolving at their exact paths — Android App Links
verification and AdMob both fetch them by URL.

## The admin dashboard (`/admin`)

A server-rendered dashboard (`Admin::DashboardController` + `app/views/admin/dashboard/`) that
mirrors the `anava-web` React reference: a recordings browser (grouped by day, with date-range and
per-page filters, pagination, and a detail modal showing an amplitude waveform + OpenStreetMap
location + JSON download) and an analytics tab (summary cards + daily/slot/activity-type charts).
It used to live at `/`; the website took that over.

- It reads through the same `Recording` model and `RecordingAnalytics` service the JSON API uses —
  no HTTP round-trip to itself, no separate frontend host, no CORS.
- Filtering/pagination/model selection are plain query parameters on `/admin` (server-rendered);
  expand/collapse, tab switching, the detail modal, and the charts are handled by
  `public/admin/dashboard.js` (vanilla JS). Charts use the vendored
  `public/admin/vendor/chart.umd.min.js` ([Chart.js](https://www.chartjs.org/)). Styling is
  `public/admin/dashboard.css`.
- Those three files under `public/admin/` are served as static assets by `ActionDispatch::Static`
  (`config.public_file_server.enabled = true`), not via an asset pipeline — which is why the app
  stays "light" despite now rendering HTML.

**Access control.** Set `ANAVA_ADMIN_PASSWORD` (and optionally `ANAVA_ADMIN_USERNAME`, default
`admin`) and `/admin` requires HTTP Basic auth. Leave it unset and the dashboard stays open — the
same posture it had at `/` — but every page renders a warning banner saying so. Set it in
production: the dashboard shows every user's recordings and locations.

The `anava-web/` directory is no longer wired into this app at all; it's kept purely as the design
reference the dashboard was ported from.

## The per-user panel (`/panel`)

Each device gets its own private page: total sessions, current and longest streak, average score,
time in prayer, its three rankings, a 30-day activity chart, a per-prayer breakdown, and its recent
sessions. Everything on it is scoped to one `user_id` — a person can only ever see their own
recordings.

**How signing in works, given the app has no accounts.** The only identity Anava has is the
anonymous UUID each install generates on first launch (`Defaults.getUserId()` on Android,
`SettingsStore.userId` on iOS) — the same id recordings are uploaded under. Putting that id in a URL
would leave the panel permanently reachable by anyone who ever saw the link. So instead:

1. The app calls `POST /api/v1/panel/magic-link` with its `user_id` and gets back a URL
   (`PanelLinksController`).
2. That URL carries a 32-byte random token — not the user id. Only its SHA-256 digest is stored, so
   a database leak can't be replayed (`app/models/panel_magic_link.rb`).
3. Opening it (`GET /panel/enter?token=…`) spends the token — one conditional `UPDATE`, so two
   browsers racing the same link can't both get in — and exchanges it for a session cookie.
4. Tokens expire after 15 minutes; a device keeps at most 5 live ones, and expired rows are purged
   opportunistically whenever a link is issued. The session cookie lasts 30 days.

The panel's figures come from `PanelAnalytics`, which reuses `RecordingAnalytics` for anything the
in-app statistics screen also shows, so the two never disagree. Styling is `public/panel/panel.css`
and the one chart is `public/panel/panel.js`.

**Production requirement:** the session cookie is signed with `secret_key_base`. Locally that comes
from `config/credentials.yml.enc` + `config/master.key`, but `master.key` is gitignored and so is
absent from a build made from the repo — set **`SECRET_KEY_BASE`** in the deployment environment or
`/panel` will fail at request time. Nothing else in the app needs it.

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

### Deployment checklist for this app's three faces

Because `/` is now the public website rather than the dashboard, one deploy serves all of it —
there is no longer a separate GitHub Pages host to point DNS at. Before the first deploy that
includes the panel:

1. **Set `SECRET_KEY_BASE`** in the Coolify environment. `config/master.key` is gitignored, so an
   image built from the repo cannot decrypt the credentials — and the panel's session cookie needs
   that secret. Generate one with `bundle exec rails secret`.
2. **Set `ANAVA_ADMIN_PASSWORD`** so `/admin` isn't open to the internet. The dashboard shows every
   user's recordings, coordinates and device models.
3. **Create the `panel_magic_links` table** on the existing database — see "Deploying the panel
   table" under "Database schema". `db/init.sql` only runs on a brand-new Postgres volume.
4. Check that `https://<domain>/.well-known/assetlinks.json` and `https://<domain>/app-ads.txt`
   still resolve, if this domain is the one Android App Links and AdMob were verified against.

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
| GET | `/` (the public website — see "The public website" above) |
| GET | `/admin` (HTML dashboard — see "The admin dashboard" above) |
| GET | `/panel`, `/panel/enter?token=`, `/panel/sign-out` (see "The per-user panel") |
| POST | `/api/v1/panel/magic-link` |
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

`POST /api/v1/recordings` is idempotent: a repeated post with the same `user_id`, `slot_id`,
`start_timestamp`, and `end_timestamp` updates that existing recording in place instead of creating
a duplicate row, so a client retrying a request (e.g. after a dropped response) is safe. See
`Recording.create_or_update_idempotently` in `app/models/recording.rb`.

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
app/models/recording.rb             # Active Record model + query-filter scope helper
app/services/recording_analytics.rb # analytics/ranking/stats logic built on top of Recording
app/services/audio_file_storage.rb  # validates + saves uploaded WAV files (see above)
app/models/panel_magic_link.rb      # single-use panel sign-in tokens (digest-only storage)
app/services/panel_analytics.rb     # everything the per-user panel shows (streaks, 30-day window)
app/controllers/                    # JSON API controllers (health, statistics, device_models, recordings)
app/controllers/panel_links_controller.rb # POST /api/v1/panel/magic-link
app/controllers/panel_controller.rb # the per-user panel at /panel (see "The per-user panel")
app/controllers/admin/base_controller.rb  # optional HTTP Basic auth for everything under /admin
app/controllers/admin/dashboard_controller.rb # the HTML dashboard at /admin
app/views/admin/dashboard/          # dashboard ERB templates (index + recordings/analytics partials)
app/views/panel/                    # panel ERB templates (show + signed-out/expired-link states)
app/views/layouts/admin.html.erb    # dashboard layout (loads admin assets + the modal markup)
app/views/layouts/panel.html.erb    # panel layout
app/helpers/recording_presentation_helper.rb # shared view helpers: slot names, duration/date formatting
public/index.html, css/, js/, …     # the public marketing website (served statically)
public/admin/dashboard.css, .js     # dashboard styles + behaviour (served statically)
public/admin/vendor/chart.umd.min.js # vendored Chart.js (analytics + amplitude + panel charts)
public/panel/panel.css, panel.js    # panel styles + its one chart
config/database.yml                 # Active Record connection config, reads DATABASE_URL
config/initializers/cors.rb         # rack-cors, mirrors the old before-filter CORS headers
config/initializers/rswag_*.rb      # mounts /api-docs (see "API documentation" below)
config/routes.rb                    # /admin, /panel and /api/v1/* — no root route, by design
db/init.sql                         # what actually provisions dev/production Postgres (see below)
db/migrate/, db/schema.rb           # standard Active Record migrations (see "Database schema" below)
swagger/v1/swagger.yaml             # generated OpenAPI doc, checked in (see "API documentation")
```

## Database schema

There are now two parallel definitions of the schema (`recordings`, and `panel_magic_links` added
alongside it), and they need to be kept in sync by hand:

- **`db/init.sql`** — what actually provisions dev/production: the official Postgres image applies
  it automatically on first container start (see `docker-compose.yaml`). Still has the
  `update_updated_at_column()` trigger and the `get_user_rank()`/`get_user_count()` functions, which
  the app no longer calls (ranking is computed in Ruby via `RecordingAnalytics.user_rank` instead),
  left in place in case anything else relies on them.
- **`db/migrate/` + `db/schema.rb`** — the standard Active Record way to manage the schema going
  forward. `db/schema.rb` was generated by applying `db/migrate/20260709152751_create_recordings.rb`'s
  `create_table`/`add_index` calls directly against a scratch database and dumping the result — not
  by running `rails db:migrate` against a real one. `20260920120000_create_panel_magic_links.rb`
  was added the same way (hand-written migration, hand-matched `schema.rb` entry and `init.sql`
  block); specs load `schema.rb`, so they cover it.

**Deploying the panel table.** `panel_magic_links` is new, so an existing Postgres volume will not
have it — `db/init.sql` only runs on a *first* container start. Apply it once by hand
(`psql < db/init.sql` is safe: every statement is `IF NOT EXISTS`/`OR REPLACE`), or run
`bin/rails db:migrate`. Until it exists, `/panel` and `POST /api/v1/panel/magic-link` fail; nothing
else is affected.

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
| `SECRET_KEY_BASE` | from `config/credentials.yml.enc` | signs the panel's session cookie. **Required in production** unless `config/master.key` is present in the image — it is gitignored, so a build from the repo won't have it |
| `ANAVA_ADMIN_PASSWORD` | _(unset)_ | set it to put `/admin` behind HTTP Basic auth; unset leaves the dashboard open and shows a warning banner |
| `ANAVA_ADMIN_USERNAME` | `admin` | the username for that HTTP Basic auth |
| `ANAVA_PUBLIC_BASE_URL` | _(the request's own scheme + host)_ | base URL written into issued panel links; only needed when the forwarded headers don't give the public host |

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
