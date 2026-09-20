# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'active_record/railtie'

# Light Rails stack: Action Pack (routing + controllers), Active Record, and
# Action View — the last one only for the server-rendered HTML views (the admin
# dashboard and the per-user panel, app/views/). No asset pipeline, no Action
# Mailer/Cable/Storage. The public website, the dashboard's CSS/JS/Chart.js and
# the panel's stylesheet are all plain static files under public/, served by
# ActionDispatch::Static, not compiled assets.
Bundler.require(*Rails.groups)

module AnavaApi
  class Application < Rails::Application
    config.load_defaults 8.0

    # Still api_only at the framework level: the JSON controllers inherit from
    # ActionController::API (no CSRF middleware — the API is token-less and hit
    # by non-browser clients). The HTML endpoints inherit from
    # ActionController::Base directly and render ERB: Admin::DashboardController
    # (GET-only, stateless) and PanelController (needs a session — see below).
    config.api_only = true

    # api_only drops the cookie/session middleware, which the per-user panel
    # needs: a magic link is redeemed once and exchanged for a session cookie,
    # so the device's anonymous user_id never sits in a URL (see
    # app/controllers/panel_controller.rb). Added back explicitly, and only
    # these two — no flash, no CSRF token storage.
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use ActionDispatch::Session::CookieStore,
                          key: '_anava_panel_session',
                          same_site: :lax,
                          httponly: true,
                          secure: Rails.env.production?,
                          # Seconds, not `30.days`: ActiveSupport's numeric core
                          # extensions aren't loaded yet this early in boot.
                          expire_after: 30 * 24 * 60 * 60

    # Serve the public website (public/index.html and friends), the admin
    # dashboard's assets (public/admin/) and the panel's (public/panel/) via
    # ActionDispatch::Static in every environment. Off by default in
    # production unless RAILS_SERVE_STATIC_FILES is set, so enable explicitly.
    config.public_file_server.enabled = true

    # Deployed behind Coolify's Traefik proxy under an arbitrary domain; allow
    # any Host header (covers reaching the dashboard by IP or domain, and the
    # API by internal service name).
    config.hosts.clear
  end
end
