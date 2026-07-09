# frozen_string_literal: true

# Matches the recordings table already provisioned by db/init.sql (the
# Postgres bootstrap docker-compose applies on first container start).
# db/init.sql's update_updated_at_column() trigger and get_user_rank()/
# get_user_count() functions aren't reproduced here: Active Record already
# maintains updated_at itself, and RecordingAnalytics computes ranking in
# Ruby rather than calling those Postgres functions.
class CreateRecordings < ActiveRecord::Migration[8.0]
  def change
    create_table :recordings do |t|
      t.string :user_id, null: false
      t.string :model, null: false
      t.string :build, null: false
      t.string :version, null: false
      t.date :date, null: false
      t.integer :slot_id, null: false
      t.bigint :start_timestamp, null: false
      t.bigint :end_timestamp, null: false
      t.text :amplitudes_json, null: false
      t.decimal :longitude, precision: 10, scale: 7
      t.decimal :latitude, precision: 10, scale: 7
      t.integer :duration
      t.integer :percentage
      t.text :file_path

      t.timestamps
    end

    add_index :recordings, :user_id
    add_index :recordings, :date
    add_index :recordings, %i[user_id date]
    add_index :recordings, :start_timestamp, order: :desc
    add_index :recordings, :end_timestamp, order: :desc
    add_index :recordings, :slot_id
    add_index :recordings, :model
  end
end
