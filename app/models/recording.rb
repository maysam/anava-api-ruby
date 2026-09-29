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

  # Columns an operator may change from the admin dashboard's edit form.
  # Timestamps and the amplitude payload are left alone: they are the raw
  # capture, not "details" an operator should be correcting by hand.
  ADMIN_EDITABLE_COLUMNS = %w[
    model build version user_id date slot_id duration percentage latitude longitude
  ].freeze

  # Only enforced for admin dashboard edits (`save(context: :admin_edit)`), so
  # the API's long-standing write behaviour is unchanged. Guards the NOT NULL
  # columns an operator could otherwise blank out.
  with_options on: :admin_edit do
    validates :model, :build, :version, :user_id, :date, :slot_id, presence: true
    validates :slot_id, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
    validates :duration, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
    validates :percentage, numericality: { only_integer: true }, allow_nil: true
    validates :latitude, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
    validates :longitude, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
  end

  # A negative activity percentage is a detection artefact, not a real score:
  # it is treated as zero everywhere it is shown or aggregated (averages,
  # sums, rankings, charts), so it can never drag a figure below zero. The
  # stored value is left untouched. NULL stays NULL so AVG() still skips it.
  CLAMPED_PERCENTAGE_SQL = Arel.sql('CASE WHEN percentage < 0 THEN 0 ELSE percentage END')

  def self.clamp_percentage(raw_percentage)
    return nil if raw_percentage.nil?

    [raw_percentage.to_i, 0].max
  end

  def activity_percentage
    self.class.clamp_percentage(percentage)
  end

  # Every JSON view of a recording (API responses, the admin modal) reports
  # the clamped percentage, matching the aggregates computed from it.
  def as_json(options = nil)
    serialized = super
    serialized['percentage'] = activity_percentage if serialized.key?('percentage')
    serialized
  end

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
