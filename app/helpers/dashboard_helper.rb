# frozen_string_literal: true

# View helpers for the dashboard — Ruby ports of the small formatting helpers
# in the anava-web React components (slot names, duration/time/date formatting).
module DashboardHelper
  SLOTS = %w[Fajr Dhuhr Asr Maghrib Isha].freeze

  def slot_name(slot_id)
    SLOTS[slot_id] || "Slot #{slot_id}"
  end

  # "m:ss" — used in the recordings list (matches RecordingsList.formatDuration).
  def format_duration_short(seconds)
    seconds = seconds.to_i
    return '0:00' if seconds.zero?

    format('%d:%02d', seconds / 60, seconds % 60)
  end

  # "Xh Ym" / "Ym Ys" — used in analytics (matches AnalyticsDashboard.formatDuration).
  def format_duration_long(seconds)
    seconds = seconds.to_i
    hours = seconds / 3600
    minutes = (seconds % 3600) / 60
    secs = seconds % 60
    hours.positive? ? "#{hours}h #{minutes}m" : "#{minutes}m #{secs}s"
  end

  # Epoch-millisecond timestamp -> "HH:MM:SS" in the server's local time.
  def format_time(millis)
    Time.at(millis.to_i / 1000).strftime('%H:%M:%S')
  end

  # "Monday, January 5, 2026" — the day-group header in the recordings list.
  def format_day_header(date_string)
    Date.parse(date_string.to_s).strftime('%A, %B %-d, %Y')
  rescue ArgumentError, TypeError
    date_string.to_s
  end

  # Serialize a Ruby object to JSON for embedding inside a
  # <script type="application/json"> tag. Rails' json_escape turns `<`, `>`,
  # `&` and the U+2028/U+2029 separators into their JSON unicode escapes, so
  # attacker-controlled string values (e.g. a recording's user_id) can't break
  # out of the script tag. Marked html_safe since it's now fully escaped.
  def embed_json(object)
    raw(json_escape(object.to_json))
  end
end
