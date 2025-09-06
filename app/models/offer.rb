# == Schema Information
#
# Table name: offers
#
#  id                :integer          not null, primary key
#  hotel_id          :integer          not null
#  name              :string           not null
#  url               :string
#  price             :decimal(12, 2)
#  price_raw         :string
#  starts_on         :string
#  source_fetched_at :datetime
#  raw_data          :jsonb            default("{}")
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  index_offers_on_hotel_id          (hotel_id)
#  index_offers_on_hotel_url_starts  (hotel_id,url,starts_on) UNIQUE
#  index_offers_on_price             (price)
#  index_offers_on_starts_on         (starts_on)
#

# frozen_string_literal: true
class Offer < ApplicationRecord
  belongs_to :hotel
  belongs_to :travel_agency, optional: true
  belongs_to :country, optional: true

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :url, length: { maximum: 2000 }, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_start, ->(date_fragment) { where("starts_on ILIKE ?", "%#{date_fragment}%") if date_fragment.present? }
end

