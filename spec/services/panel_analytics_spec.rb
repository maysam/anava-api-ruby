# frozen_string_literal: true

require 'rails_helper'

RSpec.describe PanelAnalytics do
  let(:user_id) { 'device-1' }
  let(:today) { Date.new(2026, 9, 20) }

  def record_on(date, user: user_id, **attributes)
    create(:recording, { user_id: user, date: date }.merge(attributes))
  end

  describe '.current_streak' do
    it 'counts consecutive days back from today' do
      dates = [today - 2, today - 1, today]

      expect(described_class.current_streak(dates, today)).to eq(3)
    end

    it 'still counts a streak whose last day is yesterday — today is not over' do
      dates = [today - 2, today - 1]

      expect(described_class.current_streak(dates, today)).to eq(2)
    end

    it 'is zero once a day has actually been missed' do
      dates = [today - 5, today - 4, today - 3]

      expect(described_class.current_streak(dates, today)).to eq(0)
    end

    it 'is zero with no recordings at all' do
      expect(described_class.current_streak([], today)).to eq(0)
    end
  end

  describe '.longest_streak' do
    it 'finds the longest run anywhere in the history' do
      dates = [today - 40, today - 20, today - 19, today - 18, today - 17, today - 2, today]

      expect(described_class.longest_streak(dates)).to eq(4)
    end

    it 'is zero with no recordings' do
      expect(described_class.longest_streak([])).to eq(0)
    end
  end

  describe '.overview' do
    it 'covers only the requesting device' do
      record_on(today, slot_id: 1, duration: 60, percentage: 80)
      record_on(today, user: 'someone-else', slot_id: 2, duration: 600, percentage: 100)

      overview = described_class.overview(user_id, today: today)

      expect(overview[:summary][:totalRecordings]).to eq(1)
      expect(overview[:slotBreakdown].map { |slot| slot[:slotId] }).to eq([1])
    end

    it 'includes every day of the window, empty ones included' do
      record_on(today, slot_id: 0)

      overview = described_class.overview(user_id, today: today)

      expect(overview[:dailyActivity].length).to eq(described_class::RECENT_DAYS)
      expect(overview[:dailyActivity].last).to include(date: today.iso8601, count: 1)
      expect(overview[:dailyActivity].first).to include(count: 0)
    end

    it 'leaves out recordings older than the window, but still counts them in the totals' do
      record_on(today - 100, slot_id: 0)
      record_on(today, slot_id: 1)

      overview = described_class.overview(user_id, today: today)

      expect(overview[:summary][:totalRecordings]).to eq(2)
      expect(overview[:recentRecordings].length).to eq(1)
      expect(overview[:firstRecordedOn]).to eq(today - 100)
      expect(overview[:activeDays]).to eq(2)
    end

    it 'averages each slot\'s score' do
      record_on(today, slot_id: 2, percentage: 60)
      record_on(today - 1, slot_id: 2, percentage: 90)

      overview = described_class.overview(user_id, today: today)

      expect(overview[:slotBreakdown].first).to include(slotId: 2, count: 2, averagePercentage: 75)
    end
  end
end
