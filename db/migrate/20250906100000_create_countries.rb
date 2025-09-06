# frozen_string_literal: true
class CreateCountries < ActiveRecord::Migration[8.0]
  def change
    create_table :countries do |t|
      t.string :name, null: false
      t.string :normalized_name, null: false
      t.string :iso_code
      t.timestamps
    end
    add_index :countries, :normalized_name, unique: true
  end
end

