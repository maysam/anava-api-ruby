require_relative "boot"

require "rails"
require "action_controller/railtie"
require "active_record/railtie"

# Only load the framework pieces this API actually uses (Action Pack +
# Active Record). No Action View, asset pipeline, Action Mailer/Cable/Storage.
Bundler.require(*Rails.groups)

module AnavaApi
  class Application < Rails::Application
    config.load_defaults 8.0

    config.api_only = true

    # Deployed behind Coolify's Traefik proxy under an arbitrary domain;
    # there's no browser-facing HTML here, so host header allowlisting
    # (Rails' default anti-DNS-rebinding protection) isn't needed.
    config.hosts.clear
  end
end
