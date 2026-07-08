class HealthController < ApplicationController
  def show
    render json: { success: true, message: "API is running", timestamp: Time.now.utc.iso8601 }
  end
end
