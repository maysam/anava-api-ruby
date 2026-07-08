class DeviceModelsController < ApplicationController
  def index
    models = Recording.where.not(model: [nil, ""]).distinct.order(:model).pluck(:model)
    render json: { success: true, models: models }
  end
end
