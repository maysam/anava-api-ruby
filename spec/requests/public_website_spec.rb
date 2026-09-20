# frozen_string_literal: true

require 'rails_helper'

# `/` is the marketing website now, served straight out of public/ by
# ActionDispatch::Static — there is deliberately no root route (see
# config/routes.rb). These specs guard that arrangement: a root route added
# later would silently shadow the website, and so would a public/ rename.
RSpec.describe 'The public website', type: :request do
  it 'serves the marketing site at the root path' do
    get '/'

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with('text/html')
    expect(response.body).to include('Anava - Sacred Prayer Recording App')
  end

  it 'serves the website\'s other pages and assets' do
    get '/privacy-policy.html'
    expect(response).to have_http_status(:ok)

    get '/css/styles.css'
    expect(response).to have_http_status(:ok)
    expect(response.content_type).to start_with('text/css')
  end

  it 'still serves the Android app-links association file' do
    get '/.well-known/assetlinks.json'

    expect(response).to have_http_status(:ok)
  end

  it 'keeps serving the API under the website' do
    get '/health'

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['success']).to be(true)
  end
end
