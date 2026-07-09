require "rails_helper"

RSpec.describe "GET /api/v1/statistics", type: :request do
  it "returns a user's analytics plus the total player count" do
    create(:recording, user_id: "alice", percentage: 80)
    create(:recording, user_id: "bob", percentage: 40)

    get "/api/v1/statistics", params: { userId: "alice" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["success"]).to eq(true)
    expect(body["data"]["totalRecordings"]).to eq(1)
    expect(body["data"]["totalPlayersCount"]).to eq(2)
  end
end
