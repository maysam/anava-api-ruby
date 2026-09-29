# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Recording, type: :model do
  describe '.total_players_count' do
    it 'counts distinct user_ids across all recordings' do
      create(:recording, user_id: 'alice')
      create(:recording, user_id: 'alice')
      create(:recording, user_id: 'bob')

      expect(Recording.total_players_count).to eq(2)
    end
  end

  describe '.filter_by_params' do
    it 'filters by an exact date when :date is given' do
      matching = create(:recording, date: Date.new(2026, 1, 1))
      create(:recording, date: Date.new(2026, 1, 2))

      result = Recording.filter_by_params(Recording.all, ActionController::Parameters.new(date: '2026-01-01'))

      expect(result).to contain_exactly(matching)
    end

    it 'filters by a startDate/endDate range when both are given' do
      in_range = create(:recording, date: Date.new(2026, 1, 5))
      create(:recording, date: Date.new(2026, 1, 1))
      create(:recording, date: Date.new(2026, 1, 20))

      result = Recording.filter_by_params(
        Recording.all,
        ActionController::Parameters.new(startDate: '2026-01-03', endDate: '2026-01-10')
      )

      expect(result).to contain_exactly(in_range)
    end

    it 'returns the scope unchanged when no filters are given' do
      create_list(:recording, 2)

      result = Recording.filter_by_params(Recording.all, ActionController::Parameters.new)

      expect(result.count).to eq(2)
    end
  end

  describe '#activity_percentage / #as_json' do
    it 'reports a negative percentage as zero without changing the stored value' do
      recording = create(:recording, percentage: -12)

      expect(recording.activity_percentage).to eq(0)
      expect(recording.as_json['percentage']).to eq(0)
      expect(recording.reload.percentage).to eq(-12)
    end

    it 'keeps positive and nil percentages as they are' do
      expect(build(:recording, percentage: 42).activity_percentage).to eq(42)
      expect(build(:recording, percentage: nil).as_json['percentage']).to be_nil
    end
  end
end
