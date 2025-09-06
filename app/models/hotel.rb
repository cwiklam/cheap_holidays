# frozen_string_literal: true
class Hotel < ApplicationRecord
  belongs_to :country, optional: true
  has_many :offers, dependent: :destroy

  validates :name, presence: true

  scope :recent, -> { order(created_at: :desc) }
end
