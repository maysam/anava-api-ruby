# frozen_string_literal: true

class RecordingsController < ApplicationController
  # GET /recordings
  def index
    scope = Recording.filter_by_params(Recording.all, params)
    scope = scope.where(user_id: params[:userId]) if params[:userId]
    limit, offset = pagination_params

    total = scope.count
    recordings = scope.order(end_timestamp: :asc).limit(limit).offset(offset)
    render json: { success: true, data: recordings, pagination: { total: total, limit: limit, offset: offset } }
  end

  # GET /recordings/:id
  def show
    recording = Recording.find_by(id: params[:id])
    if recording
      render json: { success: true, data: recording }
    else
      render json: { success: false, error: 'Recording not found' }, status: :not_found
    end
  end

  # POST /recordings
  # Accepts either a JSON body, or multipart/form-data with the same fields
  # plus a "file" part holding the recording's WAV audio.
  def create
    attributes = recording_attributes
    attributes['model'] = request.headers['X-Device-Model'] || 'no model'
    attributes['build'] = request.headers['X-Forwarded-For'] || 'no ip'
    attributes['version'] = request.headers['X-App-Version'] || 'no version'
    attributes['duration'] ||= RecordingAnalytics.calculate_duration(
      attributes['start_timestamp'], attributes['end_timestamp']
    )
    attributes['file_path'] = AudioFileStorage.save(params[:file]) if params[:file].present?

    recording = Recording.create!(attributes)
    recording_date = begin
      Date.parse(attributes['date'].to_s)
    rescue ArgumentError, TypeError
      Date.today
    end
    render json: { success: true, data: RecordingAnalytics.calculate_analytics(recording.user_id, recording_date) }
  end

  # PUT /recordings/:id
  # Accepts either a JSON body, or multipart/form-data (e.g. to attach/replace
  # the WAV audio file on its own, with no other fields).
  def update
    updates = recording_attributes
    updates['file_path'] = AudioFileStorage.save(params[:file]) if params[:file].present?
    if updates['start_timestamp'] && updates['end_timestamp']
      updates['duration'] = RecordingAnalytics.calculate_duration(updates['start_timestamp'], updates['end_timestamp'])
    end

    if updates.empty?
      render json: { success: false, error: 'No valid fields to update' }, status: :bad_request
      return
    end

    recording = Recording.find_by(id: params[:id])
    if recording
      recording.update!(updates)
      render json: { success: true, data: recording }
    else
      render json: { success: false, error: 'Recording not found' }, status: :not_found
    end
  end

  # DELETE /recordings/:id
  def destroy
    Recording.where(id: params[:id]).delete_all
    render json: { success: true, message: 'Recording deleted successfully' }
  end

  # GET /recordings/user/:user_id
  def by_user
    scope = Recording.filter_by_params(Recording.where(user_id: params[:user_id]), params)
    limit, offset = pagination_params

    total = scope.count
    recordings = scope.order(end_timestamp: :desc).limit(limit).offset(offset).to_a
    render json: {
      success: true,
      data: recordings,
      groupedByDate: RecordingAnalytics.group_by_date(recordings),
      pagination: { total: total, limit: limit, offset: offset }
    }
  end

  # GET /recordings/analytics/:user_id
  def analytics_by_user
    render json: { success: true, analytics: RecordingAnalytics.analytics_payload('user_id', params[:user_id]) }
  end

  # GET /recordings/model/:model
  def by_model
    scope = Recording.filter_by_params(Recording.where(model: params[:model]), params)
    limit, offset = pagination_params

    total = scope.count
    recordings = scope.order(end_timestamp: :desc).limit(limit).offset(offset).to_a
    render json: {
      success: true,
      data: recordings,
      groupedByDate: RecordingAnalytics.group_by_date(recordings),
      pagination: { total: total, limit: limit, offset: offset }
    }
  end

  # GET /recordings/analytics-by-model/:model
  def analytics_by_model
    render json: { success: true, analytics: RecordingAnalytics.analytics_payload('model', params[:model]) }
  end

  private

  # multipart/form-data bodies (used when uploading a "file") arrive through
  # Rails' params, not the raw request body JSON parses elsewhere in this
  # controller.
  def recording_attributes
    if request.content_type.to_s.include?('multipart/form-data')
      params.permit(*Recording::WRITABLE_COLUMNS).to_h
    else
      parsed_json_body.slice(*Recording::WRITABLE_COLUMNS)
    end
  end

  def pagination_params
    limit = (params[:limit] || 100).to_i
    offset = (params[:offset] || 0).to_i
    [limit, offset]
  end
end
