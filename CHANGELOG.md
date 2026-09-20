# Changelog

## Unreleased

### Three faces on one app: website at `/`, dashboard at `/admin`, panel at `/panel`

**The public website moved into the backend.** `public/` now holds the marketing
site (`index.html`, `faq.html`, `privacy-policy.html`, `terms-of-service.html`,
`impressum.html`, `detector-playground.html`, `css/`, `js/`, `images/`,
`app-ads.txt`, `.well-known/assetlinks.json`), copied from the separate
`website/` GitHub Pages repo. It is served by `ActionDispatch::Static` before
routing, so **the `root` route was removed** — a root route would shadow
`public/index.html`. [spec/requests/public_website_spec.rb](spec/requests/public_website_spec.rb)
guards that, including that `assetlinks.json` (Android App Links) and
`app-ads.txt` (AdMob) still resolve at their exact paths.

**The dashboard moved from `/` to `/admin`.** `DashboardController` became
`Admin::DashboardController` under a new `Admin::BaseController`, views moved to
`app/views/admin/dashboard/`, the layout to `app/views/layouts/admin.html.erb`,
and its static assets to `public/admin/` (`dashboard.css`, `dashboard.js`,
`vendor/chart.umd.min.js`) so they can't collide with the website's. Setting
`ANAVA_ADMIN_PASSWORD` (plus optional `ANAVA_ADMIN_USERNAME`, default `admin`)
now puts the whole area behind HTTP Basic auth; leaving it unset keeps the old
open posture but renders a warning banner on every page, so an unprotected
deployment is visible rather than silent.

**New: a private panel for each user, at `/panel`.** It shows only that one
device's recordings — total sessions, current and longest streak, average score,
time in prayer, the three rankings, a 30-day activity chart, a per-prayer
breakdown and recent sessions. Figures come from the new
[app/services/panel_analytics.rb](app/services/panel_analytics.rb), which reuses
`RecordingAnalytics` for everything the in-app statistics screen also shows so the
two can't disagree.

**New: magic-link sign-in, because Anava has no accounts.**
`POST /api/v1/panel/magic-link` ([app/controllers/panel_links_controller.rb](app/controllers/panel_links_controller.rb))
takes a device's anonymous `user_id` and returns a one-time URL. The design
decisions, all in [app/models/panel_magic_link.rb](app/models/panel_magic_link.rb):

- the URL carries a 32-byte random token, never the `user_id`, so a link seen in
  browser history or a referrer header doesn't expose the id it belongs to;
- only the token's SHA-256 digest is stored, so a database leak can't be replayed;
- redeeming is a single conditional `UPDATE`, not read-then-write, so two browsers
  racing the same link can't both be let in;
- tokens expire after 15 minutes and a device keeps at most 5 live ones; expired
  rows are purged opportunistically on issue, so no scheduler is needed;
- issuance is rate-limited to 5 requests per `user_id` per 5-minute window
  (429 past that). Issuing a link was never a stronger authorization boundary
  than the pre-existing, unauthenticated `GET /api/v1/recordings/user/:user_id`
  and `GET /api/v1/statistics?userId=` already are — anyone who knows a
  `user_id` could already read that device's full history — but without a
  rate limit, spamming issuance for a known `user_id` could evict a legitimate
  device's own in-flight link via the 5-live-links cap. The limit closes that
  DoS path (flagged by an automated security review) without a larger
  redesign around authenticated device identity, which is a separate,
  bigger change (per-device API keys/attestation) than this fix covers;
- `GET /panel/enter?token=` spends the token and calls `reset_session` before
  storing the user id, so a session cookie another browser already carried can't
  be reused.

**Schema.** New `panel_magic_links` table:
[db/migrate/20260920120000_create_panel_magic_links.rb](db/migrate/20260920120000_create_panel_magic_links.rb),
hand-matched in [db/schema.rb](db/schema.rb) and [db/init.sql](db/init.sql) the
same way the `recordings` table already is. `init.sql` only runs on a brand-new
Postgres volume, so **an existing deployment must create this table by hand** —
see "Deploying the panel table" in [README.md](README.md).

**Config.** `config.api_only` stays true, but `ActionDispatch::Cookies` and
`ActionDispatch::Session::CookieStore` are added back explicitly
([config/application.rb](config/application.rb)) — the panel needs a session, and
nothing else does. The cookie is `httponly`, `same_site: :lax`, `secure` in
production, and lasts 30 days. It is signed with `secret_key_base`, so
**`SECRET_KEY_BASE` must be set in production**: `config/master.key` is gitignored
and therefore absent from an image built from the repo.

**Shared helper.** `DashboardHelper` became
[app/helpers/recording_presentation_helper.rb](app/helpers/recording_presentation_helper.rb),
used by both the dashboard and the panel, and its slot naming now covers every
tradition's `slot_id` range (Islamic 0-4, Jewish 5-7, Christian 8-10, Custom
11-18) instead of only the five Islamic prayers.

**Tests.** 102 examples, all passing (was 51): new specs for the website at `/`,
admin auth, the magic-link model (including issuance rate limiting), the panel
end-to-end, and `PanelAnalytics` (including that a streak whose last day is
yesterday still counts — today isn't over). `swagger/v1/swagger.yaml`
regenerated to document the new endpoint and its 429 response.

- `POST /api/v1/recordings` is now idempotent: a repeated post with the same
  `user_id`, `slot_id`, `start_timestamp`, and `end_timestamp` updates the
  existing recording in place instead of creating a duplicate row. See
  `Recording.create_or_update_idempotently` in
  [app/models/recording.rb](app/models/recording.rb) and
  [app/controllers/recordings_controller.rb](app/controllers/recordings_controller.rb).
- Upgraded `puma` from `~> 6.4` to `~> 8.0` ([Gemfile](Gemfile)). Updated only
  `puma` and its own dependency (`nio4r`) in `Gemfile.lock` via
  `bundle update puma --conservative`, so unrelated gems (Rails, rubocop,
  json, etc.) stay pinned at their previous versions.
