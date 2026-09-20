# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PanelMagicLink do
  # Issues `count` links for `user_id`, stepping past RATE_LIMIT_WINDOW
  # whenever RATE_LIMIT_MAX_ISSUANCES would otherwise be hit, so tests about
  # eviction/isolation aren't incidentally testing the rate limiter too.
  def issue_many(user_id, count)
    count.times do |i|
      starting_new_window = i.positive? && (i % described_class::RATE_LIMIT_MAX_ISSUANCES).zero?
      travel(described_class::RATE_LIMIT_WINDOW + 1.second) if starting_new_window
      described_class.issue(user_id)
    end
  end

  describe '.issue' do
    it 'returns a token that is only ever stored as a digest' do
      link, raw_token = described_class.issue('device-1')

      expect(raw_token).to be_present
      expect(link.token_digest).to eq(Digest::SHA256.hexdigest(raw_token))
      expect(described_class.pluck(:token_digest)).not_to include(raw_token)
    end

    it 'expires after TOKEN_TTL' do
      link, = described_class.issue('device-1')

      expect(link.expires_at).to be_within(5.seconds).of(Time.current + described_class::TOKEN_TTL)
    end

    it 'keeps at most MAX_LIVE_LINKS_PER_USER live links per device' do
      issue_many('device-1', described_class::MAX_LIVE_LINKS_PER_USER + 3)

      expect(described_class.where(user_id: 'device-1').count)
        .to eq(described_class::MAX_LIVE_LINKS_PER_USER)
    end

    it 'does not expire another device\'s links' do
      described_class.issue('device-2')
      issue_many('device-1', described_class::MAX_LIVE_LINKS_PER_USER + 3)

      expect(described_class.where(user_id: 'device-2').count).to eq(1)
    end
  end

  describe '.issue rate limiting' do
    it 'allows up to RATE_LIMIT_MAX_ISSUANCES issuances per user within the window' do
      expect { issue_many('device-1', described_class::RATE_LIMIT_MAX_ISSUANCES) }.not_to raise_error
    end

    it 'refuses the next issuance once the window\'s limit is reached' do
      described_class::RATE_LIMIT_MAX_ISSUANCES.times { described_class.issue('device-1') }

      expect { described_class.issue('device-1') }.to raise_error(described_class::RateLimitedError)
    end

    it 'does not count consumed or expired links against a later issuance' do
      described_class::RATE_LIMIT_MAX_ISSUANCES.times { described_class.issue('device-1') }
      expect { described_class.issue('device-1') }.to raise_error(described_class::RateLimitedError)

      travel(described_class::RATE_LIMIT_WINDOW + 1.second)

      expect { described_class.issue('device-1') }.not_to raise_error
    end

    it 'rate-limits per device, not globally' do
      described_class::RATE_LIMIT_MAX_ISSUANCES.times { described_class.issue('device-1') }

      expect { described_class.issue('device-2') }.not_to raise_error
    end
  end

  describe '.redeem' do
    it 'returns the user_id the token was issued for' do
      _link, raw_token = described_class.issue('device-1')

      expect(described_class.redeem(raw_token)).to eq('device-1')
    end

    it 'can only be redeemed once' do
      _link, raw_token = described_class.issue('device-1')

      expect(described_class.redeem(raw_token)).to eq('device-1')
      expect(described_class.redeem(raw_token)).to be_nil
    end

    it 'refuses an expired token' do
      link, raw_token = described_class.issue('device-1')
      link.update!(expires_at: 1.second.ago)

      expect(described_class.redeem(raw_token)).to be_nil
    end

    it 'refuses an unknown or blank token' do
      expect(described_class.redeem('not-a-real-token')).to be_nil
      expect(described_class.redeem(nil)).to be_nil
      expect(described_class.redeem('')).to be_nil
    end
  end

  describe '.purge_expired' do
    it 'deletes only links that expired longer ago than the grace window' do
      recently_expired, = described_class.issue('device-1')
      recently_expired.update!(expires_at: 1.hour.ago)
      long_expired, = described_class.issue('device-1')
      long_expired.update!(expires_at: 30.days.ago)
      live, = described_class.issue('device-1')

      described_class.purge_expired

      expect(described_class.pluck(:id)).to contain_exactly(recently_expired.id, live.id)
    end
  end
end
