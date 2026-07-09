require "swagger_helper"

RSpec.describe "health", type: :request do
  path "/health" do
    get("check API health") do
      tags "Health"
      produces "application/json"

      response(200, "API is running") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 message: { type: :string },
                 timestamp: { type: :string, format: "date-time" }
               }

        run_test!
      end
    end
  end
end
