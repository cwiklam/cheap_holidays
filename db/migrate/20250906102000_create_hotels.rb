# frozen_string_literal: true
class CreateHotels < ActiveRecord::Migration[8.0]
  def change
    create_table :hotels do |t|
      t.string  :name, null: false
      t.string  :url
      t.string  :image_url
      t.references :country, foreign_key: true
      t.references :travel_agency, foreign_key: true
      t.datetime :source_fetched_at
      t.jsonb :raw_data, default: {}
      t.timestamps
    end

    add_index :hotels, :name
    add_index :hotels, :url
    add_index :hotels, [:travel_agency_id, :url]
    add_index :hotels, [:travel_agency_id, :name]
  end
end

