# == Schema Information
#
# Table name: offers
#
#  id                :integer          not null, primary key
#  hotel_id          :integer          not null
#  travel_agency_id  :integer          not null
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
#  index_offers_on_travel_agency_id  (travel_agency_id)
#

# frozen_string_literal: true
class Offer < ApplicationRecord
  belongs_to :hotel
  belongs_to :travel_agency

  validates :name, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :url, length: { maximum: 2000 }, allow_blank: true

  scope :recent, -> { order(created_at: :desc) }
  scope :for_start, ->(date_fragment) { where("starts_on ILIKE ?", "%#{date_fragment}%") if date_fragment.present? }

  DATE_RANGE_REGEX = /(\d{1,2})[.](\d{1,2})(?:[.](\d{4}))?\s*[\-–]\s*(\d{1,2})[.](\d{1,2})[.](\d{4})/
  DAYS_IN_PAREN_REGEX = /\((\d+)\s*dni\)/i

  def parsed_start_date
    return @parsed_start_date if defined?(@parsed_start_date)
    @parsed_start_date = begin
      str = starts_on.to_s
      if str =~ DATE_RANGE_REGEX
        sd, sm, sy_opt, _ed, _em, ey = $1.to_i, $2.to_i, $3, $4.to_i, $5.to_i, $6.to_i
        sy = sy_opt ? sy_opt.to_i : ey
        Date.new(sy, sm, sd) rescue nil
      else
        Date.parse(str) rescue nil
      end
    end
  end

  def duration_days
    return @duration_days if defined?(@duration_days)
    @duration_days = begin
      str = starts_on.to_s
      if str =~ DAYS_IN_PAREN_REGEX
        $1.to_i
      elsif str =~ DATE_RANGE_REGEX
        sd, sm, sy_opt, ed, em, ey = $1.to_i, $2.to_i, $3, $4.to_i, $5.to_i, $6.to_i
        sy = sy_opt ? sy_opt.to_i : ey
        s = Date.new(sy, sm, sd) rescue nil
        e = Date.new(ey, em, ed) rescue nil
        (e - s).to_i if s && e
      end
    end
  end
end
