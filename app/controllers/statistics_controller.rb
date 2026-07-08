class StatisticsController < ApplicationController
  def show
    analytics = RecordingAnalytics.calculate_analytics(params[:userId].to_s)
    render json: { success: true, data: analytics.merge(totalPlayersCount: Recording.total_players_count) }
  end
end
