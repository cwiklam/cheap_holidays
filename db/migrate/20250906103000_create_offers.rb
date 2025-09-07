# frozen_string_literal: true
class CreateOffers < ActiveRecord::Migration[8.0]
  def change
    create_table :offers do |t|
      t.references :hotel, null: false, foreign_key: true
      t.references :travel_agency, null: false, foreign_key: true
      t.string  :name, null: false
      t.string  :url
      t.decimal :price, precision: 12, scale: 2
      t.string  :price_raw
      t.string  :starts_on
      t.datetime :source_fetched_at
      t.jsonb :raw_data, default: {}
      t.timestamps
    end

    add_index :offers, [:hotel_id, :url, :starts_on], unique: true, name: "index_offers_on_hotel_url_starts"
    add_index :offers, :starts_on
    add_index :offers, :price
  end
end

