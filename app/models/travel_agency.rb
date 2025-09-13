# == Schema Information
#
# Table name: travel_agencies
#
#  id            :integer          not null, primary key
#  name          :string           not null
#  name_id       :string           not null
#  description   :text
#  url           :string           not null
#  next_page_url :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#

# frozen_string_literal: true

class TravelAgency < ApplicationRecord
  has_many :travel_agency_hotels, dependent: :destroy
  has_many :hotels, dependent: :nullify, through: :travel_agency_hotels
  has_many :offers, dependent: :destroy

  # Validations
  validates :name, presence: true
  validates :url, presence: true, format: { with: %r{\Ahttps?://}i, message: "must start with http:// or https://" }
end
