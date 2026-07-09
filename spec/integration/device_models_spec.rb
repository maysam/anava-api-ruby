require "swagger_helper"

RSpec.describe "api/v1/models", type: :request do
  path "/api/v1/models" do
    get("list distinct device models") do
      tags "Device models"
      produces "application/json"

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 models: { type: :array, items: { type: :string } }
               }

        before { create(:recording, model: "Pixel-7") }
        run_test!
      end
    end
  end
end
