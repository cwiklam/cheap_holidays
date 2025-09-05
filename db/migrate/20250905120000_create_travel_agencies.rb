# frozen_string_literal: true

class CreateTravelAgencies < ActiveRecord::Migration[8.0]
  def change
    create_table :travel_agencies do |t|
      t.string  :name, null: false
      t.text    :description
      t.string  :url, null: false

      t.timestamps
    end
  end
end

