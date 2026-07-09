require "swagger_helper"

RSpec.describe "api/v1/statistics", type: :request do
  path "/api/v1/statistics" do
    get("get a user's statistics") do
      tags "Statistics"
      produces "application/json"
      parameter name: :userId, in: :query, type: :string, required: false,
                description: "User to compute statistics/ranking for"

      response(200, "successful") do
        schema type: :object,
               properties: {
                 success: { type: :boolean },
                 data: {
                   type: :object,
                   properties: {
                     totalRecordings: { type: :integer },
                     totalDuration: { type: :integer },
                     averagePercentage: { type: :integer },
                     averageDuration: { type: :integer },
                     rankingToday: { type: :integer },
                     rankingLastWeek: { type: :integer },
                     rankingLastMonth: { type: :integer },
                     total: { type: :integer },
                     totalPlayersCount: { type: :integer }
                   }
                 }
               }

        let(:userId) { create(:recording).user_id }
        run_test!
      end
    end
  end
end
