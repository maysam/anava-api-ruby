# frozen_string_literal: true

# View helpers shared by the admin dashboard (app/views/admin/) and the
# per-user panel (app/views/panel/) — slot naming plus the small
# duration/time/date formatters ported from the anava-web React components.
module RecordingPresentationHelper
  # Every tradition owns a fixed, non-overlapping slot_id range so the
  # per-slot ranking stays scoped within a tradition without a server-side
  # tradition column. Mirrors PrayerScheduleFactory in the Android app
  # (Islamic 0-4, Jewish 5-7, Christian 8-10, Custom 11-18).
  SLOT_NAMES_BY_ID = {
    0 => 'Fajr', 1 => 'Dhuhr', 2 => 'Asr', 3 => 'Maghrib', 4 => 'Isha',
    5 => 'Shacharit', 6 => 'Mincha', 7 => "Ma'ariv",
    8 => 'Morning Prayer', 9 => 'Midday Prayer', 10 => 'Evening Prayer'
  }.freeze

  # Custom slots are user-named on the device and that name is never sent to
  # the server, so they can only be shown positionally.
  CUSTOM_SLOT_ID_RANGE = (11..18)

  TRADITION_NAMES_BY_SLOT_RANGE = {
    (0..4) => 'Islamic',
    (5..7) => 'Jewish',
    (8..10) => 'Christian',
    CUSTOM_SLOT_ID_RANGE => 'Custom'
  }.freeze

  def slot_name(slot_id)
    slot_id = slot_id.to_i
    return SLOT_NAMES_BY_ID[slot_id] if SLOT_NAMES_BY_ID.key?(slot_id)
    return "Custom #{slot_id - CUSTOM_SLOT_ID_RANGE.first + 1}" if CUSTOM_SLOT_ID_RANGE.cover?(slot_id)

    "Slot #{slot_id}"
  end

  # The tradition a slot_id belongs to, or nil for an unrecognised id.
  def tradition_name(slot_id)
    slot_id = slot_id.to_i
    _range, name = TRADITION_NAMES_BY_SLOT_RANGE.find { |range, _| range.cover?(slot_id) }
    name
  end

  # "m:ss" — used in the recordings list (matches RecordingsList.formatDuration).
  def format_duration_short(seconds)
    seconds = seconds.to_i
    return '0:00' if seconds.zero?

    format('%<minutes>d:%<seconds>02d', minutes: seconds / 60, seconds: seconds % 60)
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
