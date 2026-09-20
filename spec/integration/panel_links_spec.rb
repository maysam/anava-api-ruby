require "swagger_helper"

RSpec.describe "api/v1/panel/magic-link", type: :request do
  path "/api/v1/panel/magic-link" do
    post("issue a one-time link to the device's own web panel") do
      tags "Panel"
      description <<~DESC
        Returns a single-use URL that signs the requesting device into its
        personal web panel. The device's anonymous user_id never appears in the
        URL: the link carries a random token, which is spent on first use and
        exchanged for a session cookie. Tokens expire after 15 minutes.

        Rate-limited to 5 issuances per user_id per 5-minute window (429 once
        exceeded), so a caller who only knows a device's user_id can't spam
        this endpoint to evict that device's own live link.
      DESC
      consumes "application/json"
      produces "application/json"
      parameter name: :body, in: :body, required: true, schema: {
        type: :object,
        required: %w[user_id],
        properties: {
          user_id: { type: :string, description: "The device's anonymous id (userId is also accepted)" }
        }
      }

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: {
                   type: :object,
                   properties: {
                     url: { type: :string, description: "Open this in a browser to enter the panel" },
                     expiresAt: { type: :string, format: :"date-time" },
                     expiresInSeconds: { type: :integer }
                   }
                 }
               }

        let(:body) { { user_id: "ab3f9c21-0000-4000-8000-000000000001" } }
        run_test!
      end

      response(400, "user_id missing") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 error: { type: :string }
               }

        let(:body) { {} }
        run_test!
      end

      response(429, "too many requests for this device") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 error: { type: :string }
               }

        before do
          PanelMagicLink::RATE_LIMIT_MAX_ISSUANCES.times do
            PanelMagicLink.issue("ab3f9c21-0000-4000-8000-000000000001")
          end
        end
        let(:body) { { user_id: "ab3f9c21-0000-4000-8000-000000000001" } }
        run_test!
      end
    end
  end
end
