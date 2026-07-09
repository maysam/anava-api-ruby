# frozen_string_literal: true

source 'https://rubygems.org'

ruby '>= 3.2'

# Light Rails setup: Action Pack (routing + controllers), Railties, and
# Active Record for the Postgres data layer. No Action View, no asset
# pipeline, no Action Mailer/Cable/Storage.
gem 'actionpack', '~> 8.0'
gem 'activerecord', '~> 8.0'
gem 'activesupport', '~> 8.0'
gem 'railties', '~> 8.0'

gem 'pg', '~> 1.5'
gem 'puma', '~> 6.4'
gem 'rack-cors', '~> 2.0'

# Serves the generated OpenAPI doc + Swagger UI at /api-docs (see
# spec/swagger_helper.rb and config/initializers/rswag_*.rb).
gem 'rswag-api', '~> 2.17'
gem 'rswag-ui', '~> 2.17'

group :development, :test do
  gem 'factory_bot_rails', '~> 6.0'
  gem 'faker', '~> 3.0'
  gem 'rspec-rails', '~> 6.0'
  gem 'rswag-specs', '~> 2.17'
  gem 'rubocop', '~> 1.88'
end

group :test do
  # Specs run against SQLite instead of Postgres: no external database
  # server needed, and db/init.sql (Postgres-specific: SERIAL, trigger
  # functions) isn't portable anyway. See db/schema.rb.
  gem 'sqlite3', '~> 2.0'
end
