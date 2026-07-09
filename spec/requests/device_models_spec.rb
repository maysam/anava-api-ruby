require "rails_helper"

RSpec.describe "GET /api/v1/models", type: :request do
  it "lists distinct, non-blank device models in alphabetical order" do
    create(:recording, model: "Pixel-7")
    create(:recording, model: "iPhone-14")
    create(:recording, model: "Pixel-7")
    create(:recording, model: "")

    get "/api/v1/models"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["success"]).to eq(true)
    expect(body["models"]).to eq(%w[Pixel-7 iPhone-14].sort)
  end
end
