# frozen_string_literal: true
class Country < ApplicationRecord
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


