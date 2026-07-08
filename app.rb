# Ruby/Sinatra clone of the Anava Supabase edge function (supabase/functions/anava/index.ts).
# Talks directly to Postgres instead of the Supabase client.
require "sinatra"
require "sinatra/json"
require "json"
require "pg"
require "connection_pool"
require "date"

set :bind, "0.0.0.0"
set :port, ENV.fetch("PORT", 8085).to_i
set :show_exceptions, false

DATABASE_URL = ENV.fetch("DATABASE_URL", "postgres://anava:anava@localhost:5432/anava")

DB_POOL = ConnectionPool.new(size: ENV.fetch("DB_POOL_SIZE", 5).to_i, timeout: 5) do
  connection = PG.connect(DATABASE_URL)
  connection.type_map_for_results = PG::BasicTypeMapForResults.new(connection)
  connection
end

def with_db(&block)
  DB_POOL.with(&block)
end

# Columns a client is allowed to write. Mirrors the Recording interface in index.ts.
WRITABLE_RECORDING_COLUMNS = %w[
  user_id model build version date slot_id amplitudes_json
  start_timestamp end_timestamp longitude latitude duration percentage file_path
].freeze

before do
  headers "Access-Control-Allow-Origin" => "*",
          "Access-Control-Allow-Methods" => "GET, POST, PUT, DELETE, OPTIONS",
          "Access-Control-Allow-Headers" => "Content-Type, Authorization, X-Device-Model, X-App-Version"
end

options "*" do
  200
end

helpers do
  def json_body
    request.body.rewind
    JSON.parse(request.body.read)
  rescue JSON::ParserError
    halt 400, json(success: false, error: "Invalid JSON body")
  end

  def error_response(error, status_code = 500)
    logger.error("#{request.request_method} #{request.path}: #{error.message}")
    status status_code
    json(success: false, error: error.message)
  end

  def calculate_duration(start_timestamp, end_timestamp)
    ((end_timestamp.to_i - start_timestamp.to_i) / 1000.0).floor
  end

  def total_players_count(db)
    result = db.exec("SELECT count(DISTINCT user_id) AS user_count FROM recordings")
    result[0]["user_count"].to_i
  end

  def user_rank(db, start_date, end_date, target_user)
    result = db.exec_params(
      "SELECT rank FROM get_user_rank($1::date, $2::date, $3::text)",
      [start_date, end_date, target_user]
    )
    result.ntuples.positive? ? result[0]["rank"].to_i : 0
  end

  # Mirrors calculateAnalytics() in index.ts.
  def calculate_analytics(db, user_id, recording_date = Date.today)
    duration_rows = db.exec_params(
      "SELECT duration, percentage FROM recordings WHERE user_id = $1",
      [user_id]
    ).to_a

    total_recordings = duration_rows.length
    total_duration = duration_rows.sum { |row| row["duration"].to_i }
    total_percentage = duration_rows.sum { |row| row["percentage"].to_i }
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
      rankingToday: user_rank(db, today_iso, today_iso, user_id),
      rankingLastWeek: user_rank(db, last_week_iso, today_iso, user_id),
      rankingLastMonth: user_rank(db, last_month_iso, today_iso, user_id),
      total: total_players_count(db)
    }
  end

  # Builds WHERE clause fragments for the shared date/user/model filters.
  def build_recordings_query(base_conditions, base_values)
    conditions = base_conditions.dup
    values = base_values.dup

    if params[:date]
      values << params[:date]
      conditions << "date = $#{values.length}"
    end

    if params[:startDate] && params[:endDate]
      values << params[:startDate]
      conditions << "date >= $#{values.length}"
      values << params[:endDate]
      conditions << "date <= $#{values.length}"
    end

    [conditions, values]
  end

  def pagination_params
    limit = (params[:limit] || 100).to_i
    offset = (params[:offset] || 0).to_i
    [limit, offset]
  end

  def group_by_date(recordings)
    recordings.group_by { |recording| recording["date"].to_s }
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

    total_duration = recordings.sum { |recording| recording["duration"].to_i }
    recordings_by_slot = recordings.each_with_object(Hash.new(0)) do |recording, counts|
      counts[recording["slot_id"].to_s] += 1
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
  def analytics_payload(db, filter_column, filter_value)
    today = Date.today.iso8601
    seven_days_ago = (Date.today - 7).iso8601
    thirty_days_ago = (Date.today - 30).iso8601

    daily_recordings = db.exec_params(
      "SELECT * FROM recordings WHERE #{filter_column} = $1 AND date = $2",
      [filter_value, today]
    ).to_a
    weekly_recordings = db.exec_params(
      "SELECT * FROM recordings WHERE #{filter_column} = $1 AND date >= $2 AND date <= $3",
      [filter_value, seven_days_ago, today]
    ).to_a
    monthly_recordings = db.exec_params(
      "SELECT * FROM recordings WHERE #{filter_column} = $1 AND date >= $2 AND date <= $3",
      [filter_value, thirty_days_ago, today]
    ).to_a

    weekly_by_date = group_by_date(weekly_recordings)
    daily_summary = weekly_by_date.keys.sort.map do |date|
      {
        date: date,
        count: weekly_by_date[date].length,
        totalDuration: weekly_by_date[date].sum { |recording| recording["duration"].to_i }
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

# Health check endpoint
get "/anava/health" do
  json(success: true, message: "API is running", timestamp: Time.now.utc.iso8601)
end

get "/anava/statistics" do
  with_db do |db|
    analytics = calculate_analytics(db, params[:userId].to_s)
    players_count = total_players_count(db)
    json(success: true, data: analytics.merge(totalPlayersCount: players_count))
  end
rescue StandardError => error
  error_response(error)
end

# Create new recording
post "/anava/recordings" do
  recording = json_body.slice(*WRITABLE_RECORDING_COLUMNS)
  recording["model"] = request.env["HTTP_X_DEVICE_MODEL"] || "no model"
  recording["build"] = request.env["HTTP_X_FORWARDED_FOR"] || "no ip"
  recording["version"] = request.env["HTTP_X_APP_VERSION"] || "no version"
  if recording["duration"].nil?
    recording["duration"] = calculate_duration(recording["start_timestamp"], recording["end_timestamp"])
  end

  columns = recording.keys
  placeholders = columns.each_index.map { |index| "$#{index + 1}" }
  with_db do |db|
    db.exec_params(
      "INSERT INTO recordings (#{columns.join(', ')}) VALUES (#{placeholders.join(', ')})",
      recording.values
    )
    recording_date = Date.parse(recording["date"].to_s) rescue Date.today
    json(success: true, data: calculate_analytics(db, recording["user_id"], recording_date))
  end
rescue StandardError => error
  error_response(error)
end

# Get all recordings with optional filters
get "/anava/recordings" do
  conditions, values = build_recordings_query([], [])
  if params[:userId]
    values << params[:userId]
    conditions << "user_id = $#{values.length}"
  end
  limit, offset = pagination_params
  where_clause = conditions.empty? ? "" : "WHERE #{conditions.join(' AND ')}"

  with_db do |db|
    recordings = db.exec_params(
      "SELECT * FROM recordings #{where_clause} ORDER BY end_timestamp ASC LIMIT #{limit} OFFSET #{offset}",
      values
    ).to_a
    total = db.exec_params("SELECT count(*) AS total FROM recordings #{where_clause}", values)[0]["total"].to_i
    json(success: true, data: recordings, pagination: { total: total, limit: limit, offset: offset })
  end
rescue StandardError => error
  error_response(error)
end

# Get recordings by user (must be defined before /anava/recordings/:id)
get "/anava/recordings/user/:userId" do
  conditions, values = build_recordings_query(["user_id = $1"], [params[:userId]])
  limit, offset = pagination_params
  where_clause = "WHERE #{conditions.join(' AND ')}"

  with_db do |db|
    recordings = db.exec_params(
      "SELECT * FROM recordings #{where_clause} ORDER BY end_timestamp DESC LIMIT #{limit} OFFSET #{offset}",
      values
    ).to_a
    total = db.exec_params("SELECT count(*) AS total FROM recordings #{where_clause}", values)[0]["total"].to_i
    json(
      success: true,
      data: recordings,
      groupedByDate: group_by_date(recordings),
      pagination: { total: total, limit: limit, offset: offset }
    )
  end
rescue StandardError => error
  error_response(error)
end

# Get analytics for a user
get "/anava/recordings/analytics/:userId" do
  with_db do |db|
    json(success: true, analytics: analytics_payload(db, "user_id", params[:userId]))
  end
rescue StandardError => error
  error_response(error)
end

# Get recordings by device model
get "/anava/recordings/model/:model" do
  conditions, values = build_recordings_query(["model = $1"], [params[:model]])
  limit, offset = pagination_params
  where_clause = "WHERE #{conditions.join(' AND ')}"

  with_db do |db|
    recordings = db.exec_params(
      "SELECT * FROM recordings #{where_clause} ORDER BY end_timestamp DESC LIMIT #{limit} OFFSET #{offset}",
      values
    ).to_a
    total = db.exec_params("SELECT count(*) AS total FROM recordings #{where_clause}", values)[0]["total"].to_i
    json(
      success: true,
      data: recordings,
      groupedByDate: group_by_date(recordings),
      pagination: { total: total, limit: limit, offset: offset }
    )
  end
rescue StandardError => error
  error_response(error)
end

# Get analytics for a device model
get "/anava/recordings/analytics-by-model/:model" do
  with_db do |db|
    json(success: true, analytics: analytics_payload(db, "model", params[:model]))
  end
rescue StandardError => error
  error_response(error)
end

# List distinct device models
get "/anava/models" do
  with_db do |db|
    models = db.exec("SELECT DISTINCT model FROM recordings WHERE model IS NOT NULL AND model <> '' ORDER BY model")
                .map { |row| row["model"] }
    json(success: true, models: models)
  end
rescue StandardError => error
  error_response(error)
end

# Get single recording by ID
get "/anava/recordings/:id" do
  with_db do |db|
    result = db.exec_params("SELECT * FROM recordings WHERE id = $1", [params[:id].to_i])
    halt 404, json(success: false, error: "Recording not found") if result.ntuples.zero?
    json(success: true, data: result[0])
  end
rescue StandardError => error
  error_response(error)
end

# Update recording
put "/anava/recordings/:id" do
  updates = json_body.slice(*WRITABLE_RECORDING_COLUMNS)
  if updates["start_timestamp"] && updates["end_timestamp"]
    updates["duration"] = calculate_duration(updates["start_timestamp"], updates["end_timestamp"])
  end
  halt 400, json(success: false, error: "No valid fields to update") if updates.empty?

  assignments = updates.keys.each_with_index.map { |column, index| "#{column} = $#{index + 1}" }
  with_db do |db|
    result = db.exec_params(
      "UPDATE recordings SET #{assignments.join(', ')} WHERE id = $#{updates.length + 1} RETURNING *",
      updates.values + [params[:id].to_i]
    )
    halt 404, json(success: false, error: "Recording not found") if result.ntuples.zero?
    json(success: true, data: result[0])
  end
rescue StandardError => error
  error_response(error)
end

# Delete recording
delete "/anava/recordings/:id" do
  with_db do |db|
    db.exec_params("DELETE FROM recordings WHERE id = $1", [params[:id].to_i])
    json(success: true, message: "Recording deleted successfully")
  end
rescue StandardError => error
  error_response(error)
end

not_found do
  json(success: false, error: "Not found")
end

error do
  error_response(env["sinatra.error"] || StandardError.new("Internal server error"))
end
