# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /health', type: :request do
  it 'reports the API as running' do
    get '/health'

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body['success']).to eq(true)
    expect(body['message']).to eq('API is running')
  end
end
