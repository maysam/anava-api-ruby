require "rails_helper"

RSpec.describe Recording, type: :model do
  describe ".total_players_count" do
    it "counts distinct user_ids across all recordings" do
      create(:recording, user_id: "alice")
      create(:recording, user_id: "alice")
      create(:recording, user_id: "bob")

      expect(Recording.total_players_count).to eq(2)
    end
  end

  describe ".filter_by_params" do
    it "filters by an exact date when :date is given" do
      matching = create(:recording, date: Date.new(2026, 1, 1))
      create(:recording, date: Date.new(2026, 1, 2))

      result = Recording.filter_by_params(Recording.all, ActionController::Parameters.new(date: "2026-01-01"))

      expect(result).to contain_exactly(matching)
    end

    it "filters by a startDate/endDate range when both are given" do
      in_range = create(:recording, date: Date.new(2026, 1, 5))
      create(:recording, date: Date.new(2026, 1, 1))
      create(:recording, date: Date.new(2026, 1, 20))

      result = Recording.filter_by_params(
        Recording.all,
        ActionController::Parameters.new(startDate: "2026-01-03", endDate: "2026-01-10")
      )

      expect(result).to contain_exactly(in_range)
    end

    it "returns the scope unchanged when no filters are given" do
      create_list(:recording, 2)

      result = Recording.filter_by_params(Recording.all, ActionController::Parameters.new)

      expect(result.count).to eq(2)
    end
  end
end
