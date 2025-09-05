# frozen_string_literal: true

class TravelAgency < ApplicationRecord

  # Validations
  validates :name, presence: true
  validates :url, presence: true, format: { with: %r{\Ahttps?://}i, message: "must start with http:// or https://" }
end

