# Changelog

## Unreleased

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
