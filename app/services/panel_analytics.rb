# frozen_string_literal: true

# Everything the personal panel (PanelController) shows about one device's own
# recordings. Reads through the same Recording model the JSON API uses, and
# reuses RecordingAnalytics for the figures the mobile app already displays, so
# the panel and the in-app statistics screen never disagree.
module PanelAnalytics
  module_function

  RECENT_DAYS = 30
  RECENT_RECORDINGS_LIMIT = 50

  def overview(user_id, today: Date.current)
    scope = Recording.where(user_id: user_id)
    recent_recordings = scope.where(date: (today - (RECENT_DAYS - 1))..today)
                             .order(end_timestamp: :desc).to_a
    active_dates = scope.distinct.pluck(:date).map(&:to_date).sort

    {
      summary: RecordingAnalytics.calculate_analytics(user_id, today),
      dailyActivity: daily_activity(recent_recordings, today),
      slotBreakdown: slot_breakdown(recent_recordings),
      recentRecordings: recent_recordings.first(RECENT_RECORDINGS_LIMIT)
    }.merge(history(active_dates, today))
  end

  # The "how long have you been at this" figures, all derived from the set of
  # days with at least one recording rather than from the recordings themselves.
  def history(active_dates, today)
    {
      firstRecordedOn: active_dates.first,
      lastRecordedOn: active_dates.last,
      currentStreak: current_streak(active_dates, today),
      longestStreak: longest_streak(active_dates),
      activeDays: active_dates.length
    }
  end

  # Consecutive days with at least one recording, counting back from today. A
  # day recorded yesterday but not yet today still counts as a live streak —
  # the day isn't over, and breaking it at midnight would be discouraging.
  def current_streak(active_dates, today = Date.current)
    return 0 if active_dates.empty?

    active_days = active_dates.to_set
    cursor = active_days.include?(today) ? today : today - 1
    return 0 unless active_days.include?(cursor)

    streak = 0
    while active_days.include?(cursor)
      streak += 1
      cursor -= 1
    end
    streak
  end

  def longest_streak(active_dates)
    longest = 0
    running = 0
    previous_date = nil

    active_dates.each do |date|
      running = previous_date && date == previous_date + 1 ? running + 1 : 1
      longest = running if running > longest
      previous_date = date
    end

    longest
  end

  # One entry per day of the trailing RECENT_DAYS window, including the days
  # with nothing recorded — an activity chart with the gaps left out would
  # quietly redraw a patchy month as a solid one.
  def daily_activity(recordings, today = Date.current)
    counts_by_date = recordings.group_by { |recording| recording.date.to_date }

    ((today - (RECENT_DAYS - 1))..today).map do |date|
      day_recordings = counts_by_date[date] || []
      {
        date: date.iso8601,
        count: day_recordings.length,
        totalDuration: day_recordings.sum { |recording| recording.duration.to_i },
        averagePercentage: average_percentage(day_recordings)
      }
    end
  end

  def slot_breakdown(recordings)
    recordings.group_by(&:slot_id).sort_by { |slot_id, _| slot_id.to_i }.map do |slot_id, slot_recordings|
      {
        slotId: slot_id.to_i,
        count: slot_recordings.length,
        averagePercentage: average_percentage(slot_recordings),
        totalDuration: slot_recordings.sum { |recording| recording.duration.to_i }
      }
    end
  end

  def average_percentage(recordings)
    return 0 if recordings.empty?

    (recordings.sum { |recording| recording.percentage.to_i }.to_f / recordings.length).round
  end
end
