# frozen_string_literal: true

# A single-use, short-lived token that lets a device open its own web panel in
# a browser without the app ever having accounts or passwords.
#
# The app's only identity is the anonymous UUID it generates on first launch
# (`Defaults.getUserId()` on Android, `SettingsStore.userId` on iOS). Putting
# that UUID straight into a URL would make the panel permanently reachable by
# anyone who saw the link — in browser history, in a referrer header, over a
# shoulder. So the device instead asks for a magic link, which:
#
#   * carries a 32-byte random token, not the user_id;
#   * is stored only as a SHA-256 digest, so a database leak can't be replayed;
#   * expires after TOKEN_TTL;
#   * is consumed on first use, and exchanged there for a session cookie.
class PanelMagicLink < ActiveRecord::Base
  TOKEN_TTL = 15.minutes

  # How many unconsumed links one device may hold at once. Requesting another
  # expires the oldest, so a device that taps "Open my panel" repeatedly can't
  # grow an unbounded set of live tokens.
  MAX_LIVE_LINKS_PER_USER = 5

  # Issuance has no stronger identity check than "the caller knows this
  # user_id" (the same trust boundary the pre-existing, unauthenticated
  # GET /api/v1/recordings/user/:user_id and GET /api/v1/statistics?userId=
  # already place in that id — this endpoint doesn't expose anything those
  # don't). What it *does* add is an eviction path: MAX_LIVE_LINKS_PER_USER
  # means spamming .issue for a known user_id could evict a legitimate
  # in-flight link before the real device redeems it. RATE_LIMIT_* closes
  # that: a caller (legitimate or not) gets a handful of issuances per
  # window, then 429s, so eviction-by-spam and free-form probing both cost
  # something.
  RATE_LIMIT_WINDOW = 5.minutes
  RATE_LIMIT_MAX_ISSUANCES = 5

  class RateLimitedError < StandardError; end

  class << self
    # Issues a new link for `user_id` and returns [link, raw_token]. The raw
    # token exists only in this return value — it is never stored or logged.
    #
    # Raises RateLimitedError once RATE_LIMIT_MAX_ISSUANCES have been issued
    # for this user_id within RATE_LIMIT_WINDOW — counting every issuance,
    # not just live ones, so redeeming links faster than they're rate-limited
    # can't be used to dodge the limit.
    def issue(user_id)
      raise RateLimitedError if rate_limited?(user_id)

      raw_token = SecureRandom.urlsafe_base64(32)
      expire_surplus_links_for(user_id)

      link = create!(
        user_id: user_id,
        token_digest: digest(raw_token),
        expires_at: Time.current + TOKEN_TTL
      )
      [link, raw_token]
    end

    # Consumes `raw_token` and returns the user_id it belonged to, or nil when
    # the token is unknown, already used, or expired.
    #
    # The consume is a single conditional UPDATE rather than a read-then-write,
    # so two browsers opening the same link concurrently can't both be let in:
    # exactly one UPDATE matches the still-unconsumed row.
    def redeem(raw_token)
      return nil if raw_token.blank?

      token_digest = digest(raw_token)
      consumed_count = where(token_digest: token_digest, consumed_at: nil)
                       .where(expires_at: Time.current..)
                       .update_all(consumed_at: Time.current, updated_at: Time.current)
      return nil if consumed_count.zero?

      find_by(token_digest: token_digest)&.user_id
    end

    # Housekeeping for rows nobody can use any more. Called opportunistically
    # when a link is issued, so no scheduler is needed.
    def purge_expired(older_than: 7.days)
      where(expires_at: ...(Time.current - older_than)).delete_all
    end

    def digest(raw_token)
      Digest::SHA256.hexdigest(raw_token.to_s)
    end

    private

    def rate_limited?(user_id)
      where(user_id: user_id, created_at: RATE_LIMIT_WINDOW.ago..).count >= RATE_LIMIT_MAX_ISSUANCES
    end

    def expire_surplus_links_for(user_id)
      purge_expired

      live_links = where(user_id: user_id, consumed_at: nil)
                   .where(expires_at: Time.current..)
                   .order(created_at: :desc)
                   .offset(MAX_LIVE_LINKS_PER_USER - 1)
      where(id: live_links.select(:id)).delete_all
    end
  end

  def expired?
    expires_at <= Time.current
  end
end
