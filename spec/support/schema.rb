# Test-only schema setup. Mirrors the `recordings` table from db/init.sql
# (the source of truth for development/production) in Active Record's
# portable schema DSL so it can run against the SQLite test database.
# db/init.sql's trigger and get_user_rank()/get_user_count() functions are
# intentionally not reproduced here — they're Postgres-only, and the app no
# longer calls them (RecordingAnalytics computes ranking in Ruby instead).
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :recordings, force: :cascade do |t|
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
  add_index :recordings, [:user_id, :date]
  add_index :recordings, :start_timestamp, order: :desc
  add_index :recordings, :end_timestamp, order: :desc
  add_index :recordings, :slot_id
  add_index :recordings, :model
end
