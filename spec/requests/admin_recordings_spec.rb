# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin recording edit/delete', type: :request do
  let!(:recording) do
    create(:recording, model: 'Pixel-7', build: '1.2.3.4', version: '1.0.0', slot_id: 1, percentage: 40, duration: 60)
  end

  describe 'GET /admin/recordings/:id/edit' do
    it 'renders the edit form prefilled with the recording' do
      get "/admin/recordings/#{recording.id}/edit", params: { return_to: '/admin?model=Pixel-7' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="recording[model]" value="Pixel-7"')
      expect(response.body).to include('value="/admin?model=Pixel-7"')
    end

    it 'returns 404 for an unknown recording' do
      get '/admin/recordings/999999/edit'

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /admin/recordings/:id (update)' do
    it 'updates editable details and redirects back with a notice' do
      post "/admin/recordings/#{recording.id}", params: {
        return_to: '/admin?model=Pixel-7&tab=recordings',
        recording: { model: 'Pixel-8', percentage: '75', slot_id: '3' }
      }

      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with('/admin?model=Pixel-7&tab=recordings&notice=recording_updated')
      recording.reload
      expect(recording.model).to eq('Pixel-8')
      expect(recording.percentage).to eq(75)
      expect(recording.slot_id).to eq(3)
    end

    it 'ignores columns that are not admin-editable' do
      original_start_timestamp = recording.start_timestamp

      post "/admin/recordings/#{recording.id}", params: { recording: { start_timestamp: 1 } }

      expect(recording.reload.start_timestamp).to eq(original_start_timestamp)
    end

    it 're-renders the form with errors when a required field is blanked' do
      post "/admin/recordings/#{recording.id}", params: { recording: { model: '' } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include('Model can&#39;t be blank')
      expect(recording.reload.model).to eq('Pixel-7')
    end

    it 'never redirects outside the admin area' do
      post "/admin/recordings/#{recording.id}", params: { return_to: 'https://evil.example', recording: { model: 'X' } }

      expect(response.location).to end_with('/admin?notice=recording_updated')
    end

    it 'also accepts PATCH' do
      patch "/admin/recordings/#{recording.id}", params: { recording: { version: '2.0.0' } }

      expect(recording.reload.version).to eq('2.0.0')
    end
  end

  describe 'deleting' do
    it 'deletes the recording via POST .../delete and redirects with a notice' do
      post "/admin/recordings/#{recording.id}/delete", params: { return_to: '/admin?model=Pixel-7' }

      expect(response).to have_http_status(:see_other)
      expect(response.location).to end_with('/admin?model=Pixel-7&notice=recording_deleted')
      expect(Recording.exists?(recording.id)).to be(false)
    end

    it 'deletes via DELETE and removes the stored audio file' do
      FileUtils.mkdir_p(AudioFileStorage::STORAGE_DIRECTORY)
      audio_path = AudioFileStorage::STORAGE_DIRECTORY.join('admin-delete-spec.wav').to_s
      File.write(audio_path, 'RIFF')
      recording.update!(file_path: audio_path)

      delete "/admin/recordings/#{recording.id}"

      expect(Recording.exists?(recording.id)).to be(false)
      expect(File.exist?(audio_path)).to be(false)
    end
  end

  it 'shows the notice banner on the dashboard' do
    get '/admin', params: { model: 'Pixel-7', notice: 'recording_deleted' }

    expect(response.body).to include('Recording deleted.')
  end

  it 'requires admin auth when a password is configured' do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('ANAVA_ADMIN_PASSWORD', nil).and_return('secret')

    post "/admin/recordings/#{recording.id}/delete"

    expect(response).to have_http_status(:unauthorized)
    expect(Recording.exists?(recording.id)).to be(true)
  end
end
