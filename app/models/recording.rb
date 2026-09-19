# frozen_string_literal: true

class Recording < ActiveRecord::Base
  # Columns a client is allowed to write. Mirrors the Recording interface in
  # the original supabase/functions/anava/index.ts.
  WRITABLE_COLUMNS = %w[
    user_id model build version date slot_id amplitudes_json
    start_timestamp end_timestamp longitude latitude duration percentage file_path
  ].freeze

  # Columns that together identify "the same recording" for idempotency
  # purposes: a device (user_id) reporting the same slot over the same time
  # window is treated as a resubmission, not a new recording.
  IDEMPOTENCY_KEY_COLUMNS = %w[user_id slot_id start_timestamp end_timestamp].freeze

  def self.total_players_count
    distinct.count(:user_id)
  end

  # Creates a recording, or updates the existing one with the same
  # identifying key, so retried/duplicate POSTs don't create duplicate rows.
  def self.create_or_update_idempotently(recording_attributes)
    idempotency_key = recording_attributes.slice(*IDEMPOTENCY_KEY_COLUMNS)
    recording = find_or_initialize_by(idempotency_key)
    recording.assign_attributes(recording_attributes)
    recording.save!
    recording
  end

  # Applies the shared date / date-range filters used by the listing endpoints.
  def self.filter_by_params(scope, request_params)
    scope = scope.where(date: request_params[:date]) if request_params[:date]

    if request_params[:startDate] && request_params[:endDate]
      scope = scope.where(date: request_params[:startDate]..request_params[:endDate])
    end

    scope
  end
end
