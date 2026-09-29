# frozen_string_literal: true

module Admin
  # Operator edits and deletions of single recordings, reached from the
  # recording detail modal on the admin dashboard. Plain HTML forms that POST
  # (the app is api_only, so there is no Rack::MethodOverride for PATCH/DELETE
  # from a browser form); PATCH and DELETE are routed too for scripted use.
  #
  # After a change the operator is sent back to the dashboard view they came
  # from (`return_to`), with a `notice` query param the dashboard turns into a
  # banner — there is no flash, since the admin area keeps no session.
  class RecordingsController < BaseController
    NOTICE_MESSAGES = {
      'recording_updated' => 'Recording updated.',
      'recording_deleted' => 'Recording deleted.'
    }.freeze

    before_action :load_recording

    def edit
      @return_to = safe_return_to
    end

    def update
      @return_to = safe_return_to
      @recording.assign_attributes(editable_attributes)
      if @recording.save(context: :admin_edit)
        redirect_to with_notice(@return_to, 'recording_updated'), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    def destroy
      stored_audio_path = @recording.file_path
      @recording.destroy!
      AudioFileStorage.delete(stored_audio_path)
      redirect_to with_notice(safe_return_to, 'recording_deleted'), status: :see_other
    end

    private

    def load_recording
      @recording = Recording.find_by(id: params[:id])
      return if @recording

      render plain: 'Recording not found', status: :not_found
    end

    # Blank form fields clear nullable columns rather than storing "".
    def editable_attributes
      submitted_attributes = params.fetch(:recording, {}).permit(*Recording::ADMIN_EDITABLE_COLUMNS).to_h
      submitted_attributes.transform_values(&:presence)
    end

    # Only ever redirect within the admin area, so `return_to` can't be used
    # as an open redirect.
    def safe_return_to
      requested_path = params[:return_to].to_s
      requested_path.start_with?('/admin') && !requested_path.start_with?('//') ? requested_path : admin_dashboard_path
    end

    def with_notice(path, notice_key)
      uri = URI.parse(path)
      # decode_www_form returns [key, value] pairs (an Array), so convert to a
      # Hash before dropping any stale notice — Array has no #except.
      # The dashboard's query params are all single-valued, so to_h loses nothing.
      query_params = URI.decode_www_form(uri.query.to_s).to_h.except('notice')
      uri.query = URI.encode_www_form(query_params.merge('notice' => notice_key))
      uri.to_s
    end
  end
end
