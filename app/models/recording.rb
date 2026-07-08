class Recording < ActiveRecord::Base
  # Columns a client is allowed to write. Mirrors the Recording interface in
  # the original supabase/functions/anava/index.ts.
  WRITABLE_COLUMNS = %w[
    user_id model build version date slot_id amplitudes_json
    start_timestamp end_timestamp longitude latitude duration percentage file_path
  ].freeze

  def self.total_players_count
    distinct.count(:user_id)
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
