# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_09_152751) do
  create_table "recordings", force: :cascade do |t|
    t.text "amplitudes_json", null: false
    t.string "build", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.integer "duration"
    t.bigint "end_timestamp", null: false
    t.text "file_path"
    t.decimal "latitude", precision: 10, scale: 7
    t.decimal "longitude", precision: 10, scale: 7
    t.string "model", null: false
    t.integer "percentage"
    t.integer "slot_id", null: false
    t.bigint "start_timestamp", null: false
    t.datetime "updated_at", null: false
    t.string "user_id", null: false
    t.string "version", null: false
    t.index ["date"], name: "index_recordings_on_date"
    t.index ["end_timestamp"], name: "index_recordings_on_end_timestamp", order: :desc
    t.index ["model"], name: "index_recordings_on_model"
    t.index ["slot_id"], name: "index_recordings_on_slot_id"
    t.index ["start_timestamp"], name: "index_recordings_on_start_timestamp", order: :desc
    t.index ["user_id", "date"], name: "index_recordings_on_user_id_and_date"
    t.index ["user_id"], name: "index_recordings_on_user_id"
  end
end
