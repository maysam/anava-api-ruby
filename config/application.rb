# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'active_record/railtie'

# Light Rails stack: Action Pack (routing + controllers), Active Record, and
# Action View — the last one only for the server-rendered dashboard
# (DashboardController, app/views/). No asset pipeline, no Action
# Mailer/Cable/Storage. The dashboard's CSS/JS/Chart.js are plain static files
# under public/, served by ActionDispatch::Static, not compiled assets.
Bundler.require(*Rails.groups)

module AnavaApi
  class Application < Rails::Application
    config.load_defaults 8.0

    # Still api_only at the framework level: the JSON controllers inherit from
    # ActionController::API (no CSRF/session middleware — the API is
    # token-less and hit by non-browser clients). The one HTML endpoint,
    # DashboardController, inherits from ActionController::Base directly and
    # renders ERB; it's GET-only and skips forgery protection, so it needs no
    # session either. See app/controllers/dashboard_controller.rb.
    config.api_only = true

    # Serve the dashboard's static assets (public/dashboard.css,
    # public/dashboard.js, public/vendor/chart.umd.min.js) via
    # ActionDispatch::Static in every environment. Off by default in
    # production unless RAILS_SERVE_STATIC_FILES is set, so enable explicitly.
    config.public_file_server.enabled = true

    # Deployed behind Coolify's Traefik proxy under an arbitrary domain; allow
    # any Host header (covers reaching the dashboard by IP or domain, and the
    # API by internal service name).
    config.hosts.clear
  end
end
