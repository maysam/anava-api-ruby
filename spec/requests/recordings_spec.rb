require "rails_helper"

RSpec.describe "Recordings", type: :request do
  let(:json_headers) { { "Content-Type" => "application/json" } }

  describe "POST /api/v1/recordings" do
    it "creates a recording, tagging it with the request's device headers" do
      attributes = attributes_for(:recording)

      post "/api/v1/recordings",
           params: attributes.to_json,
           headers: json_headers.merge("X-Device-Model" => "Pixel-7", "X-App-Version" => "1.2.3")

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["success"]).to eq(true)
      expect(Recording.count).to eq(1)
      expect(Recording.last.model).to eq("Pixel-7")
      expect(Recording.last.version).to eq("1.2.3")
    end

    it "computes duration from the timestamps when none is given" do
      attributes = attributes_for(:recording).except(:duration).merge(start_timestamp: 1_000, end_timestamp: 5_500)

      post "/api/v1/recordings", params: attributes.to_json, headers: json_headers

      expect(Recording.last.duration).to eq(4)
    end

    it "rejects an invalid JSON body" do
      post "/api/v1/recordings", params: "not-json", headers: json_headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "GET /api/v1/recordings/:id" do
    it "returns the recording" do
      recording = create(:recording)

      get "/api/v1/recordings/#{recording.id}"

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["id"]).to eq(recording.id)
    end

    it "returns 404 for a missing recording" do
      get "/api/v1/recordings/0"

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PUT /api/v1/recordings/:id" do
    it "updates only the given fields" do
      recording = create(:recording, percentage: 10)

      put "/api/v1/recordings/#{recording.id}", params: { percentage: 90 }.to_json, headers: json_headers

      expect(response).to have_http_status(:ok)
      expect(recording.reload.percentage).to eq(90)
    end

    it "rejects an update with no writable fields" do
      recording = create(:recording)

      put "/api/v1/recordings/#{recording.id}", params: {}.to_json, headers: json_headers

      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "DELETE /api/v1/recordings/:id" do
    it "deletes the recording" do
      recording = create(:recording)

      delete "/api/v1/recordings/#{recording.id}"

      expect(response).to have_http_status(:ok)
      expect(Recording.exists?(recording.id)).to eq(false)
    end
  end

  describe "GET /api/v1/recordings/user/:user_id" do
    it "returns only that user's recordings, grouped by date" do
      mine = create(:recording, user_id: "alice", date: Date.new(2026, 1, 1))
      create(:recording, user_id: "bob")

      get "/api/v1/recordings/user/alice"

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].length).to eq(1)
      expect(body["data"].first["id"]).to eq(mine.id)
      expect(body["groupedByDate"]).to have_key("2026-01-01")
    end
  end
end
