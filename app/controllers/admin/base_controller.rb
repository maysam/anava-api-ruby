# frozen_string_literal: true

module Admin
  # Shared base for the operator-facing admin area (mounted at /admin since the
  # public website took over `/`). Inherits from ActionController::Base rather
  # than the API's ActionController::API so it can render ERB.
  #
  # Access control is HTTP Basic, enabled by setting ANAVA_ADMIN_PASSWORD. When
  # that variable is unset the admin area stays open — the same posture the
  # dashboard had while it lived at `/` — and the layout renders a warning
  # banner instead, so an unprotected deployment is visible rather than silent.
  class BaseController < ActionController::Base
    layout 'admin'
    skip_forgery_protection

    before_action :authenticate_admin!

    DEFAULT_ADMIN_USERNAME = 'admin'

    # Exposed to the layout so it can render the "unprotected" warning banner.
    helper_method :admin_authentication_configured?

    private

    def admin_authentication_configured?
      configured_admin_password.present?
    end

    def authenticate_admin!
      return unless admin_authentication_configured?

      authenticate_or_request_with_http_basic('Anava Admin') do |username, password|
        ActiveSupport::SecurityUtils.secure_compare(username.to_s, configured_admin_username) &
          ActiveSupport::SecurityUtils.secure_compare(password.to_s, configured_admin_password)
      end
    end

    def configured_admin_username
      ENV.fetch('ANAVA_ADMIN_USERNAME', DEFAULT_ADMIN_USERNAME)
    end

    def configured_admin_password
      ENV.fetch('ANAVA_ADMIN_PASSWORD', nil)
    end
  end
end
