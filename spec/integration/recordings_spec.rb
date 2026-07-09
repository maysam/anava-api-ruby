require "swagger_helper"

RSpec.describe "api/v1/recordings", type: :request do
  path "/api/v1/recordings" do
    get("list recordings") do
      tags "Recordings"
      produces "application/json"
      parameter name: :userId, in: :query, type: :string, required: false
      parameter name: :date, in: :query, type: :string, required: false, description: "Exact date filter (YYYY-MM-DD)"
      parameter name: :startDate, in: :query, type: :string, required: false
      parameter name: :endDate, in: :query, type: :string, required: false
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :array, items: { "$ref" => "#/components/schemas/Recording" } },
                 pagination: {
                   type: :object,
                   properties: {
                     total: { type: :integer },
                     limit: { type: :integer },
                     offset: { type: :integer }
                   }
                 }
               }

        let(:userId) { nil }
        let(:date) { nil }
        let(:startDate) { nil }
        let(:endDate) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        before { create(:recording) }
        run_test!
      end
    end

    post("create a recording") do
      tags "Recordings"
      consumes "application/json"
      produces "application/json"
      parameter name: :recording, in: :body, schema: {
        type: :object,
        properties: {
          user_id: { type: :string },
          date: { type: :string, format: "date" },
          slot_id: { type: :integer },
          start_timestamp: { type: :integer, format: "int64" },
          end_timestamp: { type: :integer, format: "int64" },
          amplitudes_json: { type: :string },
          percentage: { type: :integer },
          longitude: { type: :number },
          latitude: { type: :number }
        },
        required: %w[user_id date slot_id start_timestamp end_timestamp amplitudes_json]
      }
      description <<~DESC
        `duration` is computed from start_timestamp/end_timestamp if omitted. `model`, `build`, and
        `version` are always overwritten server-side from the X-Device-Model, X-Forwarded-For, and
        X-App-Version headers.

        Instead of a JSON body, this endpoint also accepts `multipart/form-data` with the same
        fields (as form fields) plus a `file` part holding the recording's WAV audio -- its saved
        path is then stored as `file_path`. Not modeled below since this schema only describes the
        JSON request body.
      DESC

      response(200, "recording created; returns the creator's updated analytics") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :object, description: "Same shape as GET /api/v1/statistics's data" }
               }

        let(:recording) { attributes_for(:recording) }
        run_test!
      end
    end
  end

  path "/api/v1/recordings/{id}" do
    parameter name: :id, in: :path, type: :integer

    get("show a recording") do
      tags "Recordings"
      produces "application/json"

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { "$ref" => "#/components/schemas/Recording" }
               }

        let(:id) { create(:recording).id }
        run_test!
      end

      response(404, "recording not found") do
        let(:id) { 0 }
        run_test!
      end
    end

    put("update a recording") do
      tags "Recordings"
      consumes "application/json"
      produces "application/json"
      parameter name: :updates, in: :body, schema: {
        type: :object,
        description: "Any subset of the writable Recording fields; at least one is required."
      }

      response(200, "recording updated") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { "$ref" => "#/components/schemas/Recording" }
               }

        let(:id) { create(:recording).id }
        let(:updates) { { percentage: 90 } }
        run_test!
      end

      response(400, "no writable fields given") do
        let(:id) { create(:recording).id }
        let(:updates) { {} }
        run_test!
      end

      response(404, "recording not found") do
        let(:id) { 0 }
        let(:updates) { { percentage: 90 } }
        run_test!
      end
    end

    delete("delete a recording") do
      tags "Recordings"
      produces "application/json"

      response(200, "recording deleted") do
        let(:id) { create(:recording).id }
        run_test!
      end
    end
  end

  path "/api/v1/recordings/user/{user_id}" do
    parameter name: :user_id, in: :path, type: :string

    get("list a user's recordings, grouped by date") do
      tags "Recordings"
      produces "application/json"
      parameter name: :date, in: :query, type: :string, required: false
      parameter name: :startDate, in: :query, type: :string, required: false
      parameter name: :endDate, in: :query, type: :string, required: false
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :array, items: { "$ref" => "#/components/schemas/Recording" } },
                 groupedByDate: { type: :object, description: "Recordings keyed by ISO date string" },
                 pagination: {
                   type: :object,
                   properties: {
                     total: { type: :integer },
                     limit: { type: :integer },
                     offset: { type: :integer }
                   }
                 }
               }

        let(:user_id) { create(:recording).user_id }
        let(:date) { nil }
        let(:startDate) { nil }
        let(:endDate) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/recordings/analytics/{user_id}" do
    parameter name: :user_id, in: :path, type: :string

    get("get a user's daily/weekly/monthly recording analytics") do
      tags "Recordings"
      produces "application/json"

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 analytics: {
                   type: :object,
                   properties: {
                     daily: { type: :object },
                     weekly: { type: :object },
                     monthly: { type: :object }
                   }
                 }
               }

        let(:user_id) { create(:recording).user_id }
        run_test!
      end
    end
  end

  path "/api/v1/recordings/model/{model}" do
    parameter name: :model, in: :path, type: :string

    get("list recordings for a device model, grouped by date") do
      tags "Recordings"
      produces "application/json"
      parameter name: :date, in: :query, type: :string, required: false
      parameter name: :startDate, in: :query, type: :string, required: false
      parameter name: :endDate, in: :query, type: :string, required: false
      parameter name: :limit, in: :query, type: :integer, required: false
      parameter name: :offset, in: :query, type: :integer, required: false

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: { type: :array, items: { "$ref" => "#/components/schemas/Recording" } },
                 groupedByDate: { type: :object },
                 pagination: {
                   type: :object,
                   properties: {
                     total: { type: :integer },
                     limit: { type: :integer },
                     offset: { type: :integer }
                   }
                 }
               }

        let(:model) { create(:recording).model }
        let(:date) { nil }
        let(:startDate) { nil }
        let(:endDate) { nil }
        let(:limit) { nil }
        let(:offset) { nil }
        run_test!
      end
    end
  end

  path "/api/v1/recordings/analytics-by-model/{model}" do
    parameter name: :model, in: :path, type: :string

    get("get a device model's daily/weekly/monthly recording analytics") do
      tags "Recordings"
      produces "application/json"

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 analytics: {
                   type: :object,
                   properties: {
                     daily: { type: :object },
                     weekly: { type: :object },
                     monthly: { type: :object }
                   }
                 }
               }

        let(:model) { create(:recording).model }
        run_test!
      end
    end
  end
end
