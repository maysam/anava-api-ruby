require "rails_helper"

RSpec.describe AudioFileStorage do
  after { FileUtils.rm_rf(AudioFileStorage::STORAGE_DIRECTORY) }

  describe ".save" do
    it "copies a valid WAV upload into storage and returns its path" do
      uploaded_file = fixture_file_upload("sample.wav", "audio/wav")

      path = described_class.save(uploaded_file)

      expect(File).to exist(path)
      expect(path).to start_with(AudioFileStorage::STORAGE_DIRECTORY.to_s)
      expect(File.binread(path)).to eq(File.binread(Rails.root.join("spec/fixtures/files/sample.wav")))
    end

    it "raises for a file that isn't a valid WAV" do
      uploaded_file = fixture_file_upload("not_a_wave.txt", "text/plain")

      expect { described_class.save(uploaded_file) }.to raise_error(AudioFileStorage::InvalidWaveFileError)
    end
  end
end
