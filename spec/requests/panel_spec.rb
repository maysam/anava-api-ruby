# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'The personal panel', type: :request do
  let(:user_id) { 'ab3f9c21-0000-4000-8000-000000000001' }

  describe 'POST /api/v1/panel/magic-link' do
    it 'issues a one-time link for the requested device' do
      post '/api/v1/panel/magic-link', params: { user_id: user_id }.to_json,
                                       headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body['success']).to be(true)
      expect(body['data']['url']).to include('/panel/enter?token=')
      expect(body['data']['expiresInSeconds']).to eq(PanelMagicLink::TOKEN_TTL.to_i)
      expect(PanelMagicLink.where(user_id: user_id).count).to eq(1)
    end

    it 'accepts the camelCase spelling the iOS client encodes' do
      post '/api/v1/panel/magic-link', params: { userId: user_id }.to_json,
                                       headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
      expect(PanelMagicLink.where(user_id: user_id).count).to eq(1)
    end

    it 'never puts the raw token anywhere but the returned URL' do
      post '/api/v1/panel/magic-link', params: { user_id: user_id }.to_json,
                                       headers: { 'CONTENT_TYPE' => 'application/json' }

      raw_token = Rack::Utils.parse_query(URI.parse(response.parsed_body['data']['url']).query)['token']
      expect(PanelMagicLink.last.token_digest).to eq(PanelMagicLink.digest(raw_token))
    end

    it 'rejects a request without a user_id' do
      post '/api/v1/panel/magic-link', params: {}.to_json,
                                       headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body['error']).to match(/user_id/)
    end

    it 'rate-limits repeated requests for the same device instead of 500ing' do
      PanelMagicLink::RATE_LIMIT_MAX_ISSUANCES.times do
        post '/api/v1/panel/magic-link', params: { user_id: user_id }.to_json,
                                         headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      post '/api/v1/panel/magic-link', params: { user_id: user_id }.to_json,
                                       headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body['success']).to be(false)
    end

    it 'does not let rate-limit spam for one device evict another device\'s links' do
      PanelMagicLink::RATE_LIMIT_MAX_ISSUANCES.times do
        post '/api/v1/panel/magic-link', params: { user_id: user_id }.to_json,
                                         headers: { 'CONTENT_TYPE' => 'application/json' }
      end

      post '/api/v1/panel/magic-link', params: { user_id: 'another-device' }.to_json,
                                       headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'GET /panel/enter' do
    it 'exchanges a valid token for a session and redirects to the panel' do
      _link, raw_token = PanelMagicLink.issue(user_id)

      get '/panel/enter', params: { token: raw_token }

      expect(response).to redirect_to('/panel')
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Your personal panel')
    end

    it 'keeps the session alive across later requests' do
      _link, raw_token = PanelMagicLink.issue(user_id)
      get '/panel/enter', params: { token: raw_token }

      get '/panel'

      expect(response).to have_http_status(:ok)
    end

    it 'refuses a token that was already used' do
      _link, raw_token = PanelMagicLink.issue(user_id)
      get '/panel/enter', params: { token: raw_token }

      get '/panel/enter', params: { token: raw_token }

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('That link has expired')
    end

    it 'refuses an expired token' do
      link, raw_token = PanelMagicLink.issue(user_id)
      link.update!(expires_at: 1.second.ago)

      get '/panel/enter', params: { token: raw_token }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'GET /panel' do
    it 'asks the visitor to open it from the app when there is no session' do
      get '/panel'

      expect(response).to have_http_status(:unauthorized)
      expect(response.body).to include('Open your panel from the app')
    end

    it 'shows only this device\'s own recordings' do
      create(:recording, user_id: user_id, date: Date.current, slot_id: 1, duration: 120, percentage: 90)
      create(:recording, user_id: 'someone-else', date: Date.current, slot_id: 3, duration: 300, percentage: 99)
      _link, raw_token = PanelMagicLink.issue(user_id)
      get '/panel/enter', params: { token: raw_token }

      get '/panel'

      expect(response.body).to include('Dhuhr')
      expect(response.body).not_to include('Maghrib')
      expect(response.body).to include('90%')
    end

    it 'shows an empty state for a device that has not synced anything yet' do
      _link, raw_token = PanelMagicLink.issue(user_id)
      get '/panel/enter', params: { token: raw_token }

      get '/panel'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Nothing recorded yet')
    end

    it 'never renders the full device id' do
      _link, raw_token = PanelMagicLink.issue(user_id)
      get '/panel/enter', params: { token: raw_token }

      get '/panel'

      expect(response.body).not_to include(user_id)
      expect(response.body).to include(user_id.first(8))
    end
  end

  describe 'GET /panel/sign-out' do
    it 'drops the session and sends the visitor back to the website' do
      _link, raw_token = PanelMagicLink.issue(user_id)
      get '/panel/enter', params: { token: raw_token }

      get '/panel/sign-out'
      expect(response).to redirect_to('/')

      get '/panel'
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
