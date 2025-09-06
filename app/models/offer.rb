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

