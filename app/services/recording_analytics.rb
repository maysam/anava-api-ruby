# Analytics/reporting logic on top of the Recording model, ported from the
# Sinatra helpers. Pure Active Record — no raw SQL, no Postgres functions.
module RecordingAnalytics
  module_function

  def calculate_duration(start_timestamp, end_timestamp)
    ((end_timestamp.to_i - start_timestamp.to_i) / 1000.0).floor
  end

  # Ranks users by average `percentage` within a date range. Ties share a
  # rank and the next distinct value skips ahead (the same "competition
  # ranking" semantics as SQL's RANK() OVER (ORDER BY avg DESC)), computed
  # here in Ruby via Active Record's grouped average instead of the old
  # get_user_rank() Postgres function.
  def user_rank(start_date, end_date, target_user)
    averages_by_user = Recording.where(date: start_date..end_date)
                                 .group(:user_id)
                                 .average(:percentage)
                                 .sort_by { |_user_id, average| -average }

    rank = 0
    previous_average = nil
    averages_by_user.each_with_index do |(user_id, average), index|
      if average != previous_average
        rank = index + 1
        previous_average = average
      end
      return rank if user_id == target_user
    end

    0
  end

  # Mirrors calculateAnalytics() in index.ts.
  def calculate_analytics(user_id, recording_date = Date.today)
    scope = Recording.where(user_id: user_id)
    total_recordings = scope.count
    total_duration = scope.sum(:duration)
    total_percentage = scope.sum(:percentage)
    average_percentage = total_recordings.positive? ? (total_percentage.to_f / total_recordings).round : 0
    average_duration = total_recordings.positive? ? (total_duration.to_f / total_recordings).round : 0

    today_iso = recording_date.iso8601
    last_week_iso = (recording_date - 7).iso8601
    last_month_iso = (recording_date - 30).iso8601

    {
      totalRecordings: total_recordings,
      totalDuration: total_duration,
      averagePercentage: average_percentage,
      averageDuration: average_duration,
      rankingToday: user_rank(today_iso, today_iso, user_id),
      rankingLastWeek: user_rank(last_week_iso, today_iso, user_id),
      rankingLastMonth: user_rank(last_month_iso, today_iso, user_id),
      total: Recording.total_players_count
    }
  end

  def group_by_date(recordings)
    recordings.group_by { |recording| recording.date.to_s }
  end

  # Mirrors calculateStats() in index.ts.
  def calculate_stats(recordings)
    if recordings.nil? || recordings.empty?
      return {
        totalRecordings: 0,
        totalDuration: 0,
        averageDuration: 0,
        rankingToday: 0,
        rankingLastWeek: 0,
        rankingLastMonth: 0,
        recordingsByType: {},
        recordingsBySlot: {}
      }
    end

    total_duration = recordings.sum { |recording| recording.duration.to_i }
    recordings_by_slot = recordings.each_with_object(Hash.new(0)) do |recording, counts|
      counts[recording.slot_id.to_s] += 1
    end

    {
      totalRecordings: recordings.length,
      totalDuration: total_duration,
      averageDuration: total_duration / recordings.length,
      rankingToday: 0,
      rankingLastWeek: 0,
      rankingLastMonth: 0,
      recordingsByType: {},
      recordingsBySlot: recordings_by_slot
    }
  end

  # Shared body of /recordings/analytics/:userId and /recordings/analytics-by-model/:model.
  def analytics_payload(filter_column, filter_value)
    today = Date.today.iso8601
    seven_days_ago = (Date.today - 7).iso8601
    thirty_days_ago = (Date.today - 30).iso8601

    daily_recordings = Recording.where(filter_column => filter_value, date: today).to_a
    weekly_recordings = Recording.where(filter_column => filter_value, date: seven_days_ago..today).to_a
    monthly_recordings = Recording.where(filter_column => filter_value, date: thirty_days_ago..today).to_a

    weekly_by_date = group_by_date(weekly_recordings)
    daily_summary = weekly_by_date.keys.sort.map do |date|
      {
        date: date,
        count: weekly_by_date[date].length,
        totalDuration: weekly_by_date[date].sum { |recording| recording.duration.to_i }
      }
    end

    {
      daily: {
        date: today,
        stats: calculate_stats(daily_recordings),
        recordings: daily_recordings
      },
      weekly: {
        startDate: seven_days_ago,
        endDate: today,
        stats: calculate_stats(weekly_recordings),
        dailySummary: daily_summary,
        totalCount: weekly_recordings.length
      },
      monthly: {
        startDate: thirty_days_ago,
        endDate: today,
        stats: calculate_stats(monthly_recordings),
        totalCount: monthly_recordings.length
      }
    }
  end
end
