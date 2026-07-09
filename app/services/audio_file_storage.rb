# Saves an uploaded WAV file to local disk and returns the path to store in
# Recording#file_path. Deliberately not Active Storage: this is a light,
# API-only app (no Action View/asset pipeline), and a plain uploaded-file
# save is all a single local .wav blob needs.
module AudioFileStorage
  class InvalidWaveFileError < StandardError; end

  STORAGE_DIRECTORY = Rails.root.join("storage", "recordings")
  RIFF_CHUNK_ID = "RIFF"
  WAVE_FORMAT_ID = "WAVE"

  module_function

  def save(uploaded_file)
    validate_wave_file!(uploaded_file)

    FileUtils.mkdir_p(STORAGE_DIRECTORY)
    destination_path = STORAGE_DIRECTORY.join("#{SecureRandom.uuid}.wav")
    FileUtils.cp(uploaded_file.tempfile.path, destination_path)

    destination_path.to_s
  end

  # A WAV file is a RIFF container: 4 bytes "RIFF", 4 bytes chunk size, then
  # 4 bytes "WAVE". Checking these magic bytes is far more reliable than
  # trusting the client-supplied Content-Type or filename extension.
  def validate_wave_file!(uploaded_file)
    header = uploaded_file.read(12)
    uploaded_file.rewind

    return if header && header.byteslice(0, 4) == RIFF_CHUNK_ID && header.byteslice(8, 4) == WAVE_FORMAT_ID

    raise InvalidWaveFileError, "Uploaded file is not a valid WAV file"
  end
end
