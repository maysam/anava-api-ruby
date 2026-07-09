# frozen_string_literal: true

# Server-rendered web dashboard — a native Rails/ERB port of the anava-web
# React reference app (recordings browser + analytics). Reads through the same
# Recording model and RecordingAnalytics service the JSON API uses.
#
# Inherits from ActionController::Base (not the API's ActionController::API) so
# it can render ERB views. It's GET-only and stateless, so forgery protection
# is skipped and no session/cookies are needed.
class DashboardController < ActionController::Base
  layout 'dashboard'
  skip_forgery_protection

  PER_PAGE_OPTIONS = [10, 25, 50, 100].freeze
  DEFAULT_PER_PAGE = 25
  RANGE_PRESETS = %w[all today yesterday this_week last_week this_month last_month].freeze

  def index
    @models = Recording.where.not(model: [nil, '']).distinct.order(:model).pluck(:model)
    @selected_model = params[:model].presence
    @selected_model = @models.first unless @models.include?(@selected_model)

    @tab = params[:tab] == 'analytics' ? 'analytics' : 'recordings'

    load_recordings if @selected_model
    @analytics = RecordingAnalytics.analytics_payload('model', @selected_model) if @selected_model
  end

  private

  def load_recordings
    @range = RANGE_PRESETS.include?(params[:range]) ? params[:range] : 'all'
    @per_page = PER_PAGE_OPTIONS.include?(params[:per_page].to_i) ? params[:per_page].to_i : DEFAULT_PER_PAGE
    @page = [params[:page].to_i, 1].max

    scope = Recording.where(model: @selected_model)
    date_range = date_range_for_preset(@range)
    scope = scope.where(date: date_range.first..date_range.last) if date_range

    @total = scope.count
    @total_pages = [(@total.to_f / @per_page).ceil, 1].max
    @page = [@page, @total_pages].min

    recordings = scope.order(end_timestamp: :desc)
                      .limit(@per_page)
                      .offset((@page - 1) * @per_page)
                      .to_a

    # Grouped by date (descending), each day's rows ordered by end_timestamp
    # ascending — matching the React RecordingsList component.
    @grouped_recordings = recordings
                          .group_by { |recording| recording.date.to_s }
                          .sort_by { |date, _| date }
                          .reverse
                          .to_h
    @grouped_recordings.each_value { |rows| rows.sort_by!(&:end_timestamp) }

    @recordings_for_json = recordings
  end

  # Ruby port of getDateRangeForPreset() in the React RecordingsList. Returns
  # a [start_date, end_date] pair of Dates, or nil for "all".
  def date_range_for_preset(preset)
    today = Date.current
    case preset
    when 'today'      then [today, today]
    when 'yesterday'  then [today - 1, today - 1]
    when 'this_week'  then [today.beginning_of_week, today]
    when 'last_week'  then [today.beginning_of_week - 7, today.beginning_of_week - 1]
    when 'this_month' then [today.beginning_of_month, today]
    when 'last_month'
      last_month = today.prev_month
      [last_month.beginning_of_month, last_month.end_of_month]
    end
  end
end
