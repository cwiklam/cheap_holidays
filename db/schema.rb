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

ActiveRecord::Schema[8.0].define(version: 2025_09_07_164656) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "countries", force: :cascade do |t|
    t.string "name", null: false
    t.string "normalized_name", null: false
    t.string "iso_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["normalized_name"], name: "index_countries_on_normalized_name", unique: true
  end

  create_table "hotels", force: :cascade do |t|
    t.string "name", null: false
    t.string "url"
    t.string "image_url"
    t.bigint "country_id"
    t.bigint "travel_agency_id"
    t.datetime "source_fetched_at"
    t.jsonb "raw_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["country_id"], name: "index_hotels_on_country_id"
    t.index ["name"], name: "index_hotels_on_name"
    t.index ["travel_agency_id", "name"], name: "index_hotels_on_travel_agency_id_and_name"
    t.index ["travel_agency_id", "url"], name: "index_hotels_on_travel_agency_id_and_url"
    t.index ["travel_agency_id"], name: "index_hotels_on_travel_agency_id"
    t.index ["url"], name: "index_hotels_on_url"
  end

  create_table "offers", force: :cascade do |t|
    t.bigint "hotel_id", null: false
    t.bigint "travel_agency_id", null: false
    t.string "name", null: false
    t.string "url"
    t.decimal "price", precision: 12, scale: 2
    t.string "price_raw"
    t.string "starts_on"
    t.datetime "source_fetched_at"
    t.jsonb "raw_data", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id", "url", "starts_on", "price", "source_fetched_at"], name: "index_offers_on_hotel_url_starts"
    t.index ["hotel_id"], name: "index_offers_on_hotel_id"
    t.index ["price"], name: "index_offers_on_price"
    t.index ["starts_on"], name: "index_offers_on_starts_on"
    t.index ["travel_agency_id"], name: "index_offers_on_travel_agency_id"
  end

  create_table "travel_agencies", force: :cascade do |t|
    t.string "name", null: false
    t.string "name_id", null: false
    t.text "description"
    t.string "url", null: false
    t.string "next_page_url"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "travel_agency_hotels", force: :cascade do |t|
    t.bigint "travel_agency_id", null: false
    t.bigint "hotel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hotel_id"], name: "index_travel_agency_hotels_on_hotel_id"
    t.index ["travel_agency_id"], name: "index_travel_agency_hotels_on_travel_agency_id"
  end

  add_foreign_key "hotels", "countries"
  add_foreign_key "hotels", "travel_agencies"
  add_foreign_key "offers", "hotels"
  add_foreign_key "offers", "travel_agencies"
  add_foreign_key "travel_agency_hotels", "hotels"
  add_foreign_key "travel_agency_hotels", "travel_agencies"
end
