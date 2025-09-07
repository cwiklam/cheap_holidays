# == Schema Information
#
# Table name: hotels
#
#  id                :integer          not null, primary key
#  name              :string           not null
#  url               :string
#  image_url         :string
#  country_id        :integer
#  travel_agency_id  :integer
#  source_fetched_at :datetime
#  raw_data          :jsonb            default("{}")
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_hotels_on_country_id                 (country_id)
#  index_hotels_on_name                       (name)
#  index_hotels_on_travel_agency_id           (travel_agency_id)
#  index_hotels_on_travel_agency_id_and_name  (travel_agency_id,name)
#  index_hotels_on_travel_agency_id_and_url   (travel_agency_id,url)
#  index_hotels_on_url                        (url)
#

# frozen_string_literal: true
class Hotel < ApplicationRecord
  belongs_to :country, optional: true

  has_many :travel_agency_hotels, dependent: :destroy
  has_many :travel_agenciec, dependent: :nullify, through: :travel_agency_hotels
  has_many :offers, dependent: :destroy

  validates :name, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
