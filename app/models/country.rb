# == Schema Information
#
# Table name: countries
#
#  id              :integer          not null, primary key
#  name            :string           not null
#  normalized_name :string           not null
#  iso_code        :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#
# Indexes
#
#  index_countries_on_normalized_name  (normalized_name) UNIQUE
#

# frozen_string_literal: true
class Country < ApplicationRecord
  has_many :hotels, dependent: :nullify

  before_validation :set_normalized_name

  validates :name, presence: true
  validates :normalized_name, presence: true, uniqueness: true

  # Normalizuje nazwę (lowercase + pojedyncze spacje)
  def self.normalize(str)
    str.to_s.downcase.gsub(/\s+/, ' ').strip
  end

  private

  def set_normalized_name
    self.normalized_name = self.class.normalize(name) if name.present?
  end
end
