require "rails_helper"

RSpec.describe "Recording WAV uploads", type: :request do
  after { FileUtils.rm_rf(AudioFileStorage::STORAGE_DIRECTORY) }

  describe "POST /api/v1/recordings" do
    it "accepts a multipart request with a WAV file and stores its path" do
      attributes = attributes_for(:recording).except(:file_path)

      post "/api/v1/recordings", params: attributes.merge(file: fixture_file_upload("sample.wav", "audio/wav"))

      expect(response).to have_http_status(:ok)
      recording = Recording.last
      expect(recording.file_path).to be_present
      expect(File).to exist(recording.file_path)
    end

    it "rejects a file that isn't a valid WAV" do
      attributes = attributes_for(:recording).except(:file_path)

      post "/api/v1/recordings", params: attributes.merge(file: fixture_file_upload("not_a_wave.txt", "text/plain"))

      expect(response).to have_http_status(:bad_request)
      expect(Recording.count).to eq(0)
    end

    it "still accepts a plain JSON body with no file" do
      attributes = attributes_for(:recording)

      post "/api/v1/recordings", params: attributes.to_json, headers: { "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(Recording.last.file_path).to be_nil
    end
  end

  describe "PUT /api/v1/recordings/:id" do
    it "attaches a WAV file to an existing recording with no other fields given" do
      recording = create(:recording, file_path: nil)

      put "/api/v1/recordings/#{recording.id}", params: { file: fixture_file_upload("sample.wav", "audio/wav") }

      expect(response).to have_http_status(:ok)
      expect(recording.reload.file_path).to be_present
    end
  end
end
