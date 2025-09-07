class CreateTravelAgencyHotels < ActiveRecord::Migration[8.0]
  def change
    create_table :travel_agency_hotels do |t|
      t.references :travel_agency, null: false, foreign_key: true
      t.references :hotel, null: false, foreign_key: true

      t.timestamps
    end
  end
end
