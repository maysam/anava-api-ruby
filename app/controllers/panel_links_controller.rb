# frozen_string_literal: true

# Issues magic links so the mobile apps (Android and iOS) can open their own
# web panel in a browser. See PanelMagicLink for why a link is handed out
# instead of just putting the device's anonymous user_id in a URL.
#
# POST /api/v1/panel/magic-link  { "user_id": "<the device's anonymous uuid>" }
#   -> { "success": true, "data": { "url": ..., "expiresAt": ..., "expiresInSeconds": ... } }
class PanelLinksController < ApplicationController
  # Declared here (not in ApplicationController) so only this endpoint gets
  # the 429 behavior; per ApplicationController's own rescue_from ordering
  # note, a subclass's handlers are checked before the inherited StandardError
  # catch-all, so this wins over that instead of surfacing as a 500.
  rescue_from PanelMagicLink::RateLimitedError, with: :render_rate_limited

  def create
    user_id = requested_user_id
    raise InvalidRequestError, 'user_id is required' if user_id.blank?

    link, raw_token = PanelMagicLink.issue(user_id)
    render json: { success: true, data: link_payload(link, raw_token) }
  end

  private

  def render_rate_limited(_error)
    render json: { success: false, error: 'Too many panel link requests. Try again shortly.' },
           status: :too_many_requests
  end

  def link_payload(link, raw_token)
    {
      url: panel_entry_url(raw_token),
      expiresAt: link.expires_at.utc.iso8601,
      expiresInSeconds: PanelMagicLink::TOKEN_TTL.to_i
    }
  end

  def requested_user_id
    body = parsed_json_body
    (body['user_id'] || body['userId']).to_s.strip
  end

  def panel_entry_url(raw_token)
    "#{public_base_url}/panel/enter?token=#{CGI.escape(raw_token)}"
  end

  # Behind Coolify's Traefik proxy the forwarded headers already give the
  # public scheme/host, so request.base_url is normally right. ANAVA_PUBLIC_BASE_URL
  # is the escape hatch for deployments where they aren't (or where the panel
  # lives on a different hostname than the API).
  def public_base_url
    ENV['ANAVA_PUBLIC_BASE_URL'].presence&.chomp('/') || request.base_url
  end
end
