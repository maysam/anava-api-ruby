require "rails_helper"

RSpec.describe RecordingAnalytics do
  describe ".calculate_duration" do
    it "converts a millisecond timestamp span into whole seconds" do
      expect(described_class.calculate_duration(1_000, 5_500)).to eq(4)
    end
  end

  describe ".user_rank" do
    it "gives tied users the same rank and skips the next rank accordingly" do
      today = Date.today
      create(:recording, user_id: "alice", date: today, percentage: 80)
      create(:recording, user_id: "bob", date: today, percentage: 80)
      create(:recording, user_id: "carol", date: today, percentage: 50)

      today_iso = today.iso8601
      expect(described_class.user_rank(today_iso, today_iso, "alice")).to eq(1)
      expect(described_class.user_rank(today_iso, today_iso, "bob")).to eq(1)
      expect(described_class.user_rank(today_iso, today_iso, "carol")).to eq(3)
    end

    it "returns 0 for a user with no recordings in range" do
      today_iso = Date.today.iso8601
      expect(described_class.user_rank(today_iso, today_iso, "nobody")).to eq(0)
    end
  end

  describe ".calculate_stats" do
    it "returns zeroed-out stats for an empty collection" do
      stats = described_class.calculate_stats([])

      expect(stats).to include(totalRecordings: 0, totalDuration: 0, recordingsBySlot: {})
    end

    it "aggregates duration and groups by slot" do
      recordings = [
        create(:recording, duration: 10, slot_id: 1),
        create(:recording, duration: 20, slot_id: 1),
        create(:recording, duration: 30, slot_id: 2)
      ]

      stats = described_class.calculate_stats(recordings)

      expect(stats[:totalRecordings]).to eq(3)
      expect(stats[:totalDuration]).to eq(60)
      expect(stats[:averageDuration]).to eq(20)
      expect(stats[:recordingsBySlot]).to eq("1" => 2, "2" => 1)
    end
  end

  describe ".group_by_date" do
    it "groups recordings by their date as a string key" do
      same_day = Date.new(2026, 1, 1)
      a = create(:recording, date: same_day)
      b = create(:recording, date: same_day)
      c = create(:recording, date: Date.new(2026, 1, 2))

      grouped = described_class.group_by_date([a, b, c])

      expect(grouped["2026-01-01"]).to contain_exactly(a, b)
      expect(grouped["2026-01-02"]).to contain_exactly(c)
    end
  end

  describe ".calculate_analytics" do
    it "summarizes a user's recordings and includes their rank" do
      today = Date.today
      create(:recording, user_id: "alice", date: today, duration: 10, percentage: 100)
      create(:recording, user_id: "alice", date: today, duration: 20, percentage: 50)
      create(:recording, user_id: "bob", date: today, percentage: 10)

      analytics = described_class.calculate_analytics("alice", today)

      expect(analytics[:totalRecordings]).to eq(2)
      expect(analytics[:totalDuration]).to eq(30)
      expect(analytics[:averagePercentage]).to eq(75)
      expect(analytics[:averageDuration]).to eq(15)
      expect(analytics[:rankingToday]).to eq(1)
      expect(analytics[:total]).to eq(2)
    end
  end

  describe ".analytics_payload" do
    it "buckets a filtered set of recordings into daily/weekly/monthly stats" do
      today = Date.today
      create(:recording, model: "Pixel-7", date: today, duration: 10)
      create(:recording, model: "Pixel-7", date: today - 3, duration: 20)
      create(:recording, model: "Pixel-7", date: today - 20, duration: 30)
      create(:recording, model: "other-model", date: today, duration: 999)

      payload = described_class.analytics_payload("model", "Pixel-7")

      expect(payload[:daily][:stats][:totalRecordings]).to eq(1)
      expect(payload[:weekly][:stats][:totalRecordings]).to eq(2)
      expect(payload[:weekly][:dailySummary].sum { |day| day[:count] }).to eq(2)
      expect(payload[:monthly][:stats][:totalRecordings]).to eq(3)
    end
  end
end
