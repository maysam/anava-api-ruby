# frozen_string_literal: true

require 'rails_helper'

# The dashboard used to be the site root and wide open. It now lives under
# /admin and gains HTTP Basic auth as soon as ANAVA_ADMIN_PASSWORD is set; with
# the variable unset it stays open (unchanged posture) but says so on the page.
RSpec.describe 'Admin authentication', type: :request do
  def basic_auth_header(username, password)
    { 'HTTP_AUTHORIZATION' => ActionController::HttpAuthentication::Basic.encode_credentials(username, password) }
  end

  context 'when ANAVA_ADMIN_PASSWORD is unset' do
    it 'serves the dashboard and warns that it is unprotected' do
      get '/admin'

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('unprotected')
    end
  end

  context 'when ANAVA_ADMIN_PASSWORD is set' do
    around do |example|
      ENV['ANAVA_ADMIN_PASSWORD'] = 'let-me-in'
      example.run
      ENV.delete('ANAVA_ADMIN_PASSWORD')
      ENV.delete('ANAVA_ADMIN_USERNAME')
    end

    it 'challenges an anonymous visitor' do
      get '/admin'

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects a wrong password' do
      get '/admin', headers: basic_auth_header('admin', 'nope')

      expect(response).to have_http_status(:unauthorized)
    end

    it 'lets the right credentials through, without the warning banner' do
      get '/admin', headers: basic_auth_header('admin', 'let-me-in')

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('unprotected')
    end

    it 'honours a custom ANAVA_ADMIN_USERNAME' do
      ENV['ANAVA_ADMIN_USERNAME'] = 'maysam'

      get '/admin', headers: basic_auth_header('admin', 'let-me-in')
      expect(response).to have_http_status(:unauthorized)

      get '/admin', headers: basic_auth_header('maysam', 'let-me-in')
      expect(response).to have_http_status(:ok)
    end

    it 'does not put the panel behind admin auth' do
      get '/panel'

      # Unauthorized because there is no panel session — not an admin challenge.
      expect(response).to have_http_status(:unauthorized)
      expect(response.headers['WWW-Authenticate']).to be_nil
    end
  end
end
